import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/native_speech_turn.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';

void main() {
  const binding = PreparedVoiceBinding(
    voiceId: 'voice-a',
    voiceDigest: 'reference-a',
    modelDigest: 'model',
    engineVersion: 'runtime',
    pronunciationProfileId: 'en-us-core',
    bindingRevision: 1,
    documentId: 'document',
  );
  SpeechWorkerChunkRequest request({
    List<NativeSpeechTurn> turns = const [],
    String key = 'continued',
    String text = 'Stay close.',
    String generation = 'first',
    double rate = 1,
  }) => SpeechWorkerChunkRequest(
    sceneTurns: turns,
    sessionId: 'session',
    generationId: generation,
    chunkId: 'chunk',
    segmentIds: const ['segment'],
    cacheKey: key,
    boundaryClass: BreakClass.none,
    documentId: 'document',
    normalizationVersion: 'normalization',
    speakText: text,
    tokens: const [1],
    languageTag: 'en-us',
    voiceId: 'voice-a',
    rate: rate,
    synthesisIdentity: 'tokenizer',
  );
  String identity(
    SpeechWorkerChunkRequest request, {
    String model = 'model',
    List<String> references = const ['reference-a', 'reference-b'],
  }) => mlxRawAudioIdentity(
    request: request,
    binding: binding,
    engineId: 'fish_drama3',
    engineVersion: 'runtime',
    modelIdentity: model,
    referenceDigests: references,
  );
  test(
    'changing a non-leading scene voice or delivery changes raw identity',
    () {
      NativeSpeechTurn turn(String voice, String text) => NativeSpeechTurn(
        voiceId: voice,
        text: text,
        segmentIds: ['s'],
        startWord: 0,
        endWord: 2,
        bindingFingerprint: voice,
        bindingRevision: 1,
      );
      final original = identity(
        request(turns: [turn('a', 'Hello.'), turn('b', 'Reply.')]),
      );
      expect(
        identity(request(turns: [turn('a', 'Hello.'), turn('c', 'Reply.')])),
        isNot(original),
      );
      expect(
        identity(
          request(turns: [turn('a', 'Hello.'), turn('b', '[shouting] Reply.')]),
        ),
        isNot(original),
      );
      expect(
        identity(
          request(
            key: 'resumed',
            turns: [turn('a', 'Hello.'), turn('b', 'Reply.')],
          ),
        ),
        original,
      );
    },
  );
  test(
    'seek and retry reuse identical native speech, independent of join policy',
    () {
      final original = identity(request());
      expect(identity(request(key: 'resumed', generation: 'second')), original);
      expect(identity(request(key: 'initial', generation: 'third')), original);
    },
  );
  test('changed directions, references, model and exact rate cannot alias', () {
    final original = identity(request());
    for (final changed in [
      identity(request(text: '[whispers] Stay close.')),
      identity(request(rate: 1.00001)),
      identity(request(), model: 'replacement'),
      identity(request(), references: ['reference-a', 'changed-b']),
      identity(request(), references: ['reference-b', 'reference-a']),
    ]) {
      expect(changed, isNot(original));
    }
  });
}
