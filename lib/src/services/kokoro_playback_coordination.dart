import 'tts_engine.dart';

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
}) {
  final hasFutureWork = pendingChunkCount > 0 || remainingPlannedChunkCount > 0;
  if (!hasFutureWork) {
    return true;
  }

  if (bufferedLeadTime >= kokoroTargetBufferedLeadTime) {
    return true;
  }

  return bufferedChunkCount >= kokoroStartupMinimumBufferedChunkCount &&
      bufferedLeadTime >= kokoroStartupMinimumBufferedLeadTime;
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
  if (snapshot.pendingChunkCount > 0 || snapshot.remainingPlannedChunkCount > 0) {
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
    final preferredEnd =
        (cursor + preferredTargetWords).clamp(minEnd, maxEnd).toInt();
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

  if (slices.length <= 1 || slices.any((slice) => slice.wordCount < minimumSliceWords)) {
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
      final wordComparison =
          startWordIndexOf(left).compareTo(startWordIndexOf(right));
      if (wordComparison != 0) {
        return wordComparison;
      }
      final offsetComparison =
          startOffsetOf(left).compareTo(startOffsetOf(right));
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
  final wordComparison =
      startWordIndexOf(left).compareTo(startWordIndexOf(right));
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
