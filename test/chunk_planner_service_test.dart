import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/chunk_plan.dart';
import 'package:read_aloud/src/models/narration_state.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/tts_artifact.dart';
import 'package:read_aloud/src/models/voice_session_realization.dart';
import 'package:read_aloud/src/services/chunk_planner_service.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/voice_session_realization_service.dart';

void main() {
  group('ChunkPlannerService', () {
    test('builds chunk specs from ordered speech segments', () {
      final document = DocumentImportService().importPastedText('''
Sentence one. Sentence two. Sentence three. Sentence four.

Sentence five. Sentence six. Sentence seven. Sentence eight.

Sentence nine. Sentence ten. Sentence eleven. Sentence twelve.
''');
      final service = ChunkPlannerService();
      final realization = const VoiceSessionRealizationService().realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: document.speechDocument.segments.first.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );

      final plan = service.plan(
        ChunkPlannerInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          ttsArtifactSet: realization.ttsArtifactSet,
          startSegmentId: document.speechDocument.segments.first.segmentId,
          voiceId: 'af_bella',
          rate: 1.0,
          engineId: 'kokoro',
          engineVersion: '1',
        ),
      );

      expect(plan.chunks, isNotEmpty);
      expect(plan.chunks.first.segmentIds, isNotEmpty);
      expect(plan.chunks.first.startSegmentIndex, 0);
      expect(
        plan.chunks.every((chunk) => chunk.speakText.trim().isNotEmpty),
        isTrue,
      );
      expect(
        plan.chunks.every(
          (chunk) => chunk.cacheKey.startsWith('kokoro:1:af_bella:1.00:'),
        ),
        isTrue,
      );
      expect(plan.chunks.first.ttsSegments, isNotEmpty);
    });

    test('can restart planning from an arbitrary segment id', () {
      final document = DocumentImportService().importPastedText(
        'One. Two. Three. Four. Five. Six.',
      );
      final startSegment = document.speechDocument.segments[2];
      final service = ChunkPlannerService();
      final realization = const VoiceSessionRealizationService().realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );

      final plan = service.plan(
        ChunkPlannerInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          ttsArtifactSet: realization.ttsArtifactSet,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          rate: 1.0,
          engineId: 'kokoro',
          engineVersion: '1',
        ),
      );

      expect(plan.chunks.first.startSegmentIndex, startSegment.ordinal);
      expect(plan.chunks.first.segmentIds.first, startSegment.segmentId);
    });

    test('prefers realized boundary intent over raw base annotations', () {
      final document = DocumentImportService().importPastedText(
        'One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen. Next. Third.',
      );
      final service = ChunkPlannerService();
      final firstSegment = document.speechDocument.segments.first;
      final secondSegment = document.speechDocument.segments[1];

      final plan = service.plan(
        ChunkPlannerInput(
          speechDocument: document.speechDocument,
          baseAnnotations: BaseSpeechAnnotationSet(
            documentId: document.speechDocument.documentId,
            annotationVersion: 'test-v1',
            annotations: const <SpeechAnnotation>[],
          ),
          ttsArtifactSet: TtsArtifactSet(
            documentId: document.speechDocument.documentId,
            sessionId: 'session-test',
            engineId: 'kokoro',
            voiceId: 'af_bella',
            rate: 1.0,
            startSegmentId: firstSegment.segmentId,
            endSegmentId: secondSegment.segmentId,
            segments: <TtsArtifactSegment>[
              TtsArtifactSegment(
                segmentId: firstSegment.segmentId,
                speakText: firstSegment.normalizedText,
                pronunciationArtifacts: const <RealizedPronunciationArtifact>[],
                boundaryIntents: const <RealizedBoundaryIntent>[
                  RealizedBoundaryIntent(
                    annotationId: 'ann_boundary',
                    segmentId: 's_0',
                    startWord: 1,
                    endWord: 1,
                    breakClass: 'section',
                    sourceKind: 'pause_candidate',
                    engineTreatment: 'approximated',
                    confidence: 0.9,
                  ),
                ],
              ),
              TtsArtifactSegment(
                segmentId: secondSegment.segmentId,
                speakText: secondSegment.normalizedText,
                pronunciationArtifacts: const <RealizedPronunciationArtifact>[],
              ),
            ],
          ),
          startSegmentId: firstSegment.segmentId,
          voiceId: 'af_bella',
          rate: 1.0,
          engineId: 'kokoro',
          engineVersion: '1',
        ),
      );

      expect(plan.chunks.length, greaterThan(1));
      expect(plan.chunks[1].boundaryClass, BreakClass.section);
    });
  });
}
