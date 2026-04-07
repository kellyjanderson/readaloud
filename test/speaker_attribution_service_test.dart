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
      expect(
        attributions.outcomes.single.ruleUsed,
        DialogueAttributionRule.sameSentenceExplicit,
      );
      expect(attributions.outcomes.single.evidenceSpan?.text, 'Jennifer');
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
      expect(attributions.outcomes.single.confidence, 0.9);
      expect(
        attributions.outcomes.single.ruleUsed,
        DialogueAttributionRule.adjacentAfter,
      );
    });

    test(
      'attributes loose name-plus-action-plus-speech-verb patterns before a quote',
      () {
        final displayDocument = DisplayDocument(
          documentId: 'doc_attr_3',
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
              text: 'Jennifer turned and said, "Go now."',
            ),
          ],
        );

        final speechDocument = _speechDocument(<SpeechSegment>[
          _segment(
            segmentId: 's_tag',
            blockId: 'b_0',
            ordinal: 0,
            paragraphIndex: 0,
            sentenceIndex: 0,
            text: 'Jennifer turned and said,',
          ),
          _segment(
            segmentId: 's_dialogue',
            blockId: 'b_0',
            ordinal: 1,
            paragraphIndex: 0,
            sentenceIndex: 1,
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
          attributions.outcomes.single.speakerReference?.displayLabel,
          'Jennifer',
        );
        expect(attributions.outcomes.single.confidence, 0.82);
        expect(
          attributions.outcomes.single.ruleUsed,
          DialogueAttributionRule.adjacentBefore,
        );
      },
    );

    test('attributes verb-before-name tags after a quote', () {
      final displayDocument = DisplayDocument(
        documentId: 'doc_attr_4',
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
            text: '"Go now," said John.',
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
          text: '"Go now,"',
        ),
        _segment(
          segmentId: 's_tag',
          blockId: 'b_0',
          ordinal: 1,
          paragraphIndex: 0,
          sentenceIndex: 1,
          text: 'said John.',
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
        'John',
      );
      expect(attributions.outcomes.single.confidence, 0.9);
      expect(
        attributions.outcomes.single.ruleUsed,
        DialogueAttributionRule.adjacentAfter,
      );
    });

    test('attributes quote speakers from trailing screamed narration', () {
      final displayDocument = DisplayDocument(
        documentId: 'doc_attr_5',
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
            text:
                '"JUST STOP FIGHTING!" Jennifer screamed, pulling on her hair.',
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
          text: '"JUST STOP FIGHTING!"',
        ),
        _segment(
          segmentId: 's_tag',
          blockId: 'b_0',
          ordinal: 1,
          paragraphIndex: 0,
          sentenceIndex: 1,
          text: 'Jennifer screamed, pulling on her hair.',
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
    });

    test('prefers the local trailing speaker tag in alternating quote exchanges', () {
      final displayDocument = DisplayDocument(
        documentId: 'doc_attr_6',
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
            text:
                '"John, why did you have to budge in front of me this morning?" '
                'Elliot said '
                '"I dunno. I thought taking someone\'s position in line is how we operate now," '
                'John replied sarcastically.',
          ),
        ],
      );

      final speechDocument = _speechDocument(<SpeechSegment>[
        _segment(
          segmentId: 's_quote_0',
          blockId: 'b_0',
          ordinal: 0,
          paragraphIndex: 0,
          sentenceIndex: 0,
          text:
              '"John, why did you have to budge in front of me this morning?"',
        ),
        _segment(
          segmentId: 's_tag_0',
          blockId: 'b_0',
          ordinal: 1,
          paragraphIndex: 0,
          sentenceIndex: 1,
          text: 'Elliot said',
        ),
        _segment(
          segmentId: 's_quote_1',
          blockId: 'b_0',
          ordinal: 2,
          paragraphIndex: 0,
          sentenceIndex: 2,
          text:
              '"I dunno. I thought taking someone\'s position in line is how we operate now,"',
        ),
        _segment(
          segmentId: 's_tag_1',
          blockId: 'b_0',
          ordinal: 3,
          paragraphIndex: 0,
          sentenceIndex: 3,
          text: 'John replied sarcastically.',
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

      expect(attributions.outcomes, hasLength(2));
      expect(attributions.outcomes[0].speakerReference?.displayLabel, 'Elliot');
      expect(
        attributions.outcomes[0].ruleUsed,
        DialogueAttributionRule.adjacentAfter,
      );
      expect(attributions.outcomes[1].speakerReference?.displayLabel, 'John');
      expect(
        attributions.outcomes[1].ruleUsed,
        DialogueAttributionRule.adjacentAfter,
      );
    });

    test(
      'keeps one speaker per dialogue paragraph when later quotes are bare',
      () {
        final displayDocument = DisplayDocument(
          documentId: 'doc_attr_7',
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
              text:
                  '"Go now." Jennifer said. She looked away for a moment. "Leave me alone."',
            ),
          ],
        );

        final speechDocument = _speechDocument(<SpeechSegment>[
          _segment(
            segmentId: 's_quote_0',
            blockId: 'b_0',
            ordinal: 0,
            paragraphIndex: 0,
            sentenceIndex: 0,
            text: '"Go now."',
          ),
          _segment(
            segmentId: 's_tag_0',
            blockId: 'b_0',
            ordinal: 1,
            paragraphIndex: 0,
            sentenceIndex: 1,
            text: 'Jennifer said.',
          ),
          _segment(
            segmentId: 's_bridge',
            blockId: 'b_0',
            ordinal: 2,
            paragraphIndex: 0,
            sentenceIndex: 2,
            text: 'She looked away for a moment.',
          ),
          _segment(
            segmentId: 's_quote_1',
            blockId: 'b_0',
            ordinal: 3,
            paragraphIndex: 0,
            sentenceIndex: 3,
            text: '"Leave me alone."',
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

        expect(attributions.outcomes, hasLength(2));
        expect(
          attributions.outcomes[1].speakerReference?.displayLabel,
          'Jennifer',
        );
        expect(
          attributions.outcomes[1].ruleUsed,
          DialogueAttributionRule.paragraphOwnership,
        );
      },
    );

    test(
      'alternates speakers across a local dialogue exchange when a paragraph is bare',
      () {
        final displayDocument = DisplayDocument(
          documentId: 'doc_attr_8',
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
            _block(
              blockId: 'b_1',
              kind: DisplayBlockKind.paragraph,
              ordinal: 1,
              text: '"No." John said.',
            ),
            _block(
              blockId: 'b_2',
              kind: DisplayBlockKind.paragraph,
              ordinal: 2,
              text: '"Please."',
            ),
          ],
        );

        final speechDocument = _speechDocument(<SpeechSegment>[
          _segment(
            segmentId: 's_0_quote',
            blockId: 'b_0',
            ordinal: 0,
            paragraphIndex: 0,
            sentenceIndex: 0,
            text: '"Go now."',
          ),
          _segment(
            segmentId: 's_0_tag',
            blockId: 'b_0',
            ordinal: 1,
            paragraphIndex: 0,
            sentenceIndex: 1,
            text: 'Jennifer said.',
          ),
          _segment(
            segmentId: 's_1_quote',
            blockId: 'b_1',
            ordinal: 2,
            paragraphIndex: 1,
            sentenceIndex: 2,
            text: '"No."',
          ),
          _segment(
            segmentId: 's_1_tag',
            blockId: 'b_1',
            ordinal: 3,
            paragraphIndex: 1,
            sentenceIndex: 3,
            text: 'John said.',
          ),
          _segment(
            segmentId: 's_2_quote',
            blockId: 'b_2',
            ordinal: 4,
            paragraphIndex: 2,
            sentenceIndex: 4,
            text: '"Please."',
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

        expect(attributions.outcomes, hasLength(3));
        expect(
          attributions.outcomes[2].speakerReference?.displayLabel,
          'Jennifer',
        );
        expect(
          attributions.outcomes[2].ruleUsed,
          DialogueAttributionRule.dialogueAlternation,
        );
      },
    );

    test(
      'uses pronoun-tag context only when there is one recent local speaker',
      () {
        final displayDocument = DisplayDocument(
          documentId: 'doc_attr_9',
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
            _block(
              blockId: 'b_1',
              kind: DisplayBlockKind.paragraph,
              ordinal: 1,
              text: '"Wait." she said.',
            ),
          ],
        );

        final speechDocument = _speechDocument(<SpeechSegment>[
          _segment(
            segmentId: 's_0_quote',
            blockId: 'b_0',
            ordinal: 0,
            paragraphIndex: 0,
            sentenceIndex: 0,
            text: '"Go now."',
          ),
          _segment(
            segmentId: 's_0_tag',
            blockId: 'b_0',
            ordinal: 1,
            paragraphIndex: 0,
            sentenceIndex: 1,
            text: 'Jennifer said.',
          ),
          _segment(
            segmentId: 's_1_quote',
            blockId: 'b_1',
            ordinal: 2,
            paragraphIndex: 1,
            sentenceIndex: 2,
            text: '"Wait."',
          ),
          _segment(
            segmentId: 's_1_tag',
            blockId: 'b_1',
            ordinal: 3,
            paragraphIndex: 1,
            sentenceIndex: 3,
            text: 'she said.',
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

        expect(attributions.outcomes, hasLength(2));
        expect(
          attributions.outcomes[1].speakerReference?.displayLabel,
          'Jennifer',
        );
        expect(
          attributions.outcomes[1].ruleUsed,
          DialogueAttributionRule.pronounResolution,
        );
        expect(
          attributions.outcomes[1].evidenceSpan?.text.toLowerCase(),
          'she',
        );
      },
    );

    test(
      'falls back to the most recent local speaker when no better evidence exists',
      () {
        final displayDocument = DisplayDocument(
          documentId: 'doc_attr_10',
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
              text: '"Go now." John said.',
            ),
            _block(
              blockId: 'b_1',
              kind: DisplayBlockKind.paragraph,
              ordinal: 1,
              text: '"Fine."',
            ),
          ],
        );

        final speechDocument = _speechDocument(<SpeechSegment>[
          _segment(
            segmentId: 's_0_quote',
            blockId: 'b_0',
            ordinal: 0,
            paragraphIndex: 0,
            sentenceIndex: 0,
            text: '"Go now."',
          ),
          _segment(
            segmentId: 's_0_tag',
            blockId: 'b_0',
            ordinal: 1,
            paragraphIndex: 0,
            sentenceIndex: 1,
            text: 'John said.',
          ),
          _segment(
            segmentId: 's_1_quote',
            blockId: 'b_1',
            ordinal: 2,
            paragraphIndex: 1,
            sentenceIndex: 2,
            text: '"Fine."',
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

        expect(attributions.outcomes, hasLength(2));
        expect(attributions.outcomes[1].speakerReference?.displayLabel, 'John');
        expect(
          attributions.outcomes[1].ruleUsed,
          DialogueAttributionRule.speakerPersistence,
        );
      },
    );

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
        expect(
          attributions.outcomes.single.ruleUsed,
          DialogueAttributionRule.noEvidence,
        );
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
