import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_aware_speech_route.dart';
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

    test('splits chunk plans at cast-aware voice route boundaries', () {
      final document = DocumentImportService().importPastedText(
        'Narration starts here. "Go now," Jennifer said. Narration ends here.',
      );
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
          castAwareSpeechRoutes: CastAwareSpeechRouteSet(
            documentId: document.speechDocument.documentId,
            routingVersion: 'routes-v1',
            ranges: <CastAwareSpeechRange>[
              CastAwareSpeechRange(
                routeId: 'route_narration_open',
                segmentIds: <String>[
                  document.speechDocument.segments[0].segmentId,
                ],
                startSegmentId: document.speechDocument.segments[0].segmentId,
                endSegmentId: document.speechDocument.segments[0].segmentId,
                startWordIndex: 0,
                endWordIndex: document.speechDocument.segments[0].wordCount,
                castId: 'cast_narrator',
                voiceId: 'af_bella',
              ),
              CastAwareSpeechRange(
                routeId: 'route_dialogue_jennifer',
                segmentIds: <String>[
                  document.speechDocument.segments[1].segmentId,
                ],
                startSegmentId: document.speechDocument.segments[1].segmentId,
                endSegmentId: document.speechDocument.segments[1].segmentId,
                startWordIndex: document.speechDocument.segments[0].wordCount,
                endWordIndex:
                    document.speechDocument.segments[0].wordCount +
                    document.speechDocument.segments[1].wordCount,
                castId: 'cast_character_jennifer',
                voiceId: 'bf_emma',
                dialogueSpanId: 'dlg_s_1',
              ),
              CastAwareSpeechRange(
                routeId: 'route_narration_close',
                segmentIds: <String>[
                  document.speechDocument.segments[2].segmentId,
                ],
                startSegmentId: document.speechDocument.segments[2].segmentId,
                endSegmentId: document.speechDocument.segments[2].segmentId,
                startWordIndex:
                    document.speechDocument.segments[0].wordCount +
                    document.speechDocument.segments[1].wordCount,
                endWordIndex: document.speechDocument.totalWordCount,
                castId: 'cast_narrator',
                voiceId: 'af_bella',
              ),
            ],
          ),
        ),
      );

      expect(plan.chunks, hasLength(3));
      expect(plan.chunks[0].voiceId, 'af_bella');
      expect(plan.chunks[0].routeId, 'route_narration_open');
      expect(plan.chunks[1].voiceId, 'bf_emma');
      expect(plan.chunks[1].castId, 'cast_character_jennifer');
      expect(plan.chunks[1].dialogueSpanId, 'dlg_s_1');
      expect(plan.chunks[2].voiceId, 'af_bella');
      expect(plan.chunks[2].routeId, 'route_narration_close');
    });
  });
}
