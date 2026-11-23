import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_aware_speech_route.dart';
import 'package:read_aloud/src/models/chunk_plan.dart';
import 'package:read_aloud/src/models/narration_state.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/tts_artifact.dart';
import 'package:read_aloud/src/models/voice_session_realization.dart';
import 'package:read_aloud/src/services/chunk_planner_service.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';
import 'package:read_aloud/src/services/voice_session_realization_service.dart';

void main() {
  group('ChunkPlannerService', () {
    test('keeps an interrupted utterance with its reporting clause', () {
      const opening =
          '"You need to leave before they walk through the '
          'only way out and lock us inside,"';
      const reporting = 'she said,';
      const continuation = '"unless you know another way."';
      final document = DocumentImportService().importPastedText('''
$opening $reporting $continuation

“Follow me.”
''');
      final segments = document.speechDocument.segments;
      expect(segments, hasLength(4));
      final plan = _fishPlan(
        document,
        maxChunks: 1,
        boundaries: {
          segments[1].segmentId: FishSceneBoundary.continuation,
          segments[2].segmentId: FishSceneBoundary.continuation,
          segments[3].segmentId: FishSceneBoundary.chapter,
        },
        routes: [
          _range(document, 0, 0, segments[0].wordCount, 'speaker'),
          _range(document, 1, 0, segments[1].wordCount, 'narrator'),
          _range(document, 2, 0, segments[2].wordCount, 'speaker'),
        ],
      );

      final scene = plan.chunks.single;
      expect(scene.speakText, '$opening $reporting $continuation');
      expect(scene.sceneTurns.map((turn) => turn.voiceId), [
        'speaker',
        'narrator',
        'speaker',
      ]);
      expect(scene.sceneTurns.map((turn) => turn.speakText), [
        opening,
        reporting,
        continuation,
      ]);
      expect(scene.endWordIndex, document.wordCount - segments.last.wordCount);
      expect(plan.nextSegmentId, segments.last.segmentId);
    });

    test('keeps word-exact speaker changes inside a single source segment', () {
      const source = "'Wait,' she said, 'just there!'";
      final document = DocumentImportService().importPastedText(source);
      final segment = document.speechDocument.segments.single;
      final routes = [
        _range(document, 0, 0, 1, 'speaker'),
        _range(document, 0, 1, 3, 'narrator'),
        _range(document, 0, 3, 5, 'speaker'),
      ];
      final native = _fishPlan(document, routes: routes, maxChunks: 1);
      expect(native.chunks.single.speakText, source);
      expect(native.chunks.single.segmentIds, [segment.segmentId]);
      for (final turns in [
        native.chunks.single.sceneTurns,
        _fishPlan(document, routes: routes, maxChunks: 1, bits: 8).chunks,
      ]) {
        expect(turns.map((turn) => turn.chunkId).toSet(), hasLength(3));
        expect(turns.map((turn) => turn.voiceId), [
          'speaker',
          'narrator',
          'speaker',
        ]);
        expect(turns.map((turn) => turn.speakText), [
          "'Wait,'",
          'she said,',
          "'just there!'",
        ]);
        expect(
          turns.map((turn) => turn.ttsSegments.single.speakText),
          turns.map((turn) => turn.speakText),
        );
        expect(
          turns.map((turn) => turn.boundaryClass),
          everyElement(BreakClass.none),
        );
        expect(
          turns.map((turn) => turn.segmentWordRanges.single.segmentId),
          everyElement(segment.segmentId),
        );
        expect(turns.map((turn) => turn.segmentWordRanges.single.startWord), [
          0,
          1,
          3,
        ]);
        expect(turns.map((turn) => turn.segmentWordRanges.single.endWord), [
          1,
          3,
          5,
        ]);
      }
      final fallback = _fishPlan(document, routes: routes, engineId: 'kokoro');
      expect(fallback.chunks.single.speakText, source);
      expect(fallback.chunks.single.sceneTurns, isEmpty);
    });

    test('resumes in source order after reaching the native turn cap', () {
      final document = DocumentImportService().importPastedText(
        List.generate(18, (index) => 'Turn $index.').join(' '),
      );
      final segments = document.speechDocument.segments;
      final routes = [
        for (var i = 0; i < segments.length; i++)
          _range(document, i, 0, segments[i].wordCount, 'voice_$i'),
      ];
      final boundaries = {
        for (final segment in segments)
          segment.segmentId: FishSceneBoundary.continuation,
      };
      final initial = _fishPlan(
        document,
        routes: routes,
        boundaries: boundaries,
        maxChunks: 1,
      );
      final next = initial.nextSegmentId!;
      final refill = _fishPlan(
        document,
        routes: routes,
        boundaries: boundaries,
        startSegmentId: next,
      );
      final first = initial.chunks.single;
      final second = refill.chunks.single;
      expect(first.sceneTurns, hasLength(16));
      expect(
        first.sceneTurns.map((turn) => turn.voiceId).toSet(),
        hasLength(16),
      );
      expect(first.endWordIndex, second.startWordIndex);
      expect(second.endWordIndex, document.wordCount);
      expect(refill.nextSegmentId, isNull);
      expect([
        ...first.segmentIds,
        ...second.segmentIds,
      ], segments.map((segment) => segment.segmentId));
    });

    test(
      'uses a sentence break before a forced cap and reports an indivisible unit',
      () {
        final document = DocumentImportService().importPastedText(
          'A safe opening. ${List.filled(76, 'word').join(' ')}.',
        );
        final segments = document.speechDocument.segments;
        final boundaries = {
          segments.last.segmentId: FishSceneBoundary.sentence,
        };
        final initial = _fishPlan(document, boundaries: boundaries);
        expect(initial.chunks.single.speakText, 'A safe opening.');
        expect(initial.nextSegmentId, segments.last.segmentId);
        expect(
          () => _fishPlan(
            document,
            boundaries: boundaries,
            startSegmentId: initial.nextSegmentId,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('exceeds 75 words'),
            ),
          ),
        );
      },
    );

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
          (chunk) => chunk.cacheKey.startsWith('kokoro:1:af_bella:1.0:'),
        ),
        isTrue,
      );
      expect(plan.chunks.first.ttsSegments, isNotEmpty);
    });

    test('does not round nearby effective rates into one planner identity', () {
      final document = DocumentImportService().importPastedText(
        'John said hello.',
      );
      final realization = const VoiceSessionRealizationService().realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: document.speechDocument.segments.first.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1,
          narrationState: NarrationState.initial(),
        ),
      );
      ChunkPlan plan(double rate) => ChunkPlannerService().plan(
        ChunkPlannerInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          ttsArtifactSet: realization.ttsArtifactSet,
          startSegmentId: document.speechDocument.segments.first.segmentId,
          voiceId: 'af_bella',
          rate: rate,
          engineId: 'kokoro',
          engineVersion: '12',
        ),
      );
      expect(
        plan(1.001).chunks.single.cacheKey,
        isNot(plan(1.002).chunks.single.cacheKey),
      );
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
      final closingSegments = document.speechDocument.segments
          .skip(2)
          .toList(growable: false);
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
                segmentIds: closingSegments
                    .map((segment) => segment.segmentId)
                    .toList(growable: false),
                startSegmentId: document.speechDocument.segments[2].segmentId,
                endSegmentId: closingSegments.last.segmentId,
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

CastAwareSpeechRange _range(
  ReaderDocument document,
  int index,
  int start,
  int end,
  String voice,
) {
  final segments = document.speechDocument.segments;
  final segment = segments[index];
  final offset = segments.take(index).fold<int>(0, (n, s) => n + s.wordCount);
  return CastAwareSpeechRange(
    routeId: 'route_${index}_$start',
    segmentIds: [segment.segmentId],
    startSegmentId: segment.segmentId,
    endSegmentId: segment.segmentId,
    startWordIndex: offset + start,
    endWordIndex: offset + end,
    castId: 'cast_$voice',
    voiceId: voice,
  );
}

ChunkPlan _fishPlan(
  ReaderDocument document, {
  List<CastAwareSpeechRange> routes = const [],
  Map<String, FishSceneBoundary> boundaries = const {},
  String? startSegmentId,
  int? maxChunks,
  int bits = 0,
  String? engineId,
}) {
  final speech = document.speechDocument;
  final start = startSegmentId ?? speech.segments.first.segmentId;
  final engine = engineId ?? (bits == 8 ? 'fish_drama3_8bit' : 'fish_drama3');
  return const ChunkPlannerService().plan(
    ChunkPlannerInput(
      speechDocument: speech,
      baseAnnotations: document.baseSpeechAnnotations,
      ttsArtifactSet: TtsArtifactSet(
        documentId: speech.documentId,
        sessionId: 'test',
        engineId: engine,
        voiceId: 'narrator',
        rate: 1,
        startSegmentId: start,
        endSegmentId: speech.segments.last.segmentId,
        segments: const [],
      ),
      startSegmentId: start,
      voiceId: 'narrator',
      rate: 1,
      engineId: engine,
      engineVersion: mlxTtsVersionFor(bits, engineId: engine),
      fishSceneBoundaries: boundaries,
      castAwareSpeechRoutes: CastAwareSpeechRouteSet(
        documentId: speech.documentId,
        routingVersion: 'test',
        ranges: routes,
      ),
      maxChunks: maxChunks,
    ),
  );
}
