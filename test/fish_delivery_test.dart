import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/chunk_plan.dart';
import 'package:read_aloud/src/models/engine_capability.dart';
import 'package:read_aloud/src/models/narration_state.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/voice_session_realization.dart';
import 'package:read_aloud/src/services/base_speech_annotation_inference_service.dart';
import 'package:read_aloud/src/services/chunk_planner_service.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/kokoro_pronunciation_translation_service.dart';
import 'package:read_aloud/src/services/kokoro_tokenization_worker.dart';
import 'package:read_aloud/src/services/voice_session_realization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final document = DocumentImportService().importPastedText(
    'Are you there? I am right here. The room fell quiet.',
  );
  final first = document.speechDocument.segments.first;
  BaseSpeechAnnotationSet annotations({
    DeliveryIntent delivery = DeliveryIntent.whispered,
    bool partial = false,
    bool conflict = false,
  }) => const BaseSpeechAnnotationInferenceService().infer(
    speechDocument: document.speechDocument,
    displayDocument: document.displayDocument,
    explicitIntents: [
      SpeechAnnotation(
        annotationId: 'whisper',
        segmentId: first.segmentId,
        kind: SpeechAnnotationKind.deliveryIntent,
        startWord: 0,
        endWord: partial ? 1 : first.wordCount,
        confidence: 1,
        source: SpeechAnnotationSource.userOverride,
        deliveryIntent: delivery,
      ),
      if (conflict)
        SpeechAnnotation(
          annotationId: 'shout',
          segmentId: first.segmentId,
          kind: SpeechAnnotationKind.deliveryIntent,
          startWord: 0,
          endWord: first.wordCount,
          confidence: 1,
          source: SpeechAnnotationSource.userOverride,
          deliveryIntent: DeliveryIntent.shouted,
        ),
    ],
  );
  VoiceSessionRealization realize(
    BaseSpeechAnnotationSet set, {
    String engine = 'fish_drama3',
  }) => const VoiceSessionRealizationService().realize(
    VoiceSessionRealizationInput(
      speechDocument: document.speechDocument,
      baseAnnotations: set,
      basePronunciationArtifacts: document.basePronunciationArtifacts,
      startSegmentId: first.segmentId,
      voiceId: 'library_fishsarah',
      engineId: engine,
      rate: 1,
      narrationState: NarrationState.initial(),
      segmentLimit: 10,
    ),
  );

  test('explicit shouting preserves intent and lowers only its target cue', () {
    final result = realize(annotations(delivery: DeliveryIntent.shouted));
    expect(result.performanceIntents.single.engineControl, '[shouting]');
    expect(
      result.performanceIntents.single.annotation.deliveryIntent,
      DeliveryIntent.shouted,
    );
    expect(
      realize(
        annotations(delivery: DeliveryIntent.shouted),
        engine: 'kokoro',
      ).performanceIntents.single.engineControl,
      isNull,
    );
  });
  test(
    'one explicit whole-turn whisper is isolated and survives the worker',
    () async {
      final set = annotations();
      final realized = realize(set);
      expect(realized.performanceIntents.single.engineControl, '[whispers]');
      expect(
        realized.performanceIntents.single.adjustmentDecision!['allowed'],
        true,
      );
      final plan = const ChunkPlannerService().plan(
        ChunkPlannerInput(
          speechDocument: document.speechDocument,
          baseAnnotations: set,
          ttsArtifactSet: realized.ttsArtifactSet,
          startSegmentId: first.segmentId,
          voiceId: 'library_fishsarah',
          rate: 1,
          engineId: 'fish_drama3',
          engineVersion: 'test',
        ),
      );
      expect(plan.chunks.first.segmentIds, [first.segmentId]);
      expect(plan.chunks.first.speakText, 'Are you there?');
      expect(
        plan.chunks
            .skip(1)
            .expand((c) => c.ttsSegments)
            .expand((s) => s.performanceIntents),
        isEmpty,
      );
      expect(plan.chunks.last.endWordIndex, document.wordCount);
      final worker = KokoroTokenizationWorker(
        capabilityProfile: const EngineCapabilityRegistry().lookup(
          engineId: 'fish_drama3',
        ),
        assets: KokoroTokenizerAssets(
          vocabularyJson: await rootBundle.loadString(
            'assets/tokenizer_vocab.json',
          ),
          lexiconJson: await rootBundle.loadString('assets/lexicon.json'),
          goldJson: await rootBundle.loadString('assets/us_gold.json'),
          silverJson: await rootBundle.loadString('assets/us_silver.json'),
        ),
      );
      addTearDown(worker.shutdown);
      final result = await worker.prepare(plan.chunks.first, 'en-us');
      expect(result.translatedChunk!.speakText, '[whispers] Are you there?');
      expect(
        result.translatedChunk!.payloadUnits.map((u) => u.value).join(),
        'Are you there?',
      );
      expect(result.finalPhonemeString, isNot(contains('whisper')));
      final unqualified = await worker.prepare(
        plan.chunks.first,
        'en-us',
        capabilityOverride: const EngineCapabilityRegistry().lookup(
          engineId: 'fish_drama3',
          modelId: 'unverified-local-model',
          modelRevision: 'local-content',
        ),
      );
      expect(unqualified.translatedChunk!.speakText, 'Are you there?');
      final qualifiedAgain = await worker.prepare(plan.chunks.first, 'en-us');
      expect(
        qualifiedAgain.translatedChunk!.speakText,
        '[whispers] Are you there?',
      );
    },
  );

  test(
    'partial, conflicting, and other-engine directions stay unsupported',
    () {
      for (final realized in [
        realize(annotations(partial: true)),
        realize(annotations(conflict: true)),
        realize(annotations(), engine: 'fish_drama3_8bit'),
        realize(annotations(), engine: 'kokoro'),
      ]) {
        expect(realized.performanceIntents, isNotEmpty);
        expect(
          realized.performanceIntents.every((i) => i.engineControl == null),
          true,
        );
      }
    },
  );

  test('stale realization cannot apply cues to another model or revision', () {
    final segments = realize(annotations()).ttsArtifactSet.segments;
    for (final capability in [
      const EngineCapabilityRegistry().lookup(engineId: 'kokoro'),
      const EngineCapabilityRegistry().lookup(engineId: 'fish_drama3_4bit'),
      const EngineCapabilityRegistry().lookup(
        engineId: 'fish_drama3',
        modelRevision: 'different',
      ),
    ]) {
      final translated = const KokoroPronunciationTranslationService()
          .translate(
            chunkId: 'test',
            segments: segments,
            capabilityProfile: capability,
          );
      expect(translated.speakText, isNot(contains('[whispers]')));
    }
  });
}
