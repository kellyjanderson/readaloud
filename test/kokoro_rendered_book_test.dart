import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/models/native_speech_turn.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/services/speech_audio_packet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final hasBoundaryEvidence in [false, true]) {
    test(
      'finalized callback preserves ${hasBoundaryEvidence ? 'exact boundary evidence' : 'unknown boundary evidence'}',
      () async {
        TtsFinalizedAudioScene? received;
        final request = TtsSpeakRequest(
          text: 'one two',
          onRenderedScene: (scene) async => received = scene,
        );
        final cancellation = Completer<void>();
        await request.onRenderedScene!(
          TtsFinalizedAudioScene(
            documentId: 'book',
            generationId: 'generation-1',
            sceneId: 'scene-1',
            text: 'one two',
            engineSpeakText: 'one two',
            startWordIndex: 0,
            endWordIndex: 2,
            startOffset: 0,
            sceneTurns: const [],
            preparedBindings: const [],
            audioPath: '/validated-test/corrected.wav',
            duration: const Duration(seconds: 1),
            engineId: 'kokoro',
            engineVersion: '12',
            normalizationVersion: 'normalization-v1',
            capabilityProfileId: 'kokoro',
            synthesisIdentity: 'synthesis-content',
            translationSignature: 'translation-content',
            synthesisRate: 1,
            assignmentRevision: 7,
            cancelled: cancellation.future,
            isCurrent: () => true,
            rawAudioPath: '/validated-test/raw.wav',
            rawArtifactIdentity: 'wav-sha256:raw',
            predecessorRawArtifactIdentity: 'wav-sha256:predecessor',
            boundaryPolicyVersion: 'boundary-native-rate-v2',
            boundaryClass: hasBoundaryEvidence ? 'paragraph' : null,
            trailingSilenceMicros: hasBoundaryEvidence ? 123456 : null,
          ),
        );
        expect(
          received!.boundaryClass,
          hasBoundaryEvidence ? 'paragraph' : isNull,
        );
        expect(
          received!.trailingSilenceMicros,
          hasBoundaryEvidence ? 123456 : isNull,
        );
        expect(received!.boundaryPolicyVersion, 'boundary-native-rate-v2');
        expect(received!.rawAudioPath, '/validated-test/raw.wav');
        expect(received!.rawArtifactIdentity, 'wav-sha256:raw');
        expect(
          received!.predecessorRawArtifactIdentity,
          'wav-sha256:predecessor',
        );
        expect(received!.audioPath, '/validated-test/corrected.wav');
      },
    );
  }

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

  test(
    'packets play before publication, retain scene identity and defer EOF',
    () async {
      final temp = Directory.systemTemp.createTempSync('packet-playback-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final player = _FakePlayer();
      final engine = _NoModelEngine(player);
      addTearDown(() => _close(engine));
      final done = Completer<TtsRenderedSceneCompletion>();
      final progress = <TtsProgressUpdate>[];
      final errors = <String>[];
      var completed = 0;
      engine.onProgress = progress.add;
      engine.onError = errors.add;
      engine.onComplete = () => completed++;
      final second = _packetScene(temp, done.future, index: 1, start: 500);
      await engine.playRendered(
        _packetScene(
          temp,
          done.future,
          continuation: TtsRenderedAudioContinuation(
            next: (_, _) async => second,
          ),
        ),
      );
      await _until(() => player.sources.length == 2);
      expect(player.playCalls, 1);
      expect(done.isCompleted, isFalse);
      expect(progress.single.chunkId, 'scene');
      expect(progress.single.chunkAudioDuration, isNull);
      expect(progress.single.elapsedInChunk, isNull);
      expect(engine.currentPlaybackResumeAnchor!.chunkId, 'scene');
      player.moveTo(1);
      player.advance(const Duration(milliseconds: 400));
      expect(progress.last.wordStartIndex, 0);
      player.complete();
      expect(completed, 0);
      expect(progress.last.wordStartIndex, 0);
      done.complete(
        const TtsRenderedSceneCompletion(
          sceneId: 'scene',
          frameCount: 1000,
          packetCount: 2,
          duration: Duration(seconds: 1),
          onsetTrimFrames: 0,
        ),
      );
      await _until(() => completed == 1);
      expect(progress.map((p) => p.chunkId).toSet(), {'scene'});
      expect(progress.last.wordEndIndex, 2);
      expect(player.installCalls, 1);
      expect(player.addCalls, 1);
      expect(errors, isEmpty);
      expect(engine.debugPlaybackPinCount, 0);
    },
  );

  test(
    'pruning retains native head when logical index leads, and pins until removal ACK',
    () async {
      final player = _FakePlayer()..removeGate = Completer<void>();
      final engine = _NoModelEngine(player);
      addTearDown(() => _close(engine));
      final last = _scene(
        id: 'last',
        start: 4,
        end: 6,
        sourceEnd: 6,
        sequence: 2,
        offset: 16,
      );
      final middle = _scene(
        id: 'middle',
        start: 2,
        end: 4,
        sourceEnd: 6,
        sequence: 1,
        offset: 8,
        continuation: TtsRenderedAudioContinuation(next: (_, _) async => last),
      );
      await engine.playRendered(
        _scene(
          id: 'first',
          sourceEnd: 6,
          continuation: TtsRenderedAudioContinuation(
            next: (_, _) async => middle,
          ),
        ),
      );
      await _until(() => player.sources.length == 3);
      final sourcePaths = [...player.sources];
      expect(engine.debugPlaybackPinCount, 3);
      // onComplete advertises index 1 while native playback still owns source 0.
      player.announceNextBeforeNativeAdvance(1);
      await Future<void>.delayed(Duration.zero);
      expect(player.removeCalls, 0);
      expect(player.sources, sourcePaths);
      expect(engine.debugPlaybackPinCount, 3);
      // Completing the next distinct source proves source 0 is no longer live.
      player.nativeHeadIndex = 1;
      player.announceNextBeforeNativeAdvance(2);
      await _until(() => player.removeCalls == 1);
      expect(player.removalRanges, [(0, 1)]);
      expect(player.sources, sourcePaths); // native ACK is still held
      expect(engine.debugPlaybackPinCount, 3);
      player.removeGate!.complete();
      await _until(() => engine.debugPlaybackPinCount == 2);
      expect(player.sources, sourcePaths.sublist(1));
      expect(player.sources[player.nativeHeadIndex], sourcePaths[1]);
      // The retained predecessor is history, not playable future lead.
      expect(engine.debugPlayableBufferedLead, const Duration(seconds: 1));
    },
  );

  for (final indexJump in [false, true]) {
    test(
      'native ${indexJump ? 'index jump skips' : 'scene transition emits'} verified scene end without final position tick',
      () async {
        final temp = Directory.systemTemp.createTempSync(
          'packet-scene-transition-',
        );
        addTearDown(() => temp.deleteSync(recursive: true));
        final player = _FakePlayer();
        final engine = _NoModelEngine(player);
        addTearDown(() => _close(engine));
        final done = Completer<TtsRenderedSceneCompletion>();
        final progress = <TtsProgressUpdate>[];
        engine.onProgress = progress.add;
        final nextScene = TtsRenderedAudioRequest(
          documentId: 'book',
          manifestIdentity: 'manifest',
          intentRevision: 1,
          sceneId: 'next-scene',
          text: 'five six',
          startWordIndex: 4,
          endWordIndex: 6,
          sourceEndWordIndex: 6,
          startOffset: 19,
          sceneTurns: const [],
          audioPath: '/validated-test/next-scene.wav',
          format: const TtsRenderedAudioFormat(
            sampleRate: 1000,
            channels: 1,
            bitsPerSample: 16,
          ),
          duration: const Duration(seconds: 1),
          rangeSequence: 2,
        );
        final second = _packetScene(
          temp,
          done.future,
          index: 1,
          start: 500,
          sourceEnd: 6,
          text: 'one two three four',
          continuation: TtsRenderedAudioContinuation(
            next: (_, _) async => nextScene,
          ),
        );
        await engine.playRendered(
          _packetScene(
            temp,
            done.future,
            sourceEnd: 6,
            text: 'one two three four',
            continuation: TtsRenderedAudioContinuation(
              next: (_, _) async => second,
            ),
          ),
        );
        await _until(() => player.sources.length == 2);
        done.complete(
          const TtsRenderedSceneCompletion(
            sceneId: 'scene',
            frameCount: 1000,
            packetCount: 2,
            duration: Duration(seconds: 1),
            onsetTrimFrames: 0,
          ),
        );
        await _until(() => player.sources.length == 3);
        if (!indexJump) player.moveTo(1);
        // A same-scene packet transition reports its cumulative position and
        // cannot finalize the remaining word, even after publication succeeds.
        expect(
          progress.map((p) => p.wordStartIndex).toList(),
          indexJump ? [0] : [0, 2],
        );
        // No final position update is emitted for packet 1.
        player.moveTo(2);
        expect(
          progress.map((p) => (p.chunkId, p.wordStartIndex)).toList(),
          indexJump
              ? [('scene', 0), ('next-scene', 4)]
              : [('scene', 0), ('scene', 2), ('scene', 3), ('next-scene', 4)],
        );
        if (!indexJump) {
          expect(progress[2].wordEndIndex, 4);
          expect(progress[2].chunkAudioDuration, const Duration(seconds: 1));
        }
      },
    );
  }

  for (final allSilent in [false, true]) {
    test(
      'leading silent packets ${allSilent ? 'finish silently' : 'retain exact onset PCM'}',
      () async {
        final temp = Directory.systemTemp.createTempSync('packet-onset-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final player = _FakePlayer();
        final engine = _NoModelEngine(player);
        addTearDown(() => _close(engine));
        final done = Completer<TtsRenderedSceneCompletion>();
        final second = _packetScene(
          temp,
          done.future,
          index: 1,
          start: 500,
          silent: allSilent,
        );
        final first = _packetScene(
          temp,
          done.future,
          silent: true,
          continuation: TtsRenderedAudioContinuation(
            next: (_, _) async => second,
          ),
        );
        final raw = <int>[
          ...File(first.audioPath).readAsBytesSync().sublist(44),
          ...File(second.audioPath).readAsBytesSync().sublist(44),
        ];
        final trim = allSilent ? 880 : 380;
        if (allSilent) {
          done.complete(
            TtsRenderedSceneCompletion(
              sceneId: 'scene',
              frameCount: 1000,
              packetCount: 2,
              duration: const Duration(milliseconds: 120),
              onsetTrimFrames: trim,
            ),
          );
        }
        await engine.playRendered(first);
        await _until(() => player.playCalls == 1);
        expect(player.sources, hasLength(allSilent ? 1 : 2));
        final played = <int>[
          for (final path in player.sources)
            ...File(path).readAsBytesSync().sublist(44),
        ];
        expect(played, raw.sublist(trim * 2));
        if (!allSilent) {
          expect(done.isCompleted, isFalse);
          done.complete(
            TtsRenderedSceneCompletion(
              sceneId: 'scene',
              frameCount: 1000,
              packetCount: 2,
              duration: const Duration(milliseconds: 620),
              onsetTrimFrames: trim,
            ),
          );
        }
      },
    );
  }

  for (final malformed in [true, false]) {
    test(
      'packet ${malformed ? 'coverage refusal' : 'late publication failure'} stops early playback',
      () async {
        final temp = Directory.systemTemp.createTempSync('packet-failure-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final player = _FakePlayer();
        final engine = _NoModelEngine(player);
        addTearDown(() => _close(engine));
        final done = Completer<TtsRenderedSceneCompletion>();
        final errors = <String>[];
        var completed = 0;
        engine.onError = errors.add;
        engine.onComplete = () => completed++;
        final next = Completer<TtsRenderedAudioRequest?>();
        await engine.playRendered(
          _packetScene(
            temp,
            done.future,
            continuation: TtsRenderedAudioContinuation(
              next: (_, _) => next.future,
            ),
          ),
        );
        await _until(() => player.playCalls == 1);
        if (malformed) {
          next.complete(_packetScene(temp, done.future, index: 1, start: 501));
        } else {
          done.completeError(StateError('final publication refused'));
        }
        await _until(() => errors.isNotEmpty);
        await _until(() => engine.debugPlaybackPinCount == 0);
        expect(completed, 0);
        expect(player.addCalls, 0);
        if (malformed) done.completeError(StateError('aborted'));
      },
    );
  }

  test(
    'stop releases packet continuation and ignores late publication failure',
    () async {
      final temp = Directory.systemTemp.createTempSync('packet-stop-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final player = _FakePlayer();
      final engine = _NoModelEngine(player);
      addTearDown(() => _close(engine));
      final done = Completer<TtsRenderedSceneCompletion>();
      final next = Completer<TtsRenderedAudioRequest?>();
      final errors = <String>[];
      engine.onError = errors.add;
      await engine.playRendered(
        _packetScene(
          temp,
          done.future,
          continuation: TtsRenderedAudioContinuation(
            next: (_, _) => next.future,
          ),
        ),
      );
      await _until(() => player.playCalls == 1);
      await engine.stop();
      done.completeError(StateError('obsolete publication'));
      next.completeError(StateError('obsolete pull'));
      await Future<void>.delayed(Duration.zero);
      expect(errors, isEmpty);
      expect(engine.debugPlaybackPinCount, 0);
      expect(engine.pendingPlaybackPreparationTasks, 0);
    },
  );
}

TtsRenderedAudioRequest _packetScene(
  Directory temp,
  Future<TtsRenderedSceneCompletion> completion, {
  int index = 0,
  int start = 0,
  int sourceEnd = 2,
  String text = 'one two',
  bool silent = false,
  TtsRenderedAudioContinuation? continuation,
}) {
  final path = '${temp.path}/packet-$index.wav';
  final header = ByteData(44)
    ..setUint32(0, 0x52494646)
    ..setUint32(4, 1036, Endian.little)
    ..setUint32(8, 0x57415645)
    ..setUint32(12, 0x666d7420)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 1000, Endian.little)
    ..setUint32(28, 2000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461)
    ..setUint32(40, 1000, Endian.little);
  final pcm = ByteData(1000);
  // A deliberately non-silent deterministic fixture tests placement/coverage,
  // not speech quality or acoustic continuity.
  for (var i = 0; i < 500 && !silent; i++) {
    pcm.setInt16(i * 2, i.isEven ? 2000 : -2000, Endian.little);
  }
  File(path).writeAsBytesSync([
    ...header.buffer.asUint8List(),
    ...pcm.buffer.asUint8List(),
  ]);
  return TtsRenderedAudioRequest(
    documentId: 'book',
    manifestIdentity: 'manifest',
    intentRevision: 1,
    sceneId: 'scene',
    text: text,
    startWordIndex: 0,
    endWordIndex: text.split(' ').length,
    sourceEndWordIndex: sourceEnd,
    startOffset: 0,
    sceneTurns: const [],
    audioPath: path,
    format: const TtsRenderedAudioFormat(
      sampleRate: 1000,
      channels: 1,
      bitsPerSample: 16,
    ),
    duration: const Duration(milliseconds: 500),
    rangeSequence: index,
    audioPacket: SpeechAudioPacket(
      sessionId: 'producer',
      generationId: 'producer-generation',
      chunkId: 'scene',
      audioPath: path,
      packetIndex: index,
      frameStart: start,
      frameCount: 500,
      sampleRate: 1000,
    ),
    sceneCompletion: completion,
    continuation: continuation,
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
  Completer<void>? removeGate;
  var nativeHeadIndex = 0;
  var removeCalls = 0;
  final removalRanges = <(int, int)>[];
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
  Future<void> removeAudioSourceRange(int start, int end) async {
    removeCalls++;
    removalRanges.add((start, end));
    if (start <= nativeHeadIndex && nativeHeadIndex < end) {
      throw StateError('Prune removed the still-live native head.');
    }
    await removeGate?.future;
    sources.removeRange(start, end);
    if (start == 0) {
      _index -= end - start;
      nativeHeadIndex -= end - start;
    }
  }

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
    nativeHeadIndex = index;
    indexes.add(index);
  }

  void announceNextBeforeNativeAdvance(int index) {
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
