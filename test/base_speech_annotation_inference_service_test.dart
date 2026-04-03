import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/display_document.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/speech_document.dart';
import 'package:read_aloud/src/services/base_speech_annotation_inference_service.dart';

void main() {
  group('BaseSpeechAnnotationInferenceService', () {
    const service = BaseSpeechAnnotationInferenceService();

    test(
      'infers first-round discourse-role vocabulary from segment context',
      () {
        final displayDocument = DisplayDocument(
          documentId: 'doc_roles',
          sourceType: 'test',
          sourceUri: null,
          title: 'Roles',
          normalizationVersion: 'norm-v1',
          metadata: const <String, String>{},
          assets: const <String, DisplayAsset>{},
          blocks: <DisplayBlock>[
            _block(
              blockId: 'b_heading',
              kind: DisplayBlockKind.heading,
              ordinal: 0,
              text: 'Chapter One',
            ),
            _block(
              blockId: 'b_dialogue',
              kind: DisplayBlockKind.paragraph,
              ordinal: 1,
              text: '"Hello there."',
            ),
            _block(
              blockId: 'b_quote',
              kind: DisplayBlockKind.blockquote,
              ordinal: 2,
              text: 'Quoted material from elsewhere.',
            ),
            _block(
              blockId: 'b_list',
              kind: DisplayBlockKind.listItem,
              ordinal: 3,
              text: 'First item',
            ),
            _block(
              blockId: 'b_caption',
              kind: DisplayBlockKind.paragraph,
              ordinal: 4,
              text: 'A shelf of books.',
              attributes: const <String, String>{'role': 'caption'},
            ),
            _block(
              blockId: 'b_narration',
              kind: DisplayBlockKind.paragraph,
              ordinal: 5,
              text: 'Plain narration text.',
            ),
          ],
        );

        final speechDocument = _speechDocument(<SpeechSegment>[
          _segment(
            segmentId: 's_heading',
            blockId: 'b_heading',
            ordinal: 0,
            paragraphIndex: 0,
            sentenceIndex: 0,
            text: 'Chapter One',
          ),
          _segment(
            segmentId: 's_dialogue',
            blockId: 'b_dialogue',
            ordinal: 1,
            paragraphIndex: 1,
            sentenceIndex: 0,
            text: '"Hello there."',
          ),
          _segment(
            segmentId: 's_quote',
            blockId: 'b_quote',
            ordinal: 2,
            paragraphIndex: 2,
            sentenceIndex: 0,
            text: 'Quoted material from elsewhere.',
          ),
          _segment(
            segmentId: 's_list',
            blockId: 'b_list',
            ordinal: 3,
            paragraphIndex: 3,
            sentenceIndex: 0,
            text: 'First item',
          ),
          _segment(
            segmentId: 's_caption',
            blockId: 'b_caption',
            ordinal: 4,
            paragraphIndex: 4,
            sentenceIndex: 0,
            text: 'A shelf of books.',
          ),
          _segment(
            segmentId: 's_narration',
            blockId: 'b_narration',
            ordinal: 5,
            paragraphIndex: 5,
            sentenceIndex: 0,
            text: 'Plain narration text.',
          ),
        ]);

        final annotations = service.infer(
          speechDocument: speechDocument,
          displayDocument: displayDocument,
        );

        final roles = <String, String>{
          for (final annotation in annotations.annotations.where(
            (annotation) =>
                annotation.kind == SpeechAnnotationKind.discourseRole,
          ))
            annotation.segmentId: annotation.discourseRole!,
        };

        expect(roles['s_heading'], 'heading');
        expect(roles['s_dialogue'], 'dialogue');
        expect(roles['s_quote'], 'quotation');
        expect(roles['s_list'], 'list_item');
        expect(roles['s_caption'], 'caption');
        expect(roles['s_narration'], 'narration');
      },
    );

    test('emits say-as and emphasis candidates from rule-based inference', () {
      final displayDocument = DisplayDocument(
        documentId: 'doc_inference',
        sourceType: 'test',
        sourceUri: null,
        title: 'Inference',
        normalizationVersion: 'norm-v1',
        metadata: const <String, String>{},
        assets: const <String, DisplayAsset>{},
        blocks: <DisplayBlock>[
          _block(
            blockId: 'b_0',
            kind: DisplayBlockKind.paragraph,
            ordinal: 0,
            text: 'NASA has 3 missions.',
          ),
          _block(
            blockId: 'b_1',
            kind: DisplayBlockKind.paragraph,
            ordinal: 1,
            text: '"JUST STOP FIGHTING!"',
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
          text: 'NASA has 3 missions.',
        ),
        _segment(
          segmentId: 's_1',
          blockId: 'b_1',
          ordinal: 1,
          paragraphIndex: 1,
          sentenceIndex: 0,
          text: '"JUST STOP FIGHTING!"',
        ),
      ]);

      final annotations = service.infer(
        speechDocument: speechDocument,
        displayDocument: displayDocument,
      );

      final sayAsAnnotations = annotations.annotations
          .where(
            (annotation) =>
                annotation.kind == SpeechAnnotationKind.sayAsCandidate,
          )
          .toList(growable: false);
      final sayAsClasses = sayAsAnnotations
          .map((annotation) => annotation.sayAsClass)
          .toSet();

      expect(sayAsClasses, containsAll(<String?>{'letters', 'cardinal'}));

      final emphasisAnnotations = annotations.annotations
          .where(
            (annotation) =>
                annotation.kind == SpeechAnnotationKind.emphasisCandidate,
          )
          .toList(growable: false);

      expect(
        emphasisAnnotations,
        contains(
          isA<SpeechAnnotation>()
              .having((annotation) => annotation.segmentId, 'segmentId', 's_1')
              .having((annotation) => annotation.startWord, 'startWord', 0)
              .having((annotation) => annotation.endWord, 'endWord', 3),
        ),
      );
    });
  });
}

DisplayBlock _block({
  required String blockId,
  required DisplayBlockKind kind,
  required int ordinal,
  required String text,
  Map<String, String> attributes = const <String, String>{},
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
    attributes: attributes,
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
