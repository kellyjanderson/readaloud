import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/native_speech_turn.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/rendered_scene_repository.dart';
import 'package:read_aloud/src/services/tts_engine.dart';

void main() {
  late Directory temp;
  late RenderedSceneRepository repository;
  late String audio;
  late String raw;
  const intent = <String, dynamic>{'voice': 'narrator', 'speed': 1.0};
  setUp(() {
    temp = Directory.systemTemp.createTempSync('rendered-scene-test-');
    repository = RenderedSceneRepository(Directory('${temp.path}/durable'));
    audio = '${temp.path}/final.wav';
    raw = '${temp.path}/raw.wav';
    File(audio).writeAsBytesSync(wav(1000));
    File(raw).writeAsBytesSync(wav(2000));
  });
  tearDown(() async {
    await repository.dispose();
    await temp.delete(recursive: true);
  });

  TtsFinalizedAudioScene scene({
    int revision = 1,
    String voice = 'narrator',
    String direction = 'quiet',
    String predecessor = 'previous-a',
    bool Function()? isCurrent,
    Future<void>? cancelled,
    int start = 100,
    int end = 102,
    String? finalPath,
    String unusedVoice = 'unused-a',
  }) => TtsFinalizedAudioScene(
    documentId: 'session-document-$revision',
    generationId: 'generation-$revision',
    sceneId: 'ephemeral-scene-$revision',
    text: 'Hello there.',
    engineSpeakText: 'Hello there.',
    startWordIndex: start,
    endWordIndex: end,
    startOffset: 6,
    sceneTurns: [
      NativeSpeechTurn(
        voiceId: voice,
        text: 'Hello there.',
        segmentIds: ['segment-$revision'],
        startWord: start,
        endWord: end,
        bindingFingerprint: binding(voice, revision).fingerprint,
        bindingRevision: revision,
        castId: 'character',
        directions: [
          {'delivery': direction},
        ],
      ),
    ],
    preparedBindings: [
      binding(voice, revision),
      binding(unusedVoice, revision),
    ],
    audioPath: finalPath ?? audio,
    rawAudioPath: raw,
    duration: const Duration(milliseconds: 10),
    engineId: 'engine',
    engineVersion: 'engine-v1',
    normalizationVersion: 'norm-v1',
    capabilityProfileId: 'capability-v1',
    synthesisIdentity: 'synthesis-v1',
    translationSignature: 'translator-v1',
    synthesisRate: 1,
    assignmentRevision: revision,
    cancelled: cancelled ?? Completer<void>().future,
    isCurrent: isCurrent ?? () => true,
    rawArtifactIdentity: 'actual-raw-key',
    predecessorRawArtifactIdentity: predecessor,
    boundaryPolicyVersion: 'boundary-v1',
  );

  test(
    'copies final/raw audio, captured evidence and global spans durably',
    () async {
      final stored = await repository.publish(
        scene(),
        sourceId: 'source',
        intent: intent,
      );
      expect(stored.audioPath, isNot(audio));
      expect(stored.rawAudioPath, isNot(raw));
      expect(
        File(stored.audioPath).readAsBytesSync(),
        File(audio).readAsBytesSync(),
      );
      expect(
        File(stored.rawAudioPath!).readAsBytesSync(),
        File(raw).readAsBytesSync(),
      );
      expect(stored.startWordIndex, 100);
      expect(stored.endWordIndex, 102);
      expect(stored.startOffset, 6);
      expect(stored.sampleRate, 24000);
      expect(stored.channels, 1);
      expect(stored.frameCount, 240);
      expect(stored.duration, const Duration(milliseconds: 10));
      expect(stored.provenance['rawArtifactIdentity'], 'actual-raw-key');
      expect(stored.intent, intent);
      expect(stored.sceneTurns.single.directions, [
        {'delivery': 'quiet'},
      ]);
      expect(() => stored.intent['voice'] = 'changed', throwsUnsupportedError);
      File(audio).deleteSync();
      File(raw).deleteSync();
      await repository.dispose();
      repository = RenderedSceneRepository(Directory('${temp.path}/durable'));
      final reopened = await repository.sceneAt('source', 101);
      expect(reopened!.sceneId, stored.sceneId);
      expect(reopened.audioPath, stored.audioPath);
      expect(await repository.sceneAt('source', 102), isNull);
      expect(
        (await repository.scenesForSource('source')).single.dependencyDigest,
        stored.dependencyDigest,
      );
      expect(AudioArtifactPins.shared.pinCount(audio), 0);
      expect(AudioArtifactPins.shared.pinCount(raw), 0);
    },
  );

  test(
    'stable source identity survives ephemeral assignment/session revisions',
    () async {
      final a = await repository.publish(
        scene(),
        sourceId: 'source',
        intent: intent,
      );
      final b = await repository.publish(
        scene(revision: 99),
        sourceId: 'source',
        intent: intent,
      );
      expect(a.sceneId, b.sceneId);
      expect(a.dependencyDigest, b.dependencyDigest);
      expect(a.rawDependencyDigest, b.rawDependencyDigest);
      expect(a.audioPath, b.audioPath);
      expect((await repository.scenesForSource('source')).length, 1);
    },
  );

  test(
    'voice/direction changes alter dependencies, unrelated global intent does not',
    () async {
      final a = await repository.publish(
        scene(),
        sourceId: 'source',
        intent: intent,
      );
      final voice = await repository.publish(
        scene(voice: 'other'),
        sourceId: 'source',
        intent: {'voice': 'other'},
      );
      final direction = await repository.publish(
        scene(direction: 'loud'),
        sourceId: 'source',
        intent: intent,
      );
      final unrelated = await repository.publish(
        scene(),
        sourceId: 'source',
        intent: {...intent, 'unrelatedCharacter': 'new'},
      );
      for (final b in [voice, direction]) {
        expect(b.sceneId, a.sceneId);
        expect(b.dependencyDigest, isNot(a.dependencyDigest));
        expect(b.rawDependencyDigest, isNot(a.rawDependencyDigest));
      }
      expect(unrelated.dependencyDigest, a.dependencyDigest);
      expect(
        (await repository.sceneAt(
          'source',
          100,
          intent: {'voice': 'other'},
        ))!.dependencyDigest,
        voice.dependencyDigest,
      );
    },
  );

  test(
    'predecessor changes derivative dependency while preserving raw identity',
    () async {
      final a = await repository.publish(
        scene(),
        sourceId: 'source',
        intent: intent,
      );
      final b = await repository.publish(
        scene(predecessor: 'previous-b'),
        sourceId: 'source',
        intent: intent,
      );
      expect(a.rawDependencyDigest, b.rawDependencyDigest);
      expect(a.rawAudioPath, b.rawAudioPath);
      expect(a.dependencyDigest, isNot(b.dependencyDigest));
      expect(File(a.audioPath).existsSync(), isTrue);
    },
  );

  test(
    'unused prepared resources do not invalidate scene dependencies',
    () async {
      final a = await repository.publish(
        scene(),
        sourceId: 'source',
        intent: intent,
      );
      final b = await repository.publish(
        scene(unusedVoice: 'unused-b'),
        sourceId: 'source',
        intent: intent,
      );
      expect(a.dependencyDigest, b.dependencyDigest);
      expect(a.rawDependencyDigest, b.rawDependencyDigest);
    },
  );

  test(
    'one-active/noqueue cancellation drains worker, releases pins and preserves committed output',
    () async {
      final committed = await repository.publish(
        scene(),
        sourceId: 'source',
        intent: intent,
      );
      final pending = repository.publish(
        scene(voice: 'new'),
        sourceId: 'source',
        intent: intent,
      );
      final rejected = expectLater(
        pending,
        throwsA(isA<RenderedSceneCancelled>()),
      );
      expect(repository.activeCount, 1);
      await expectLater(repository.scenesForSource('source'), throwsStateError);
      await repository.cancelAndDrain().timeout(const Duration(seconds: 2));
      await rejected;
      expect(repository.activeCount, 0);
      expect(AudioArtifactPins.shared.pinCount(audio), 0);
      expect(
        (await repository.scenesForSource('source')).single.dependencyDigest,
        committed.dependencyDigest,
      );
      expect(File(committed.audioPath).existsSync(), isTrue);
    },
  );

  test(
    'engine cancellation before worker admission leaves no committed scene',
    () async {
      final cancelled = Completer<void>();
      final pending = repository.publish(
        scene(cancelled: cancelled.future),
        sourceId: 'source',
        intent: intent,
      );
      final rejected = expectLater(
        pending,
        throwsA(isA<RenderedSceneCancelled>()),
      );
      cancelled.complete();
      await rejected;
      expect(await repository.scenesForSource('source'), isEmpty);
      expect(repository.activeCount, 0);
    },
  );

  test(
    'current-owner check immediately before rename rejects obsolete output',
    () async {
      var checks = 0;
      await expectLater(
        repository.publish(
          scene(isCurrent: () => ++checks == 1),
          sourceId: 'source',
          intent: intent,
        ),
        throwsA(isA<RenderedSceneCancelled>()),
      );
      expect(checks, 2);
      expect(await repository.scenesForSource('source'), isEmpty);
      await repository.publish(scene(), sourceId: 'source', intent: intent);
      await expectLater(
        repository.scenesForSource('source', isCurrent: () => false),
        throwsA(isA<RenderedSceneCancelled>()),
      );
    },
  );

  test('corrupt metadata fails visibly and never looks like EOF', () async {
    await repository.publish(scene(), sourceId: 'source', intent: intent);
    final metadata = Directory('${temp.path}/durable/scenes')
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.json'));
    final value = jsonDecode(metadata.readAsStringSync()) as Map;
    (value['metadata'] as Map)['text'] = 'tampered';
    metadata.writeAsStringSync(jsonEncode(value));
    await expectLater(repository.sceneAt('source', 100), throwsFormatException);
  });

  test('corrupt final or raw PCM fails existing artifact validation', () async {
    final stored = await repository.publish(
      scene(),
      sourceId: 'source',
      intent: intent,
    );
    File(stored.rawAudioPath!).writeAsBytesSync([1, 2, 3]);
    await expectLater(repository.sceneAt('source', 100), throwsFormatException);
    final other = await repository.publish(
      scene(start: 200, end: 202),
      sourceId: 'other',
      intent: intent,
    );
    File(other.audioPath).writeAsBytesSync([4, 5, 6]);
    await expectLater(
      repository.scenesForSource('other'),
      throwsFormatException,
    );
  });

  test(
    'bad WAV, bounded enumeration and disposed owners reject without admitting',
    () async {
      final bad = File('${temp.path}/bad.wav')..writeAsBytesSync([1, 2, 3]);
      await expectLater(
        repository.publish(
          scene(finalPath: bad.path),
          sourceId: 'source',
          intent: intent,
        ),
        throwsFormatException,
      );
      expect(await repository.scenesForSource('source'), isEmpty);
      await repository.publish(scene(), sourceId: 'source', intent: intent);
      await repository.publish(
        scene(start: 200, end: 202),
        sourceId: 'source',
        intent: intent,
      );
      await expectLater(
        repository.scenesForSource('source', limit: 1),
        throwsFormatException,
      );
      await repository.dispose();
      await expectLater(repository.scenesForSource('source'), throwsStateError);
    },
  );
}

PreparedVoiceBinding binding(String voice, int revision) =>
    PreparedVoiceBinding(
      voiceId: voice,
      voiceDigest: 'voice-content-$voice',
      modelDigest: 'model-content',
      engineVersion: 'engine-v1',
      pronunciationProfileId: 'pronunciation-v1',
      bindingRevision: revision,
      documentId: 'session-document-$revision',
    );

Uint8List wav(int amplitude) {
  final bytes = Uint8List(44 + 480);
  final b = ByteData.sublistView(bytes);
  void tag(int at, String text) => bytes.setRange(at, at + 4, text.codeUnits);
  tag(0, 'RIFF');
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  tag(36, 'data');
  b.setUint32(4, bytes.length - 8, Endian.little);
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, 24000, Endian.little);
  b.setUint32(28, 48000, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  b.setUint32(40, bytes.length - 44, Endian.little);
  for (var i = 44; i < bytes.length; i += 2) {
    b.setInt16(i, amplitude, Endian.little);
  }
  return bytes;
}
