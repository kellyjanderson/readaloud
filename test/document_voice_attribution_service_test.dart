import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/dialogue_attribution.dart';
import 'package:read_aloud/src/models/display_document.dart';
import 'package:read_aloud/src/models/document_voice_attribution.dart';
import 'package:read_aloud/src/models/speech_document.dart';
import 'package:read_aloud/src/services/base_speech_annotation_inference_service.dart';
import 'package:read_aloud/src/services/document_voice_attribution_service.dart';

void main() {
  group('DocumentVoiceAttributionService', () {
    const annotationService = BaseSpeechAnnotationInferenceService();
    const attributionService = DocumentVoiceAttributionService();

    test(
      'materializes narrator and attributed dialogue as document-owned ranges',
      () {
        final displayDocument = DisplayDocument(
          documentId: 'doc_voice_attr_0',
          sourceType: 'test',
          sourceUri: null,
          title: 'Routing',
          normalizationVersion: 'norm-v1',
          metadata: const <String, String>{},
          assets: const <String, DisplayAsset>{},
          blocks: <DisplayBlock>[
            _block(blockId: 'b_0', ordinal: 0, text: 'The room was silent.'),
            _block(
              blockId: 'b_1',
              ordinal: 1,
              text: '"Go now," Jennifer said.',
            ),
            _block(blockId: 'b_2', ordinal: 2, text: 'John backed away.'),
          ],
        );
        final speechDocument = _speechDocument(<SpeechSegment>[
          _segment(
            segmentId: 's_0',
            blockId: 'b_0',
            ordinal: 0,
            paragraphIndex: 0,
            sentenceIndex: 0,
            text: 'The room was silent.',
          ),
          _segment(
            segmentId: 's_1',
            blockId: 'b_1',
            ordinal: 1,
            paragraphIndex: 1,
            sentenceIndex: 0,
            text: '"Go now," Jennifer said.',
          ),
          _segment(
            segmentId: 's_2',
            blockId: 'b_2',
            ordinal: 2,
            paragraphIndex: 2,
            sentenceIndex: 0,
            text: 'John backed away.',
          ),
        ]);
        final annotations = annotationService.infer(
          speechDocument: speechDocument,
          displayDocument: displayDocument,
        );

        final attribution = attributionService.build(
          DocumentVoiceAttributionInput(
            speechDocument: speechDocument,
            baseAnnotations: annotations,
            dialogueAttributions: DialogueAttributionSet(
              documentId: 'doc_voice_attr_0',
              attributionVersion: 'attr-v1',
              providerId: 'heuristic',
              providerVersion: 'v1',
              outcomes: <DialogueAttributionOutcome>[
                DialogueAttributionOutcome(
                  attributionId: 'attr_dlg_s_1',
                  dialogueSpanId: 'dlg_s_1',
                  resolution: DialogueAttributionResolution.attributedSpeaker,
                  confidence: 0.84,
                  provenance: DialogueAttributionProvenance.heuristicInference,
                  ruleUsed: DialogueAttributionRule.sameSentenceExplicit,
                  speakerReference: SpeakerReference(
                    referenceId: 'speaker_jennifer',
                    displayLabel: 'Jennifer',
                    normalizedLabel: 'jennifer',
                  ),
                  evidenceSpan: DialogueEvidenceSpan(
                    segmentId: 's_1',
                    startUtf16: 10,
                    endUtf16: 18,
                    text: 'Jennifer',
                  ),
                ),
              ],
            ),
            characterCastRegistry: CharacterCastRegistry(
              documentId: 'doc_voice_attr_0',
              registryVersion: 'registry-v1',
              entries: <CastEntry>[
                CastEntry(
                  castId: 'cast_narrator',
                  roleKind: CastEntryRoleKind.narrator,
                  displayLabel: 'Narrator',
                  confidence: 1.0,
                  provenance: CastEntryProvenance.syntheticNarrator,
                ),
                CastEntry(
                  castId: 'cast_character_jennifer',
                  roleKind: CastEntryRoleKind.character,
                  displayLabel: 'Jennifer',
                  confidence: 0.84,
                  provenance: CastEntryProvenance.attributedDialogueInference,
                  attributionIds: const <String>['attr_dlg_s_1'],
                ),
              ],
            ),
          ),
        );

        expect(attribution.ranges, hasLength(3));
        expect(attribution.ranges[0].kind, DocumentVoiceAttributionKind.narration);
        expect(attribution.ranges[0].castId, 'cast_narrator');
        expect(
          attribution.ranges[1].kind,
          DocumentVoiceAttributionKind.attributedDialogue,
        );
        expect(attribution.ranges[1].castId, 'cast_character_jennifer');
        expect(attribution.ranges[1].dialogueSpanId, 'dlg_s_1');
        expect(attribution.ranges[2].kind, DocumentVoiceAttributionKind.narration);
      },
    );

    test('merges adjacent narration ranges at document load', () {
      final displayDocument = DisplayDocument(
        documentId: 'doc_voice_attr_1',
        sourceType: 'test',
        sourceUri: null,
        title: 'Routing',
        normalizationVersion: 'norm-v1',
        metadata: const <String, String>{},
        assets: const <String, DisplayAsset>{},
        blocks: <DisplayBlock>[
          _block(blockId: 'b_0', ordinal: 0, text: 'One.'),
          _block(blockId: 'b_1', ordinal: 1, text: 'Two.'),
        ],
      );
      final speechDocument = _speechDocument(<SpeechSegment>[
        _segment(
          segmentId: 's_0',
          blockId: 'b_0',
          ordinal: 0,
          paragraphIndex: 0,
          sentenceIndex: 0,
          text: 'One.',
        ),
        _segment(
          segmentId: 's_1',
          blockId: 'b_1',
          ordinal: 1,
          paragraphIndex: 1,
          sentenceIndex: 0,
          text: 'Two.',
        ),
      ]);
      final annotations = annotationService.infer(
        speechDocument: speechDocument,
        displayDocument: displayDocument,
      );

      final attribution = attributionService.build(
        DocumentVoiceAttributionInput(
          speechDocument: speechDocument,
          baseAnnotations: annotations,
          dialogueAttributions: DialogueAttributionSet(
            documentId: 'doc_voice_attr_1',
            attributionVersion: 'attr-v1',
            providerId: 'heuristic',
            providerVersion: 'v1',
            outcomes: const <DialogueAttributionOutcome>[],
          ),
          characterCastRegistry: CharacterCastRegistry(
            documentId: 'doc_voice_attr_1',
            registryVersion: 'registry-v1',
            entries: <CastEntry>[
              CastEntry(
                castId: 'cast_narrator',
                roleKind: CastEntryRoleKind.narrator,
                displayLabel: 'Narrator',
                confidence: 1.0,
                provenance: CastEntryProvenance.syntheticNarrator,
              ),
            ],
          ),
        ),
      );

      expect(attribution.ranges, hasLength(1));
      expect(attribution.ranges.single.segmentIds, <String>['s_0', 's_1']);
    });

    test('preserves unattributed dialogue as explicit dialogue ownership data', () {
      final displayDocument = DisplayDocument(
        documentId: 'doc_voice_attr_2',
        sourceType: 'test',
        sourceUri: null,
        title: 'Routing',
        normalizationVersion: 'norm-v1',
        metadata: const <String, String>{},
        assets: const <String, DisplayAsset>{},
        blocks: <DisplayBlock>[
          _block(blockId: 'b_0', ordinal: 0, text: '"Go now."'),
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

      final attribution = attributionService.build(
        DocumentVoiceAttributionInput(
          speechDocument: speechDocument,
          baseAnnotations: annotations,
          dialogueAttributions: DialogueAttributionSet(
            documentId: 'doc_voice_attr_2',
            attributionVersion: 'attr-v1',
            providerId: 'heuristic',
            providerVersion: 'v1',
            outcomes: <DialogueAttributionOutcome>[
              DialogueAttributionOutcome(
                attributionId: 'attr_dlg_s_0',
                dialogueSpanId: 'dlg_s_0',
                resolution: DialogueAttributionResolution.unattributedDialogue,
                confidence: 0.0,
                provenance: DialogueAttributionProvenance.heuristicInference,
                ruleUsed: DialogueAttributionRule.noEvidence,
              ),
            ],
          ),
          characterCastRegistry: CharacterCastRegistry(
            documentId: 'doc_voice_attr_2',
            registryVersion: 'registry-v1',
            entries: <CastEntry>[
              CastEntry(
                castId: 'cast_narrator',
                roleKind: CastEntryRoleKind.narrator,
                displayLabel: 'Narrator',
                confidence: 1.0,
                provenance: CastEntryProvenance.syntheticNarrator,
              ),
            ],
          ),
        ),
      );

      expect(attribution.ranges, hasLength(1));
      expect(
        attribution.ranges.single.kind,
        DocumentVoiceAttributionKind.unattributedDialogue,
      );
      expect(attribution.ranges.single.castId, 'cast_narrator');
      expect(attribution.ranges.single.dialogueSpanId, 'dlg_s_0');
    });
  });
}

DisplayBlock _block({
  required String blockId,
  required int ordinal,
  required String text,
}) {
  return DisplayBlock(
    blockId: blockId,
    kind: DisplayBlockKind.paragraph,
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
