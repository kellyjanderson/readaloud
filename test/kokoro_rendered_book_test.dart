import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/models/native_speech_turn.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/tts_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rendered scene uses no model and reports admitted source turns',
    () async {
      final player = _FakePlayer();
      final engine = _NoModelEngine(player);
      addTearDown(() => _close(engine));
      final progress = <TtsProgressUpdate>[];
      RenderedAudioPlaybackAcknowledgment? acknowledgment;
      var completed = 0;
      engine.onProgress = progress.add;
      engine.onComplete = () => completed++;
      await engine.playRendered(
        _scene(
          start: 10,
          end: 12,
          sourceEnd: 12,
          offset: 41,
          onReady: (value) => acknowledgment = value,
        ),
      );
      await _until(() => player.playCalls == 1);
      expect(engine.modelCalls, 0);
      expect(acknowledgment!.manifestIdentity, 'manifest-sha256');
      expect(acknowledgment!.intentRevision, 7);
      expect(progress.first.wordStartIndex, 10);
      expect(progress.first.startOffset, 41);
      expect(progress.first.sceneTurns.single.voiceId, 'saved-voice');
      expect(engine.debugPlaybackPinCount, 1);
      player.complete();
      await _until(() => engine.debugPlaybackPinCount == 0);
      expect(completed, 1);
      expect(progress.last.wordEndIndex, 12);
      expect(progress.last.word, 'two');
      expect(engine.modelCalls, 0);
    },
  );

  test(
    'pull continuation preserves spans and completes at verified EOF',
    () async {
      final player = _FakePlayer();
      final engine = _NoModelEngine(player);
      addTearDown(() => _close(engine));
      final errors = <String>[];
      final activations = <int>[];
      final progress = <TtsProgressUpdate>[];
      var pulls = 0;
      var completed = 0;
      engine.onError = errors.add;
      engine.onProgress = progress.add;
      engine.onComplete = () => completed++;
      await engine.playRendered(
        _scene(
          sourceEnd: 4,
          activate: () => activations.add(0),
          continuation: TtsRenderedAudioContinuation(
            next: (sequence, cancelled) async {
              pulls++;
              expect(sequence, 0);
              return _scene(
                start: 2,
                end: 4,
                sourceEnd: 4,
                sequence: 1,
                offset: 8,
                activate: () => activations.add(2),
              );
            },
          ),
        ),
      );
      await _until(() => player.sources.length == 2);
      player.moveTo(1);
      expect(activations, [0, 2]);
      player.complete();
      await _until(() => engine.debugPlaybackPinCount == 0);
      expect(pulls, 1);
      expect(completed, 1);
      expect(errors, isEmpty);
      expect(progress.last.wordEndIndex, 4);
      expect(engine.modelCalls, 0);
    },
  );

  for (final missingContinuation in [false, true]) {
    test(
      'partial coverage ${missingContinuation ? 'without continuation' : 'with null continuation'} is a gap, not EOF',
      () async {
        final player = _FakePlayer();
        final engine = _NoModelEngine(player);
        addTearDown(() => _close(engine));
        final errors = <String>[];
        var completed = 0;
        engine.onError = errors.add;
        engine.onComplete = () => completed++;
        await engine.playRendered(
          _scene(
            sourceEnd: 4,
            continuation: missingContinuation
                ? null
                : TtsRenderedAudioContinuation(
                    next: (_, cancelled) async => null,
                  ),
          ),
        );
        await _until(() => errors.isNotEmpty);
        expect(errors.single, contains('coverage gap at word 2'));
        expect(completed, 0);
        expect(engine.debugPlaybackPinCount, 0);
      },
    );
  }

  test('noncontiguous next scene cannot install or complete', () async {
    final player = _FakePlayer();
    final engine = _NoModelEngine(player);
    addTearDown(() => _close(engine));
    final errors = <String>[];
    engine.onError = errors.add;
    await engine.playRendered(
      _scene(
        sourceEnd: 5,
        continuation: TtsRenderedAudioContinuation(
          next: (_, cancelled) async =>
              _scene(start: 3, end: 5, sourceEnd: 5, sequence: 1, offset: 8),
        ),
      ),
    );
    await _until(() => errors.isNotEmpty);
    expect(errors.single, contains('Non-contiguous'));
    expect(player.addCalls, 0);
    expect(engine.debugPlaybackPinCount, 0);
  });

  for (final lateFailure in [false, true]) {
    test(
      'pause during blocked install suppresses stale ${lateFailure ? 'failure' : 'success'}',
      () async {
        final player = _FakePlayer()..installGate = Completer<void>();
        final engine = _NoModelEngine(player);
        addTearDown(() => _close(engine));
        final errors = <String>[];
        var acknowledgments = 0;
        engine.onError = errors.add;
        await engine.playRendered(_scene(onReady: (_) => acknowledgments++));
        await _until(() => player.installCalls == 1);
        final pausing = engine.pause();
        if (lateFailure) {
          player.installGate!.completeError(StateError('obsolete install'));
        } else {
          player.installGate!.complete();
        }
        await pausing;
        expect(player.playCalls, 0);
        expect(acknowledgments, 0);
        expect(errors, isEmpty);
        expect(player.sources, isEmpty);
        expect(engine.debugPlaybackPinCount, 0);
      },
    );
  }

  test(
    'replacement waits for old install cleanup before new admission',
    () async {
      final player = _FakePlayer()..installGate = Completer<void>();
      final engine = _NoModelEngine(player);
      addTearDown(() => _close(engine));
      final acknowledgments = <String>[];
      await engine.playRendered(
        _scene(id: 'old', onReady: (_) => acknowledgments.add('old')),
      );
      await _until(() => player.installCalls == 1);
      final replacing = engine.playRendered(
        _scene(id: 'new', onReady: (_) => acknowledgments.add('new')),
      );
      player.installGate!.complete();
      await replacing;
      await _until(() => player.playCalls == 1);
      expect(acknowledgments, ['new']);
      expect(player.installCalls, 2);
      expect(player.sources.single, contains('new.wav'));
      expect(engine.debugPlaybackPinCount, 1);
    },
  );

  test(
    'cancellation releases held next-range wait and drops late failure',
    () async {
      final player = _FakePlayer();
      final engine = _NoModelEngine(player);
      addTearDown(() => _close(engine));
      final next = Completer<TtsRenderedAudioRequest?>();
      final called = Completer<void>();
      final errors = <String>[];
      var cancelled = false;
      engine.onError = errors.add;
      await engine.playRendered(
        _scene(
          sourceEnd: 4,
          continuation: TtsRenderedAudioContinuation(
            next: (_, cancellation) {
              cancellation.then((_) => cancelled = true);
              called.complete();
              return next.future;
            },
          ),
        ),
      );
      await called.future;
      await engine.stop();
      expect(cancelled, isTrue);
      expect(engine.pendingPlaybackPreparationTasks, 0);
      next.completeError(StateError('stale extraction failure'));
      await Future<void>.delayed(Duration.zero);
      expect(errors, isEmpty);
      expect(engine.debugPlaybackPinCount, 0);
    },
  );

  test('rendered lookahead waits for existing audio credit', () async {
    final player = _FakePlayer();
    final engine = _NoModelEngine(player);
    addTearDown(() => _close(engine));
    var pulls = 0;
    final request = _scene(
      sourceEnd: 4,
      duration: const Duration(seconds: 12),
      continuation: TtsRenderedAudioContinuation(
        next: (_, cancelled) async {
          pulls++;
          return _scene(start: 2, end: 4, sourceEnd: 4, sequence: 1, offset: 8);
        },
      ),
    );
    await engine.playRendered(request);
    await _until(() => player.playCalls == 1);
    expect(pulls, 0);
    player.advance(const Duration(seconds: 10));
    await _until(() => player.sources.length == 2);
    expect(pulls, 1);
  });

  test(
    'EOF verification held beyond player end preserves completion once',
    () async {
      final player = _FakePlayer();
      final engine = _NoModelEngine(player);
      addTearDown(() => _close(engine));
      final eof = Completer<TtsRenderedAudioRequest?>();
      var completed = 0;
      engine.onComplete = () => completed++;
      await engine.playRendered(
        _scene(
          continuation: TtsRenderedAudioContinuation(
            next: (_, cancelled) => eof.future,
          ),
        ),
      );
      await _until(() => player.playCalls == 1);
      player.complete();
      expect(completed, 0);
      eof.complete(null);
      await _until(() => completed == 1);
      expect(engine.debugPlaybackPinCount, 0);
    },
  );
}

TtsRenderedAudioRequest _scene({
  String id = 'scene',
  int start = 0,
  int end = 2,
  int sourceEnd = 2,
  int offset = 0,
  int sequence = 0,
  void Function(RenderedAudioPlaybackAcknowledgment)? onReady,
  void Function()? activate,
  TtsRenderedAudioContinuation? continuation,
  Duration duration = const Duration(seconds: 1),
}) => TtsRenderedAudioRequest(
  documentId: 'book',
  manifestIdentity: 'manifest-sha256',
  intentRevision: 7,
  sceneId: id,
  text: 'one two',
  startWordIndex: start,
  endWordIndex: end,
  sourceEndWordIndex: sourceEnd,
  startOffset: offset,
  sceneTurns: [
    NativeSpeechTurn(
      voiceId: 'saved-voice',
      text: 'one two',
      segmentIds: ['segment-$sequence'],
      startWord: start,
      endWord: end,
      bindingFingerprint: 'historical-binding',
      bindingRevision: 3,
    ),
  ],
  audioPath: '/validated-test/$id.wav',
  format: const TtsRenderedAudioFormat(
    sampleRate: 24000,
    channels: 1,
    bitsPerSample: 16,
  ),
  duration: duration,
  rangeSequence: sequence,
  onPlaybackReady: onReady,
  onRangeActive: activate,
  continuation: continuation,
);

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Playback did not reach expected state.');
}

Future<void> _close(KokoroTtsEngine engine) async {
  await engine.shutdownResources();
  engine.dispose();
  await Future<void>.delayed(Duration.zero);
}

class _NoModelEngine extends KokoroTtsEngine {
  _NoModelEngine(_FakePlayer player) : super(player: player);
  int modelCalls = 0;
  Never _forbidden() {
    modelCalls++;
    throw StateError('Offline playback must not initialize synthesis.');
  }

  @override
  Future<void> initialize() async => _forbidden();
  @override
  Future<void> prepareSelectedModel() async => _forbidden();
  @override
  Future<List<VoiceProfile>> loadVoices() async => _forbidden();
  @override
  Future<List<PreparedVoiceBinding>> prepareDocumentResources({
    required String documentId,
    required int revision,
    required Set<String> voiceIds,
    required String pronunciationProfileId,
  }) async => _forbidden();
}

/// Implements the real AudioPlayer interface without constructing a native or
/// independently scheduled player. Only engine-driven playlist/progress events.
class _FakePlayer extends Fake implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final indexes = StreamController<int?>.broadcast(sync: true);
  final sources = <String>[];
  Completer<void>? installGate;
  var installCalls = 0;
  var addCalls = 0;
  var playCalls = 0;
  var _index = 0;
  var _position = Duration.zero;
  var _state = PlayerState(false, ProcessingState.ready);
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<int?> get currentIndexStream => indexes.stream;
  @override
  PlayerState get playerState => _state;
  @override
  ProcessingState get processingState => _state.processingState;
  @override
  int? get currentIndex => _index;
  @override
  Duration get position => _position;
  @override
  double get speed => 1;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    installCalls++;
    if (installCalls == 1) await installGate?.future;
    sources
      ..clear()
      ..addAll(audioSources.map(_path));
    _state = PlayerState(false, ProcessingState.ready);
    _index = 0;
    return null;
  }

  String _path(AudioSource source) => (source as UriAudioSource).uri.path;
  @override
  Future<void> addAudioSource(AudioSource source) async {
    addCalls++;
    sources.add(_path(source));
  }

  @override
  Future<void> insertAudioSource(int index, AudioSource source) async =>
      sources.insert(index, _path(source));
  @override
  Future<void> removeAudioSourceRange(int start, int end) async =>
      sources.removeRange(start, end);
  @override
  Future<void> clearAudioSources() async => sources.clear();
  @override
  Future<void> play() async {
    playCalls++;
    _state = PlayerState(true, ProcessingState.ready);
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (index != null) _index = index;
    _state = PlayerState(true, ProcessingState.ready);
  }

  void moveTo(int index) {
    _index = index;
    indexes.add(index);
  }

  void advance(Duration value) {
    _position = value;
    positions.add(value);
  }

  void complete() {
    _state = PlayerState(true, ProcessingState.completed);
    states.add(_state);
  }

  @override
  Future<void> dispose() async {
    await states.close();
    await positions.close();
    await indexes.close();
  }
}
