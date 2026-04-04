import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_voice_assignment.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/dialogue_attribution.dart';
import 'package:read_aloud/src/models/display_document.dart';
import 'package:read_aloud/src/models/speech_document.dart';
import 'package:read_aloud/src/services/base_speech_annotation_inference_service.dart';
import 'package:read_aloud/src/services/cast_aware_speech_route_service.dart';

void main() {
  group('CastAwareSpeechRouteService', () {
    const annotationService = BaseSpeechAnnotationInferenceService();
    const routeService = CastAwareSpeechRouteService();

    test(
      'routes narration and attributed dialogue to different cast voices',
      () {
        final displayDocument = DisplayDocument(
          documentId: 'doc_route_0',
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

        final routes = routeService.build(
          CastAwareSpeechRouteInput(
            speechDocument: speechDocument,
            baseAnnotations: annotations,
            dialogueAttributions: DialogueAttributionSet(
              documentId: 'doc_route_0',
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
                  speakerReference: SpeakerReference(
                    referenceId: 'speaker_jennifer',
                    displayLabel: 'Jennifer',
                    normalizedLabel: 'jennifer',
                  ),
                ),
              ],
            ),
            characterCastRegistry: CharacterCastRegistry(
              documentId: 'doc_route_0',
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
            castVoiceAssignments: CastVoiceAssignmentSet(
              documentId: 'doc_route_0',
              assignmentVersion: 'assign-v1',
              assignments: <CastVoiceAssignment>[
                CastVoiceAssignment(
                  castId: 'cast_narrator',
                  effectiveVoiceId: 'af_bella',
                  decisionKind: VoiceAssignmentDecisionKind.automatic,
                ),
                CastVoiceAssignment(
                  castId: 'cast_character_jennifer',
                  effectiveVoiceId: 'bf_emma',
                  decisionKind: VoiceAssignmentDecisionKind.automatic,
                ),
              ],
            ),
          ),
        );

        expect(routes.ranges, hasLength(3));
        expect(routes.ranges[0].castId, 'cast_narrator');
        expect(routes.ranges[1].castId, 'cast_character_jennifer');
        expect(routes.ranges[1].voiceId, 'bf_emma');
        expect(routes.ranges[1].dialogueSpanId, 'dlg_s_1');
        expect(routes.ranges[2].castId, 'cast_narrator');
      },
    );

    test('merges adjacent narrator ranges with identical voice routing', () {
      final displayDocument = DisplayDocument(
        documentId: 'doc_route_1',
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

      final routes = routeService.build(
        CastAwareSpeechRouteInput(
          speechDocument: speechDocument,
          baseAnnotations: annotations,
          dialogueAttributions: DialogueAttributionSet(
            documentId: 'doc_route_1',
            attributionVersion: 'attr-v1',
            providerId: 'heuristic',
            providerVersion: 'v1',
            outcomes: const <DialogueAttributionOutcome>[],
          ),
          characterCastRegistry: CharacterCastRegistry(
            documentId: 'doc_route_1',
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
          castVoiceAssignments: CastVoiceAssignmentSet(
            documentId: 'doc_route_1',
            assignmentVersion: 'assign-v1',
            assignments: <CastVoiceAssignment>[
              CastVoiceAssignment(
                castId: 'cast_narrator',
                effectiveVoiceId: 'af_bella',
                decisionKind: VoiceAssignmentDecisionKind.automatic,
              ),
            ],
          ),
        ),
      );

      expect(routes.ranges, hasLength(1));
      expect(routes.ranges.single.segmentIds, <String>['s_0', 's_1']);
    });

    test('falls back to narrator routing for unattributed dialogue', () {
      final displayDocument = DisplayDocument(
        documentId: 'doc_route_2',
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

      final routes = routeService.build(
        CastAwareSpeechRouteInput(
          speechDocument: speechDocument,
          baseAnnotations: annotations,
          dialogueAttributions: DialogueAttributionSet(
            documentId: 'doc_route_2',
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
              ),
            ],
          ),
          characterCastRegistry: CharacterCastRegistry(
            documentId: 'doc_route_2',
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
          castVoiceAssignments: CastVoiceAssignmentSet(
            documentId: 'doc_route_2',
            assignmentVersion: 'assign-v1',
            assignments: <CastVoiceAssignment>[
              CastVoiceAssignment(
                castId: 'cast_narrator',
                effectiveVoiceId: 'af_bella',
                decisionKind: VoiceAssignmentDecisionKind.automatic,
              ),
            ],
          ),
        ),
      );

      expect(routes.ranges, hasLength(1));
      expect(routes.ranges.single.castId, 'cast_narrator');
      expect(routes.ranges.single.voiceId, 'af_bella');
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
