import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/dialogue_attribution.dart';
import 'package:read_aloud/src/services/character_cast_registry_service.dart';

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
      );

      expect(registry.entries, hasLength(1));
      expect(registry.narratorEntry.castId, 'cast_narrator');
      expect(registry.narratorEntry.roleKind, CastEntryRoleKind.narrator);
    });

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
              speakerReference: SpeakerReference(
                referenceId: 'speaker_jennifer',
                displayLabel: 'Jennifer',
                normalizedLabel: 'jennifer',
              ),
            ),
            DialogueAttributionOutcome(
              attributionId: 'attr_dlg_1',
              dialogueSpanId: 'dlg_1',
              resolution: DialogueAttributionResolution.attributedSpeaker,
              confidence: 0.6,
              provenance: DialogueAttributionProvenance.heuristicInference,
              speakerReference: SpeakerReference(
                referenceId: 'speaker_jennifer',
                displayLabel: 'Jennifer',
                normalizedLabel: 'jennifer',
              ),
            ),
          ],
        ),
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
              speakerReference: SpeakerReference(
                referenceId: 'speaker_jennifer',
                displayLabel: 'Jen',
                normalizedLabel: 'jennifer',
              ),
            ),
            DialogueAttributionOutcome(
              attributionId: 'attr_dlg_1',
              dialogueSpanId: 'dlg_1',
              resolution: DialogueAttributionResolution.attributedSpeaker,
              confidence: 0.8,
              provenance: DialogueAttributionProvenance.heuristicInference,
              speakerReference: SpeakerReference(
                referenceId: 'speaker_jennifer',
                displayLabel: 'Jennifer',
                normalizedLabel: 'jennifer',
              ),
            ),
          ],
        ),
      );

      final entry = registry.characterEntries.single;
      expect(entry.observedAliases, <String>['Jen', 'Jennifer']);
    });
  });
}
