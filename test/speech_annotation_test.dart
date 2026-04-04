import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';

void main() {
  group('Speech annotation envelope', () {
    test('allows zero-width boundary annotations', () {
      final annotation = SpeechAnnotation(
        annotationId: 'ann_boundary',
        segmentId: 's_0',
        kind: SpeechAnnotationKind.pauseCandidate,
        startWord: 4,
        endWord: 4,
        confidence: 0.8,
        source: SpeechAnnotationSource.ruleBasedLinguisticInference,
        breakClass: BreakClass.sentence,
      );

      expect(annotation.isBoundaryAnnotation, isTrue);
      expect(annotation.startWord, annotation.endWord);
    });

    test('rejects zero-width non-boundary annotations', () {
      expect(
        () => SpeechAnnotation(
          annotationId: 'ann_bad',
          segmentId: 's_0',
          kind: SpeechAnnotationKind.discourseRole,
          startWord: 2,
          endWord: 2,
          confidence: 0.7,
          source: SpeechAnnotationSource.ruleBasedLinguisticInference,
          discourseRole: 'quotation',
        ),
        throwsArgumentError,
      );
    });

    test('normalizes user override confidence to one', () {
      final annotation = SpeechAnnotation(
        annotationId: 'ann_override',
        segmentId: 's_0',
        kind: SpeechAnnotationKind.sayAsCandidate,
        startWord: 0,
        endWord: 1,
        confidence: 0.23,
        source: SpeechAnnotationSource.userOverride,
        sayAsClass: 'letters',
      );

      expect(annotation.confidence, 1.0);
    });

    test('rejects out-of-range confidence values', () {
      expect(
        () => SpeechAnnotation(
          annotationId: 'ann_conf',
          segmentId: 's_0',
          kind: SpeechAnnotationKind.pronunciationCandidate,
          startWord: 0,
          endWord: 1,
          confidence: 1.4,
          source: SpeechAnnotationSource.ruleBasedLinguisticInference,
          pronunciationCandidate: const PronunciationCandidatePayload(
            surfaceText: 'NASA',
            normalizedSurfaceText: 'nasa',
            representationType: 'say_as_class',
            representationValue: 'letters',
            accentFamily: null,
            priorityHint: 80,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('annotation sets require unique annotation ids', () {
      final annotation = SpeechAnnotation(
        annotationId: 'ann_dup',
        segmentId: 's_0',
        kind: SpeechAnnotationKind.pauseCandidate,
        startWord: 1,
        endWord: 1,
        confidence: 0.7,
        source: SpeechAnnotationSource.importerStructuralInference,
        breakClass: BreakClass.weak,
      );

      expect(
        () => BaseSpeechAnnotationSet(
          documentId: 'doc_1',
          annotationVersion: 'read-aloud-annotations-v1',
          annotations: <SpeechAnnotation>[annotation, annotation],
        ),
        throwsArgumentError,
      );
    });

    test('annotation sets serialize shared envelope fields', () {
      final set = BaseSpeechAnnotationSet(
        documentId: 'doc_1',
        annotationVersion: 'read-aloud-annotations-v1',
        annotations: <SpeechAnnotation>[
          SpeechAnnotation(
            annotationId: 'ann_0',
            segmentId: 's_0',
            kind: SpeechAnnotationKind.pronunciationCandidate,
            startWord: 0,
            endWord: 1,
            confidence: 0.81,
            source: SpeechAnnotationSource.ruleBasedLinguisticInference,
            pronunciationCandidate: const PronunciationCandidatePayload(
              surfaceText: 'NASA',
              normalizedSurfaceText: 'nasa',
              representationType: 'say_as_class',
              representationValue: 'letters',
              accentFamily: null,
              priorityHint: 80,
            ),
          ),
        ],
      );

      final json = set.toJson();
      expect(json['documentId'], 'doc_1');
      expect(json['annotationVersion'], 'read-aloud-annotations-v1');
      expect((json['annotations'] as List<Object?>), hasLength(1));
    });

    test('requires supported discourse-role vocabulary', () {
      expect(
        () => SpeechAnnotation(
          annotationId: 'ann_discourse',
          segmentId: 's_0',
          kind: SpeechAnnotationKind.discourseRole,
          startWord: 0,
          endWord: 1,
          confidence: 0.8,
          source: SpeechAnnotationSource.ruleBasedLinguisticInference,
          discourseRole: 'aside',
        ),
        throwsArgumentError,
      );
    });

    test('requires dialogue span id and supported class vocabulary', () {
      expect(
        () => SpeechAnnotation(
          annotationId: 'ann_dialogue_span',
          segmentId: 's_0',
          kind: SpeechAnnotationKind.dialogueSpan,
          startWord: 0,
          endWord: 2,
          confidence: 0.8,
          source: SpeechAnnotationSource.ruleBasedLinguisticInference,
          dialogueSpanId: '',
          dialogueSpanClass: 'dialogue',
        ),
        throwsArgumentError,
      );

      expect(
        () => SpeechAnnotation(
          annotationId: 'ann_dialogue_span',
          segmentId: 's_0',
          kind: SpeechAnnotationKind.dialogueSpan,
          startWord: 0,
          endWord: 2,
          confidence: 0.8,
          source: SpeechAnnotationSource.ruleBasedLinguisticInference,
          dialogueSpanId: 'dlg_s_0',
          dialogueSpanClass: 'aside',
        ),
        throwsArgumentError,
      );
    });

    test('serializes dialogue span fields on dialogue-span annotations', () {
      final annotation = SpeechAnnotation(
        annotationId: 'ann_dialogue_span',
        segmentId: 's_0',
        kind: SpeechAnnotationKind.dialogueSpan,
        startWord: 0,
        endWord: 2,
        confidence: 0.8,
        source: SpeechAnnotationSource.ruleBasedLinguisticInference,
        dialogueSpanId: 'dlg_s_0',
        dialogueSpanClass: 'dialogue',
      );

      final json = annotation.toJson();
      expect(json['dialogueSpanId'], 'dlg_s_0');
      expect(json['dialogueSpanClass'], 'dialogue');
    });

    test('requires supported say-as vocabulary', () {
      expect(
        () => SpeechAnnotation(
          annotationId: 'ann_say_as',
          segmentId: 's_0',
          kind: SpeechAnnotationKind.sayAsCandidate,
          startWord: 0,
          endWord: 1,
          confidence: 0.8,
          source: SpeechAnnotationSource.ruleBasedLinguisticInference,
          sayAsClass: 'ordinal',
        ),
        throwsArgumentError,
      );
    });
  });
}
