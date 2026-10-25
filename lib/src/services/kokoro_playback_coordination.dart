import 'tts_engine.dart';
import 'audio_artifact_store.dart';

/// Playback ownership is generation + chunk, even when immutable content paths
/// are reused. Late releases cannot consume a newer generation's pin.
class KokoroPlaybackArtifactPins {
  KokoroPlaybackArtifactPins(this.registry);
  final AudioArtifactPins registry;
  final Map<String, AudioArtifactPin> _owned = {};
  int get length => _owned.length;
  String _key(String generation, String chunk) => '$generation\u0000$chunk';
  void pin(String generation, String chunk, String path) =>
      _owned.putIfAbsent(_key(generation, chunk), () => registry.pin(path));
  void release(String generation, String chunk) =>
      _owned.remove(_key(generation, chunk))?.release();
  Map<String, AudioArtifactPin> snapshot({String? generation}) =>
      Map.unmodifiable({
        for (final entry in _owned.entries)
          if (generation == null || entry.key.startsWith('$generation\u0000'))
            entry.key: entry.value,
      });
  void releaseSnapshot(Map<String, AudioArtifactPin> snapshot) {
    for (final entry in snapshot.entries) {
      if (identical(_owned[entry.key], entry.value)) {
        _owned.remove(entry.key);
        entry.value.release();
      }
    }
  }
}

/// Runs inside the engine's serialized native mutation slot. Even a platform
/// install that finishes or fails after supersession must settle its cleanup
/// before that slot admits the newest document/revision.
Future<bool> kokoroInstallPreparedPlayback({
  required bool Function() isCurrent,
  required Future<void> Function() install,
  required Future<void> Function() clearStale,
}) async {
  if (!isCurrent()) return false;
  try {
    await install();
  } catch (_) {
    if (isCurrent()) rethrow;
    await clearStale();
    return false;
  }
  if (isCurrent()) return true;
  await clearStale();
  return false;
}

/// Completed native WAVs retain admission credit while boundary correction and
/// playlist publication are pending. Publication replaces this conservative raw
/// duration with the corrected duration; it never opens an accounting gap.
class KokoroProducedAudioCredit {
  final Map<String, Duration> _durations = {};
  void reserve(String chunkId, Duration duration) {
    if (duration <= Duration.zero) throw ArgumentError.value(duration);
    _durations[chunkId] = duration;
  }

  Duration unpublishedLead(Iterable<String> representedChunkIds) {
    final represented = representedChunkIds.toSet();
    return _durations.entries
        .where((entry) => !represented.contains(entry.key))
        .fold(Duration.zero, (sum, entry) => sum + entry.value);
  }

  void published(Iterable<String> chunkIds) {
    for (final id in chunkIds) {
      _durations.remove(id);
    }
  }

  void clear() => _durations.clear();
}

/// A preparation producer cannot join its own task drain. Cancel inference and
/// clear native playback before publishing the terminal failure instead.
Future<void> kokoroTerminatePreparationFailure({
  required void Function() invalidate,
  required bool Function() isCurrent,
  required Future<void> Function() cancel,
  required Future<void> Function() reset,
  required void Function(List<Object> cleanupErrors) report,
}) async {
  invalidate();
  final cleanupErrors = <Object>[];
  try {
    await cancel();
  } catch (error) {
    cleanupErrors.add(error);
  }
  if (!isCurrent()) return;
  try {
    await reset();
  } catch (error) {
    cleanupErrors.add(error);
  }
  if (isCurrent()) report(cleanupErrors);
}

/// End-of-document and a new speak request join the same in-flight reset.
/// A replacement may install sources only after the old stop/clear has drained.
class KokoroPlaybackResetBarrier {
  KokoroPlaybackResetBarrier(this._reset);
  final Future<void> Function() _reset;
  Future<void>? _pending;
  Future<void> reset() =>
      _pending ??= _reset().whenComplete(() => _pending = null);
}

/// Serial native playlist mutations have an owned failure route. A rejected
/// mutation is handled before the next operation, and cannot poison the drain
/// future used by reset/replay. The bool distinguishes handled failure from a
/// successfully committed mutation.
class KokoroPlaylistMutationQueue {
  Future<void> _tail = Future<void>.value();

  Future<bool> run(
    Future<void> Function() action, {
    required Future<void> Function(Object, StackTrace) onFailure,
  }) {
    final result = _tail.then((_) async {
      try {
        await action();
        return true;
      } catch (error, stack) {
        await onFailure(error, stack);
        return false;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> get drained => _tail;
}

/// Natural completion may owe a release to an export lease. That debt belongs
/// only to its resource/playback epochs, never a replacement or replay context.
class KokoroDeferredResourceRelease {
  ({int resource, int playback, Future<void> resetDrained})? _pending;
  void defer({
    required int resourceEpoch,
    required int playbackEpoch,
    Future<void>? resetDrained,
  }) {
    _pending = (
      resource: resourceEpoch,
      playback: playbackEpoch,
      resetDrained: resetDrained ?? Future<void>.value(),
    );
  }

  Future<bool> takeIfCurrent({
    required int Function() resourceEpoch,
    required int Function() playbackEpoch,
    required bool Function() generationActive,
  }) async {
    while (true) {
      final pending = _pending;
      if (pending == null) return false;
      await pending.resetDrained;
      // A replay may itself have completed while the previous reset drained.
      // Join that newer completion rather than consume its debt prematurely.
      if (pending != _pending) continue;
      _pending = null;
      return pending.resource == resourceEpoch() &&
          pending.playback == playbackEpoch() &&
          !generationActive();
    }
  }
}

class KokoroPlaybackQueueSnapshot {
  const KokoroPlaybackQueueSnapshot({
    required this.activeChunkCount,
    required this.currentChunkIndex,
    required this.currentQueueBaseIndex,
    required this.pendingChunkCount,
    required this.remainingPlannedChunkCount,
    this.playerRelativeIndex,
  });

  final int activeChunkCount;
  final int currentChunkIndex;
  final int currentQueueBaseIndex;
  final int pendingChunkCount;
  final int remainingPlannedChunkCount;
  final int? playerRelativeIndex;
}

enum KokoroForwardRecoveryAction {
  none,
  waitForPreparedAudio,
  resumeFromNextBufferedChunk,
}

class KokoroForwardRecoveryPlan {
  const KokoroForwardRecoveryPlan._({
    required this.action,
    this.nextChunkIndex,
  });

  const KokoroForwardRecoveryPlan.none()
    : this._(action: KokoroForwardRecoveryAction.none);

  const KokoroForwardRecoveryPlan.waitForPreparedAudio()
    : this._(action: KokoroForwardRecoveryAction.waitForPreparedAudio);

  const KokoroForwardRecoveryPlan.resumeFromNextBufferedChunk(
    int nextChunkIndex,
  ) : this._(
        action: KokoroForwardRecoveryAction.resumeFromNextBufferedChunk,
        nextChunkIndex: nextChunkIndex,
      );

  final KokoroForwardRecoveryAction action;
  final int? nextChunkIndex;
}

const Duration kokoroTargetBufferedLeadTime = Duration(seconds: 8);
const Duration kokoroLowWaterBufferedLeadTime = Duration(seconds: 4);
const Duration kokoroCriticalBufferedLeadTime = Duration(seconds: 2);
const Duration kokoroStartupMinimumBufferedLeadTime = Duration(seconds: 4);
const int kokoroStartupMinimumBufferedChunkCount = 2;
const int kokoroStartupPreparedChunkWindow = 3;

/// Legacy text-only callers can have more chunks than pipeline capacity. Only
/// this bounded prefix is synchronously admitted before the player may start;
/// the remainder belongs to a separately cancellable producer.
class KokoroStartupChunkWindow<T> {
  KokoroStartupChunkWindow(List<T> chunks)
    : startup = List.unmodifiable(
        chunks.take(kokoroStartupPreparedChunkWindow),
      ),
      tail = List.unmodifiable(chunks.skip(kokoroStartupPreparedChunkWindow));
  final List<T> startup;
  final List<T> tail;
}

double kokoroNormalizeSpeechRate(double requested) {
  if (!requested.isFinite || requested <= 0) {
    throw ArgumentError.value(requested, 'speechRate');
  }
  return requested.clamp(0.7, 1.4).toDouble();
}

/// PCM duration already incorporates synthesis rate. Only transport speed
/// changes how long that finalized audio remains playable in wall time.
Duration kokoroPlayableLead(Duration audioLead, {double playerSpeed = 1}) {
  if (!playerSpeed.isFinite || playerSpeed <= 0) {
    throw ArgumentError.value(playerSpeed, 'playerSpeed');
  }
  return Duration(
    microseconds: (audioLead.inMicroseconds / playerSpeed).round(),
  );
}

TtsBufferPressure kokoroBufferPressureForLeadTime(Duration leadTime) {
  if (leadTime <= kokoroCriticalBufferedLeadTime) {
    return TtsBufferPressure.critical;
  }
  if (leadTime <= kokoroLowWaterBufferedLeadTime) {
    return TtsBufferPressure.lowWater;
  }
  return TtsBufferPressure.healthy;
}

bool kokoroIsStartupWarmEnough({
  required int bufferedChunkCount,
  required Duration bufferedLeadTime,
  required int pendingChunkCount,
  required int remainingPlannedChunkCount,
  double playerSpeed = 1,
}) {
  final effectiveLead = kokoroPlayableLead(
    bufferedLeadTime,
    playerSpeed: playerSpeed,
  );
  final hasFutureWork = pendingChunkCount > 0 || remainingPlannedChunkCount > 0;
  if (!hasFutureWork) {
    return true;
  }

  if (effectiveLead >= kokoroTargetBufferedLeadTime) {
    return true;
  }

  return bufferedChunkCount >= kokoroStartupMinimumBufferedChunkCount &&
      effectiveLead >= kokoroStartupMinimumBufferedLeadTime;
}

class KokoroRecoveryWordBoundary {
  const KokoroRecoveryWordBoundary({
    required this.start,
    required this.end,
    required this.word,
  });

  final int start;
  final int end;
  final String word;
}

class KokoroRecoveryWordSlice {
  const KokoroRecoveryWordSlice({
    required this.startWordOffset,
    required this.endWordOffset,
  });

  final int startWordOffset;
  final int endWordOffset;

  int get wordCount => endWordOffset - startWordOffset;
}

bool kokoroShouldEnterUnderrunRecovery(KokoroPlaybackQueueSnapshot snapshot) {
  return kokoroHasBufferedFutureChunks(snapshot) ||
      snapshot.pendingChunkCount > 0 ||
      snapshot.remainingPlannedChunkCount > 0;
}

KokoroForwardRecoveryPlan kokoroPlanForwardRecovery(
  KokoroPlaybackQueueSnapshot snapshot,
) {
  final nextChunkIndex = kokoroNextRecoveryStartIndex(snapshot);
  if (nextChunkIndex != null) {
    return KokoroForwardRecoveryPlan.resumeFromNextBufferedChunk(
      nextChunkIndex,
    );
  }
  if (snapshot.pendingChunkCount > 0 ||
      snapshot.remainingPlannedChunkCount > 0) {
    return const KokoroForwardRecoveryPlan.waitForPreparedAudio();
  }
  return const KokoroForwardRecoveryPlan.none();
}

bool kokoroHasBufferedFutureChunks(KokoroPlaybackQueueSnapshot snapshot) {
  return kokoroNextRecoveryStartIndex(snapshot) != null;
}

int? kokoroNextRecoveryStartIndex(KokoroPlaybackQueueSnapshot snapshot) {
  if (snapshot.activeChunkCount <= 0) {
    return null;
  }

  final absolutePlayerIndex = snapshot.playerRelativeIndex == null
      ? snapshot.currentChunkIndex
      : snapshot.currentQueueBaseIndex + snapshot.playerRelativeIndex!;
  final lastConsumedIndex = _clampChunkIndex(
    snapshot,
    absolutePlayerIndex > snapshot.currentChunkIndex
        ? absolutePlayerIndex
        : snapshot.currentChunkIndex,
  );
  final nextChunkIndex = lastConsumedIndex + 1;
  if (nextChunkIndex >= snapshot.activeChunkCount) {
    return null;
  }
  return nextChunkIndex;
}

int _clampChunkIndex(KokoroPlaybackQueueSnapshot snapshot, int index) {
  if (snapshot.activeChunkCount <= 0) {
    return 0;
  }
  if (index < 0) {
    return 0;
  }
  if (index >= snapshot.activeChunkCount) {
    return snapshot.activeChunkCount - 1;
  }
  return index;
}

List<KokoroRecoveryWordSlice> kokoroPlanRecoverableChunkSlices({
  required List<KokoroRecoveryWordBoundary> wordBoundaries,
  int preferredTargetWords = 8,
  int minimumSliceWords = 3,
}) {
  if (wordBoundaries.length < minimumSliceWords * 2) {
    return const <KokoroRecoveryWordSlice>[];
  }

  final slices = <KokoroRecoveryWordSlice>[];
  var cursor = 0;
  while (cursor < wordBoundaries.length) {
    final remaining = wordBoundaries.length - cursor;
    if (remaining <= preferredTargetWords) {
      slices.add(
        KokoroRecoveryWordSlice(
          startWordOffset: cursor,
          endWordOffset: wordBoundaries.length,
        ),
      );
      break;
    }

    final minEnd = cursor + minimumSliceWords;
    final maxEnd = (cursor + preferredTargetWords + 2)
        .clamp(minEnd, wordBoundaries.length - minimumSliceWords)
        .toInt();
    final preferredEnd = (cursor + preferredTargetWords)
        .clamp(minEnd, maxEnd)
        .toInt();
    final chosenEnd =
        _findRecoveryBoundary(
          wordBoundaries: wordBoundaries,
          minEnd: minEnd,
          preferredEnd: preferredEnd,
          maxEnd: maxEnd,
        ) ??
        preferredEnd;

    slices.add(
      KokoroRecoveryWordSlice(
        startWordOffset: cursor,
        endWordOffset: chosenEnd,
      ),
    );
    cursor = chosenEnd;
  }

  if (slices.length <= 1 ||
      slices.any((slice) => slice.wordCount < minimumSliceWords)) {
    return const <KokoroRecoveryWordSlice>[];
  }
  return List<KokoroRecoveryWordSlice>.unmodifiable(slices);
}

List<T> kokoroBuildInitialPlaybackQueue<T>({
  required T firstChunk,
  required Iterable<T> stagedChunks,
  required String Function(T chunk) chunkIdOf,
  required int Function(T chunk) startWordIndexOf,
  required int Function(T chunk) startOffsetOf,
}) {
  final chunksById = <String, T>{chunkIdOf(firstChunk): firstChunk};
  for (final chunk in stagedChunks) {
    chunksById[chunkIdOf(chunk)] = chunk;
  }

  final ordered = chunksById.values.toList(growable: false)
    ..sort((left, right) {
      final wordComparison = startWordIndexOf(
        left,
      ).compareTo(startWordIndexOf(right));
      if (wordComparison != 0) {
        return wordComparison;
      }
      final offsetComparison = startOffsetOf(
        left,
      ).compareTo(startOffsetOf(right));
      if (offsetComparison != 0) {
        return offsetComparison;
      }
      return chunkIdOf(left).compareTo(chunkIdOf(right));
    });
  return ordered;
}

int kokoroPlaybackInsertIndex<T>({
  required List<T> activeChunks,
  required T incomingChunk,
  required String Function(T chunk) chunkIdOf,
  required int Function(T chunk) startWordIndexOf,
  required int Function(T chunk) startOffsetOf,
}) {
  for (var index = 0; index < activeChunks.length; index += 1) {
    final comparison = _comparePlaybackChunkOrder(
      activeChunks[index],
      incomingChunk,
      chunkIdOf: chunkIdOf,
      startWordIndexOf: startWordIndexOf,
      startOffsetOf: startOffsetOf,
    );
    if (comparison >= 0) {
      return index;
    }
  }
  return activeChunks.length;
}

int? kokoroFirstFutureReplacementIndex<T>({
  required List<T> activeChunks,
  required int currentChunkIndex,
  required int replacementStartWordIndex,
  required int Function(T chunk) startWordIndexOf,
}) {
  final startIndex = currentChunkIndex + 1;
  for (var index = startIndex; index < activeChunks.length; index += 1) {
    if (startWordIndexOf(activeChunks[index]) >= replacementStartWordIndex) {
      return index;
    }
  }
  return null;
}

int _comparePlaybackChunkOrder<T>(
  T left,
  T right, {
  required String Function(T chunk) chunkIdOf,
  required int Function(T chunk) startWordIndexOf,
  required int Function(T chunk) startOffsetOf,
}) {
  final wordComparison = startWordIndexOf(
    left,
  ).compareTo(startWordIndexOf(right));
  if (wordComparison != 0) {
    return wordComparison;
  }
  final offsetComparison = startOffsetOf(left).compareTo(startOffsetOf(right));
  if (offsetComparison != 0) {
    return offsetComparison;
  }
  return chunkIdOf(left).compareTo(chunkIdOf(right));
}

int? _findRecoveryBoundary({
  required List<KokoroRecoveryWordBoundary> wordBoundaries,
  required int minEnd,
  required int preferredEnd,
  required int maxEnd,
}) {
  int? weakMatch;

  for (var end = preferredEnd; end >= minEnd; end -= 1) {
    final boundaryWord = wordBoundaries[end - 1].word;
    if (_isStrongRecoveryBoundary(boundaryWord)) {
      return end;
    }
    weakMatch ??= _isWeakRecoveryBoundary(boundaryWord) ? end : null;
  }
  for (var end = preferredEnd + 1; end <= maxEnd; end += 1) {
    final boundaryWord = wordBoundaries[end - 1].word;
    if (_isStrongRecoveryBoundary(boundaryWord)) {
      return end;
    }
    weakMatch ??= _isWeakRecoveryBoundary(boundaryWord) ? end : null;
  }

  return weakMatch;
}

bool _isStrongRecoveryBoundary(String word) {
  final terminal = _terminalPunctuationCodeUnit(word);
  return terminal == 0x2E || terminal == 0x21 || terminal == 0x3F;
}

bool _isWeakRecoveryBoundary(String word) {
  final terminal = _terminalPunctuationCodeUnit(word);
  return terminal == 0x2C || terminal == 0x3B || terminal == 0x3A;
}

int? _terminalPunctuationCodeUnit(String word) {
  if (word.isEmpty) {
    return null;
  }

  var index = word.length - 1;
  while (index >= 0) {
    final codeUnit = word.codeUnitAt(index);
    final isClosingQuote =
        codeUnit == 0x22 ||
        codeUnit == 0x27 ||
        codeUnit == 0x2019 ||
        codeUnit == 0x201D;
    if (!isClosingQuote) {
      return codeUnit;
    }
    index -= 1;
  }

  return null;
}

/// Hysteresis uses playable wall time. Kokoro's synthesis rate is already baked
/// into PCM duration; only an independent player speed divides that duration.
class KokoroBufferAdmission {
  KokoroBufferAdmission({
    this.high = kokoroTargetBufferedLeadTime,
    this.low = kokoroLowWaterBufferedLeadTime,
    this.maxChunks = 64,
  }) {
    if (low >= high || maxChunks < 1) {
      throw ArgumentError('Invalid buffer policy');
    }
  }
  final Duration high;
  final Duration low;
  final int maxChunks;
  bool _full = false;
  bool startupCapacityExhausted({
    required Duration audioLead,
    required int bufferedChunkCount,
    required int pendingChunkCount,
    required int remainingPlannedChunkCount,
    double playerSpeed = 1,
  }) {
    final effective = kokoroPlayableLead(audioLead, playerSpeed: playerSpeed);
    return bufferedChunkCount >= maxChunks &&
        pendingChunkCount == 0 &&
        remainingPlannedChunkCount > 0 &&
        effective < kokoroStartupMinimumBufferedLeadTime;
  }

  bool admits({
    required Duration audioLead,
    required int outstandingChunks,
    double playerSpeed = 1,
  }) {
    final effective = kokoroPlayableLead(audioLead, playerSpeed: playerSpeed);
    if (_full && effective <= low) _full = false;
    if (effective >= high) _full = true;
    return !_full && outstandingChunks < maxChunks;
  }
}
