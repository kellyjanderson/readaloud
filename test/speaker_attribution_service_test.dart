import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/dialogue_attribution.dart';
import 'package:read_aloud/src/models/display_document.dart';
import 'package:read_aloud/src/models/speech_document.dart';
import 'package:read_aloud/src/services/base_speech_annotation_inference_service.dart';
import 'package:read_aloud/src/services/speaker_attribution_service.dart';

void main() {
  group('SpeakerAttributionService', () {
    const annotationService = BaseSpeechAnnotationInferenceService();
    const attributionService = SpeakerAttributionService();

    test('attributes obvious in-segment name said patterns', () {
      final displayDocument = DisplayDocument(
        documentId: 'doc_attr_0',
        sourceType: 'test',
        sourceUri: null,
        title: 'Attribution',
        normalizationVersion: 'norm-v1',
        metadata: const <String, String>{},
        assets: const <String, DisplayAsset>{},
        blocks: <DisplayBlock>[
          _block(
            blockId: 'b_0',
            kind: DisplayBlockKind.paragraph,
            ordinal: 0,
            text: '"Go now," Jennifer said.',
          ),
        ],
      );

      final speechDocument = _speechDocument(<SpeechSegment>[
        _segment(
          segmentId: 's_0',
          blockId: 'b_0',
          ordinal: 0,
          paragraphIndex: 0,
          sentenceIndex: 0,
          text: '"Go now," Jennifer said.',
        ),
      ]);

      final annotations = annotationService.infer(
        speechDocument: speechDocument,
        displayDocument: displayDocument,
      );
      final attributions = attributionService.attribute(
        speechDocument: speechDocument,
        baseAnnotations: annotations,
      );

      expect(attributions.providerId, SpeakerAttributionService.providerId);
      expect(attributions.outcomes, hasLength(1));
      expect(
        attributions.outcomes.single.resolution,
        DialogueAttributionResolution.attributedSpeaker,
      );
      expect(
        attributions.outcomes.single.speakerReference?.displayLabel,
        'Jennifer',
      );
    });

    test('attributes obvious adjacent speaker tags in the same paragraph', () {
      final displayDocument = DisplayDocument(
        documentId: 'doc_attr_1',
        sourceType: 'test',
        sourceUri: null,
        title: 'Attribution',
        normalizationVersion: 'norm-v1',
        metadata: const <String, String>{},
        assets: const <String, DisplayAsset>{},
        blocks: <DisplayBlock>[
          _block(
            blockId: 'b_0',
            kind: DisplayBlockKind.paragraph,
            ordinal: 0,
            text: '"Go now." Jennifer said.',
          ),
        ],
      );

      final speechDocument = _speechDocument(<SpeechSegment>[
        _segment(
          segmentId: 's_dialogue',
          blockId: 'b_0',
          ordinal: 0,
          paragraphIndex: 0,
          sentenceIndex: 0,
          text: '"Go now."',
        ),
        _segment(
          segmentId: 's_tag',
          blockId: 'b_0',
          ordinal: 1,
          paragraphIndex: 0,
          sentenceIndex: 1,
          text: 'Jennifer said.',
        ),
      ]);

      final annotations = annotationService.infer(
        speechDocument: speechDocument,
        displayDocument: displayDocument,
      );
      final attributions = attributionService.attribute(
        speechDocument: speechDocument,
        baseAnnotations: annotations,
      );

      expect(attributions.outcomes, hasLength(1));
      expect(
        attributions.outcomes.single.speakerReference?.displayLabel,
        'Jennifer',
      );
      expect(attributions.outcomes.single.confidence, 0.72);
    });

    test(
      'emits explicit unattributed outcomes when no likely speaker exists',
      () {
        final displayDocument = DisplayDocument(
          documentId: 'doc_attr_2',
          sourceType: 'test',
          sourceUri: null,
          title: 'Attribution',
          normalizationVersion: 'norm-v1',
          metadata: const <String, String>{},
          assets: const <String, DisplayAsset>{},
          blocks: <DisplayBlock>[
            _block(
              blockId: 'b_0',
              kind: DisplayBlockKind.paragraph,
              ordinal: 0,
              text: '"Go now."',
            ),
          ],
        );

        final speechDocument = _speechDocument(<SpeechSegment>[
          _segment(
            segmentId: 's_0',
            blockId: 'b_0',
            ordinal: 0,
            paragraphIndex: 0,
            sentenceIndex: 0,
            text: '"Go now."',
          ),
        ]);

        final annotations = annotationService.infer(
          speechDocument: speechDocument,
          displayDocument: displayDocument,
        );
        final attributions = attributionService.attribute(
          speechDocument: speechDocument,
          baseAnnotations: annotations,
        );

        expect(attributions.outcomes, hasLength(1));
        expect(
          attributions.outcomes.single.resolution,
          DialogueAttributionResolution.unattributedDialogue,
        );
        expect(attributions.outcomes.single.speakerReference, isNull);
      },
    );
  });
}

DisplayBlock _block({
  required String blockId,
  required DisplayBlockKind kind,
  required int ordinal,
  required String text,
}) {
  return DisplayBlock(
    blockId: blockId,
    kind: kind,
    inlines: <DisplayInline>[
      DisplayInline(
        kind: DisplayInlineKind.text,
        text: text,
        attributes: const <String, String>{},
      ),
    ],
    attributes: const <String, String>{},
    assetId: null,
    parentBlockId: null,
    ordinal: ordinal,
  );
}

SpeechDocument _speechDocument(List<SpeechSegment> segments) {
  return SpeechDocument(
    documentId: 'doc_test',
    sourceType: 'test',
    languageTag: 'en-US',
    segments: segments,
    segmentIndexById: <String, int>{
      for (var index = 0; index < segments.length; index += 1)
        segments[index].segmentId: index,
    },
    totalWordCount: segments.fold<int>(
      0,
      (count, segment) => count + segment.wordCount,
    ),
    normalizationVersion: 'norm-v1',
  );
}

SpeechSegment _segment({
  required String segmentId,
  required String blockId,
  required int ordinal,
  required int paragraphIndex,
  required int sentenceIndex,
  required String text,
}) {
  final spans = <SpeechWordSpan>[];
  final matches = RegExp(r'\S+').allMatches(text).toList(growable: false);
  for (var index = 0; index < matches.length; index += 1) {
    final match = matches[index];
    spans.add(
      SpeechWordSpan(
        wordIndexWithinSegment: index,
        startUtf16: match.start,
        endUtf16: match.end,
        text: match.group(0)!,
      ),
    );
  }

  return SpeechSegment(
    segmentId: segmentId,
    blockId: blockId,
    ordinal: ordinal,
    paragraphIndex: paragraphIndex,
    sentenceIndex: sentenceIndex,
    normalizedText: text,
    wordCount: spans.length,
    sourceRange: null,
    displayAnchor: DisplayAnchor(
      blockId: blockId,
      startInlineOffset: 0,
      endInlineOffset: text.length,
    ),
    wordSpans: spans,
  );
}
