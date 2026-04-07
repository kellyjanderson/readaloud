import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/display_document.dart';
import 'package:read_aloud/src/models/dialogue_attribution.dart';
import 'package:read_aloud/src/models/speech_document.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/base_speech_annotation_inference_service.dart';
import 'package:read_aloud/src/services/character_cast_registry_service.dart';
import 'package:read_aloud/src/services/speaker_attribution_service.dart';

void main() {
  group('CharacterCastRegistryService', () {
    const service = CharacterCastRegistryService();

    test('always creates one explicit narrator entry', () {
      final registry = service.build(
        dialogueAttributions: DialogueAttributionSet(
          documentId: 'doc_1',
          attributionVersion: 'attr-v1',
          providerId: 'heuristic',
          providerVersion: 'v1',
          outcomes: const <DialogueAttributionOutcome>[],
        ),
        speechDocument: _speechDocument(const <SpeechSegment>[]),
      );

      expect(registry.entries, hasLength(1));
      expect(registry.narratorEntry.castId, 'cast_narrator');
      expect(registry.narratorEntry.roleKind, CastEntryRoleKind.narrator);
    });

    test(
      'does not extract identity from raw mentions before canonical character creation',
      () {
        final registry = service.build(
          dialogueAttributions: DialogueAttributionSet(
            documentId: 'doc_1',
            attributionVersion: 'attr-v1',
            providerId: 'heuristic',
            providerVersion: 'v1',
            outcomes: const <DialogueAttributionOutcome>[],
          ),
          speechDocument: _speechDocument(<SpeechSegment>[
            _segment(
              segmentId: 's_0',
              blockId: 'b_0',
              ordinal: 0,
              paragraphIndex: 0,
              sentenceIndex: 0,
              text: 'Alex is nonbinary.',
            ),
          ]),
        );

        expect(registry.characterEntries, isEmpty);
      },
    );

    test('clusters repeated attributed speakers into one character entry', () {
      final registry = service.build(
        dialogueAttributions: DialogueAttributionSet(
          documentId: 'doc_1',
          attributionVersion: 'attr-v1',
          providerId: 'heuristic',
          providerVersion: 'v1',
          outcomes: <DialogueAttributionOutcome>[
            DialogueAttributionOutcome(
              attributionId: 'attr_dlg_0',
              dialogueSpanId: 'dlg_0',
              resolution: DialogueAttributionResolution.attributedSpeaker,
              confidence: 0.8,
              provenance: DialogueAttributionProvenance.heuristicInference,
              ruleUsed: DialogueAttributionRule.sameSentenceExplicit,
              speakerReference: SpeakerReference(
                referenceId: 'speaker_jennifer',
                displayLabel: 'Jennifer',
                normalizedLabel: 'jennifer',
              ),
              evidenceSpan: DialogueEvidenceSpan(
                segmentId: 's_0',
                startUtf16: 0,
                endUtf16: 8,
                text: 'Jennifer',
              ),
            ),
            DialogueAttributionOutcome(
              attributionId: 'attr_dlg_1',
              dialogueSpanId: 'dlg_1',
              resolution: DialogueAttributionResolution.attributedSpeaker,
              confidence: 0.6,
              provenance: DialogueAttributionProvenance.heuristicInference,
              ruleUsed: DialogueAttributionRule.sameSentenceExplicit,
              speakerReference: SpeakerReference(
                referenceId: 'speaker_jennifer',
                displayLabel: 'Jennifer',
                normalizedLabel: 'jennifer',
              ),
              evidenceSpan: DialogueEvidenceSpan(
                segmentId: 's_1',
                startUtf16: 0,
                endUtf16: 8,
                text: 'Jennifer',
              ),
            ),
          ],
        ),
        speechDocument: _speechDocument(const <SpeechSegment>[]),
      );

      expect(registry.characterEntries, hasLength(1));
      final entry = registry.characterEntries.single;
      expect(entry.castId, 'cast_character_jennifer');
      expect(entry.displayLabel, 'Jennifer');
      expect(entry.attributionIds, <String>['attr_dlg_0', 'attr_dlg_1']);
      expect(entry.confidence, closeTo(0.7, 0.0001));
    });

    test('preserves aliases across differently surfaced speaker labels', () {
      final registry = service.build(
        dialogueAttributions: DialogueAttributionSet(
          documentId: 'doc_1',
          attributionVersion: 'attr-v1',
          providerId: 'heuristic',
          providerVersion: 'v1',
          outcomes: <DialogueAttributionOutcome>[
            DialogueAttributionOutcome(
              attributionId: 'attr_dlg_0',
              dialogueSpanId: 'dlg_0',
              resolution: DialogueAttributionResolution.attributedSpeaker,
              confidence: 0.8,
              provenance: DialogueAttributionProvenance.heuristicInference,
              ruleUsed: DialogueAttributionRule.sameSentenceExplicit,
              speakerReference: SpeakerReference(
                referenceId: 'speaker_jennifer',
                displayLabel: 'Jen',
                normalizedLabel: 'jennifer',
              ),
              evidenceSpan: DialogueEvidenceSpan(
                segmentId: 's_0',
                startUtf16: 0,
                endUtf16: 3,
                text: 'Jen',
              ),
            ),
            DialogueAttributionOutcome(
              attributionId: 'attr_dlg_1',
              dialogueSpanId: 'dlg_1',
              resolution: DialogueAttributionResolution.attributedSpeaker,
              confidence: 0.8,
              provenance: DialogueAttributionProvenance.heuristicInference,
              ruleUsed: DialogueAttributionRule.sameSentenceExplicit,
              speakerReference: SpeakerReference(
                referenceId: 'speaker_jennifer',
                displayLabel: 'Jennifer',
                normalizedLabel: 'jennifer',
              ),
              evidenceSpan: DialogueEvidenceSpan(
                segmentId: 's_1',
                startUtf16: 0,
                endUtf16: 8,
                text: 'Jennifer',
              ),
            ),
          ],
        ),
        speechDocument: _speechDocument(const <SpeechSegment>[]),
      );

      final entry = registry.characterEntries.single;
      expect(entry.observedAliases, <String>['Jen', 'Jennifer']);
    });

    test(
      'consolidates obvious longer-name typo variants into one character',
      () {
        final registry = service.build(
          dialogueAttributions: DialogueAttributionSet(
            documentId: 'doc_1',
            attributionVersion: 'attr-v1',
            providerId: 'heuristic',
            providerVersion: 'v1',
            outcomes: <DialogueAttributionOutcome>[
              _outcome(
                attributionId: 'attr_dlg_0',
                dialogueSpanId: 'dlg_0',
                displayLabel: 'Jennifer',
                normalizedLabel: 'jennifer',
              ),
              _outcome(
                attributionId: 'attr_dlg_1',
                dialogueSpanId: 'dlg_1',
                displayLabel: 'Jenifer',
                normalizedLabel: 'jenifer',
              ),
              _outcome(
                attributionId: 'attr_dlg_2',
                dialogueSpanId: 'dlg_2',
                displayLabel: 'Jenefer',
                normalizedLabel: 'jenefer',
              ),
            ],
          ),
          speechDocument: _speechDocument(const <SpeechSegment>[]),
        );

        expect(registry.characterEntries, hasLength(1));
        final entry = registry.characterEntries.single;
        expect(entry.displayLabel, 'Jennifer');
        expect(entry.observedAliases, <String>[
          'Jenefer',
          'Jenifer',
          'Jennifer',
        ]);
        expect(entry.attributionIds, <String>[
          'attr_dlg_0',
          'attr_dlg_1',
          'attr_dlg_2',
        ]);
      },
    );

    test(
      'extracts explicit identity labels and preserves specific categories',
      () {
        final registry = service.build(
          dialogueAttributions: DialogueAttributionSet(
            documentId: 'doc_1',
            attributionVersion: 'attr-v1',
            providerId: 'heuristic',
            providerVersion: 'v1',
            outcomes: <DialogueAttributionOutcome>[
              _outcome(
                attributionId: 'attr_dlg_0',
                dialogueSpanId: 'dlg_0',
                displayLabel: 'Mara',
                normalizedLabel: 'mara',
              ),
              _outcome(
                attributionId: 'attr_dlg_1',
                dialogueSpanId: 'dlg_1',
                displayLabel: 'Alex',
                normalizedLabel: 'alex',
              ),
              _outcome(
                attributionId: 'attr_dlg_2',
                dialogueSpanId: 'dlg_2',
                displayLabel: 'Jon',
                normalizedLabel: 'jon',
              ),
            ],
          ),
          speechDocument: _speechDocument(<SpeechSegment>[
            _segment(
              segmentId: 's_0',
              blockId: 'b_0',
              ordinal: 0,
              paragraphIndex: 0,
              sentenceIndex: 0,
              text: 'Mara, a cis woman, checked the latch.',
            ),
            _segment(
              segmentId: 's_1',
              blockId: 'b_1',
              ordinal: 1,
              paragraphIndex: 1,
              sentenceIndex: 0,
              text: 'Alex is nonbinary.',
            ),
            _segment(
              segmentId: 's_2',
              blockId: 'b_2',
              ordinal: 2,
              paragraphIndex: 2,
              sentenceIndex: 0,
              text: 'Jon is a transgender man.',
            ),
          ]),
        );

        expect(
          registry
              .forCastId('cast_character_mara')
              ?.identityProfile
              ?.genderIdentityLabel,
          CharacterGenderIdentityLabel.cisFemale,
        );
        expect(
          registry
              .forCastId('cast_character_mara')
              ?.identityProfile
              ?.genderSource,
          CharacterGenderEvidenceSource.explicitApposition,
        );
        expect(
          registry
              .forCastId('cast_character_alex')
              ?.identityProfile
              ?.genderIdentityLabel,
          CharacterGenderIdentityLabel.nonbinary,
        );
        expect(
          registry
              .forCastId('cast_character_jon')
              ?.identityProfile
              ?.genderIdentityLabel,
          CharacterGenderIdentityLabel.transMale,
        );
      },
    );

    test('uses attached descriptors as secondary identity evidence', () {
      final registry = service.build(
        dialogueAttributions: DialogueAttributionSet(
          documentId: 'doc_1',
          attributionVersion: 'attr-v1',
          providerId: 'heuristic',
          providerVersion: 'v1',
          outcomes: <DialogueAttributionOutcome>[
            _outcome(
              attributionId: 'attr_dlg_0',
              dialogueSpanId: 'dlg_0',
              displayLabel: 'Sam',
              normalizedLabel: 'sam',
            ),
          ],
        ),
        speechDocument: _speechDocument(<SpeechSegment>[
          _segment(
            segmentId: 's_0',
            blockId: 'b_0',
            ordinal: 0,
            paragraphIndex: 0,
            sentenceIndex: 0,
            text: 'Sam, the brother, opened the door.',
          ),
        ]),
      );

      final sam = registry.forCastId('cast_character_sam');
      expect(
        sam?.identityProfile?.genderIdentityLabel,
        CharacterGenderIdentityLabel.male,
      );
      expect(
        sam?.identityProfile?.genderSource,
        CharacterGenderEvidenceSource.descriptor,
      );
    });

    test(
      'extracts pronoun profiles separately from identity fallback decisions',
      () {
        const annotationService = BaseSpeechAnnotationInferenceService();
        final displayDocument = DisplayDocument(
          documentId: 'doc_attr_gender',
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
                  'Jennifer folded her arms. "Go now," Jennifer said. She glared at John.',
            ),
            _block(
              blockId: 'b_1',
              kind: DisplayBlockKind.paragraph,
              ordinal: 1,
              text: 'John shook his head. "No," John replied. He turned away.',
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
            text: 'Jennifer folded her arms.',
          ),
          _segment(
            segmentId: 's_1',
            blockId: 'b_0',
            ordinal: 1,
            paragraphIndex: 0,
            sentenceIndex: 1,
            text: '"Go now," Jennifer said.',
          ),
          _segment(
            segmentId: 's_2',
            blockId: 'b_0',
            ordinal: 2,
            paragraphIndex: 0,
            sentenceIndex: 2,
            text: 'She glared at John.',
          ),
          _segment(
            segmentId: 's_3',
            blockId: 'b_1',
            ordinal: 3,
            paragraphIndex: 1,
            sentenceIndex: 0,
            text: 'John shook his head.',
          ),
          _segment(
            segmentId: 's_4',
            blockId: 'b_1',
            ordinal: 4,
            paragraphIndex: 1,
            sentenceIndex: 1,
            text: '"No," John replied.',
          ),
          _segment(
            segmentId: 's_5',
            blockId: 'b_1',
            ordinal: 5,
            paragraphIndex: 1,
            sentenceIndex: 2,
            text: 'He turned away.',
          ),
        ]);

        final annotations = annotationService.infer(
          speechDocument: speechDocument,
          displayDocument: displayDocument,
        );
        final attributions = const _SpeakerAttributionHarness().attribute(
          speechDocument: speechDocument,
          baseAnnotations: annotations,
        );
        final registry = service.build(
          dialogueAttributions: attributions,
          speechDocument: speechDocument,
        );

        final jennifer = registry.forCastId('cast_character_jennifer');
        final john = registry.forCastId('cast_character_john');

        expect(
          jennifer?.identityProfile?.genderIdentityLabel,
          CharacterGenderIdentityLabel.female,
        );
        expect(
          jennifer?.identityProfile?.genderSource,
          CharacterGenderEvidenceSource.pronoun,
        );
        expect(
          jennifer?.identityProfile?.pronounProfile.countFor('her'),
          greaterThan(0),
        );
        expect(
          john?.identityProfile?.genderIdentityLabel,
          CharacterGenderIdentityLabel.male,
        );
        expect(
          john?.identityProfile?.genderSource,
          CharacterGenderEvidenceSource.pronoun,
        );
        expect(
          john?.identityProfile?.pronounProfile.countFor('his'),
          greaterThan(0),
        );
      },
    );

    test(
      'returns unknown with conflict flag for unresolved explicit conflicts',
      () {
        final registry = service.build(
          dialogueAttributions: DialogueAttributionSet(
            documentId: 'doc_1',
            attributionVersion: 'attr-v1',
            providerId: 'heuristic',
            providerVersion: 'v1',
            outcomes: <DialogueAttributionOutcome>[
              _outcome(
                attributionId: 'attr_dlg_0',
                dialogueSpanId: 'dlg_0',
                displayLabel: 'Rin',
                normalizedLabel: 'rin',
              ),
            ],
          ),
          speechDocument: _speechDocument(<SpeechSegment>[
            _segment(
              segmentId: 's_0',
              blockId: 'b_0',
              ordinal: 0,
              paragraphIndex: 0,
              sentenceIndex: 0,
              text: 'Rin is a woman.',
            ),
            _segment(
              segmentId: 's_1',
              blockId: 'b_1',
              ordinal: 1,
              paragraphIndex: 1,
              sentenceIndex: 0,
              text: 'Rin is a man.',
            ),
          ]),
        );

        final rin = registry.forCastId('cast_character_rin');
        expect(
          rin?.identityProfile?.genderIdentityLabel,
          CharacterGenderIdentityLabel.unknown,
        );
        expect(rin?.identityProfile?.conflictFlag, isTrue);
        expect(
          rin?.identityProfile?.genderSource,
          CharacterGenderEvidenceSource.explicitIdentity,
        );
      },
    );

    test('keeps legacy inferredGender compatibility getters working', () {
      final registry = service.build(
        dialogueAttributions: DialogueAttributionSet(
          documentId: 'doc_1',
          attributionVersion: 'attr-v1',
          providerId: 'heuristic',
          providerVersion: 'v1',
          outcomes: <DialogueAttributionOutcome>[
            _outcome(
              attributionId: 'attr_dlg_0',
              dialogueSpanId: 'dlg_0',
              displayLabel: 'Jennifer',
              normalizedLabel: 'jennifer',
            ),
          ],
        ),
        speechDocument: _speechDocument(<SpeechSegment>[
          _segment(
            segmentId: 's_0',
            blockId: 'b_0',
            ordinal: 0,
            paragraphIndex: 0,
            sentenceIndex: 0,
            text: 'Jennifer folded her arms. She glared.',
          ),
        ]),
      );

      expect(
        registry.forCastId('cast_character_jennifer')?.inferredGender,
        VoiceGender.female,
      );
      expect(
        registry.forCastId('cast_character_jennifer')?.inferredGenderConfidence,
        isNotNull,
      );
    });
  });
}

DialogueAttributionOutcome _outcome({
  required String attributionId,
  required String dialogueSpanId,
  required String displayLabel,
  required String normalizedLabel,
}) {
  return DialogueAttributionOutcome(
    attributionId: attributionId,
    dialogueSpanId: dialogueSpanId,
    resolution: DialogueAttributionResolution.attributedSpeaker,
    confidence: 0.8,
    provenance: DialogueAttributionProvenance.heuristicInference,
    ruleUsed: DialogueAttributionRule.sameSentenceExplicit,
    speakerReference: SpeakerReference(
      referenceId: 'speaker_$normalizedLabel',
      displayLabel: displayLabel,
      normalizedLabel: normalizedLabel,
    ),
    evidenceSpan: DialogueEvidenceSpan(
      segmentId: 's_$dialogueSpanId',
      startUtf16: 0,
      endUtf16: displayLabel.length,
      text: displayLabel,
    ),
  );
}

class _SpeakerAttributionHarness {
  const _SpeakerAttributionHarness();

  DialogueAttributionSet attribute({
    required SpeechDocument speechDocument,
    required BaseSpeechAnnotationSet baseAnnotations,
  }) {
    return const SpeakerAttributionService().attribute(
      speechDocument: speechDocument,
      baseAnnotations: baseAnnotations,
    );
  }
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
