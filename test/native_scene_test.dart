import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/engine_capability.dart';
import 'package:read_aloud/src/models/chunk_plan.dart';
import 'package:read_aloud/src/models/native_speech_turn.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/tts_artifact.dart';
import 'package:read_aloud/src/services/chunk_planner_service.dart';
import 'package:read_aloud/src/services/speech_runtime.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';

void main() {
  test('native scene support is scoped to the qualified model revision', () {
    const registry = EngineCapabilityRegistry();
    final supported = registry.lookup(engineId: 'fish_drama3');
    expect(supported.supportsNativeScenes, isTrue);
    expect(
      EngineCapabilityProfile.fromMap(supported.toMap()).supportsNativeScenes,
      isTrue,
    );
    expect(
      registry
          .lookup(engineId: 'fish_drama3', modelId: 'another-model')
          .supportsNativeScenes,
      isFalse,
    );
    expect(
      registry
          .lookup(engineId: 'fish_drama3', modelRevision: 'another-revision')
          .supportsNativeScenes,
      isFalse,
    );
    expect(registry.lookup(engineId: 'kokoro').supportsNativeScenes, isFalse);
  });
  ChunkSpec turn(int n, {int words = 5}) => ChunkSpec(
    chunkId: 'c$n',
    segmentIds: ['s$n'],
    speakText: 'Turn $n.',
    voiceId: n.isEven ? 'mira' : 'mara',
    boundaryClass: BreakClass.sentence,
    startSegmentIndex: n,
    endSegmentIndex: n,
    estimatedWordCount: words,
    cacheKey: 'key$n',
    startWordIndex: n * words,
    endWordIndex: (n + 1) * words,
    ttsSegments: [
      TtsArtifactSegment(
        segmentId: 's$n',
        speakText: 'Turn $n.',
        pronunciationArtifacts: const [],
      ),
    ],
    castId: n.isEven ? 'cast_mira' : 'cast_mara',
  );
  test('bounded scenes retain ordered A/B/A source turns without gaps', () {
    final original = List.generate(40, turn);
    final scenes = packNativeSceneChunks(original);
    expect(scenes.length, 3);
    expect(scenes.map((s) => s.estimatedWordCount), [75, 75, 50]);
    expect(scenes.expand((s) => s.sceneTurns).toList(), original);
    expect(scenes.first.sceneTurns.take(3).map((s) => s.voiceId), [
      'mira',
      'mara',
      'mira',
    ]);
    expect(scenes.last.endWordIndex, 200);
    expect(scenes.every((s) => s.sceneTurns.length <= 16), isTrue);
    expect(scenes.map((s) => s.startWordIndex), [0, 75, 150]);
  });
  test(
    'source discontinuity splits a scene instead of concealing missing text',
    () {
      final scenes = packNativeSceneChunks([turn(0), turn(2)]);
      expect(scenes.length, 2);
      expect(scenes.first.endWordIndex, 5);
      expect(scenes.last.startWordIndex, 10);
    },
  );
  test(
    'runtime and worker snapshots retain all turn bindings and directions',
    () {
      final turns = [
        NativeSpeechTurn(
          voiceId: 'mira',
          text: '[whispers] Be quiet.',
          segmentIds: ['s0'],
          startWord: 0,
          endWord: 2,
          bindingFingerprint: 'voice-mira-rev7',
          bindingRevision: 7,
          castId: 'cast_mira',
          directions: [
            {'delivery': 'whispered'},
          ],
        ),
        NativeSpeechTurn(
          voiceId: 'mara',
          text: '[shouting] Footsteps!',
          segmentIds: ['s1'],
          startWord: 2,
          endWord: 3,
          bindingFingerprint: 'voice-mara-rev7',
          bindingRevision: 7,
          castId: 'cast_mara',
          directions: [
            {'delivery': 'shouted'},
          ],
        ),
      ];
      final runtime = SpeechRuntimeChunkPayload(
        chunkId: 'scene',
        segmentIds: ['s0', 's1'],
        cacheKey: 'cache',
        boundaryClass: BreakClass.none,
        documentId: 'doc',
        normalizationVersion: 'n1',
        speakText: 'Be quiet. Footsteps!',
        tokens: [],
        languageTag: 'en-us',
        voiceId: 'mira',
        rate: 1,
        isInitialChunk: true,
        isResumedChunk: false,
        sceneTurns: turns,
      );
      final restored = SpeechRuntimeChunkPayload.fromPayload(
        runtime.toPayload(),
      );
      final worker = SpeechWorkerChunkRequest(
        sessionId: 's',
        generationId: 'g',
        chunkId: restored.chunkId,
        segmentIds: restored.segmentIds,
        cacheKey: restored.cacheKey,
        boundaryClass: restored.boundaryClass,
        documentId: restored.documentId,
        normalizationVersion: restored.normalizationVersion,
        speakText: restored.speakText,
        tokens: restored.tokens,
        languageTag: restored.languageTag,
        voiceId: restored.voiceId,
        rate: restored.rate,
        sceneTurns: restored.sceneTurns,
      ).snapshot();
      turns.clear();
      expect(
        worker.sceneTurns.map((t) => t.toMap()),
        restored.sceneTurns.map((t) => t.toMap()),
      );
      expect(worker.sceneTurns.last.bindingFingerprint, 'voice-mara-rev7');
      expect(worker.sceneTurns.last.directions.single['delivery'], 'shouted');
      expect(() => worker.sceneTurns.clear(), throwsUnsupportedError);
    },
  );
}
