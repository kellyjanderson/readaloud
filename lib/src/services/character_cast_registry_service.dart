import '../models/character_cast_registry.dart';
import '../models/dialogue_attribution.dart';

class CharacterCastRegistryService {
  const CharacterCastRegistryService();

  static const registryVersion = 'read-aloud-character-cast-registry-v1';

  CharacterCastRegistry build({
    required DialogueAttributionSet dialogueAttributions,
  }) {
    final entries = <CastEntry>[
      CastEntry(
        castId: 'cast_narrator',
        roleKind: CastEntryRoleKind.narrator,
        displayLabel: 'Narrator',
        confidence: 1.0,
        provenance: CastEntryProvenance.syntheticNarrator,
      ),
    ];

    final groupedOutcomes = <String, List<DialogueAttributionOutcome>>{};
    for (final outcome in dialogueAttributions.outcomes) {
      if (outcome.resolution !=
              DialogueAttributionResolution.attributedSpeaker ||
          outcome.speakerReference == null) {
        continue;
      }
      final key = outcome.speakerReference!.normalizedLabel;
      groupedOutcomes
          .putIfAbsent(key, () => <DialogueAttributionOutcome>[])
          .add(outcome);
    }

    final sortedKeys = groupedOutcomes.keys.toList(growable: false)..sort();
    for (final key in sortedKeys) {
      final outcomes = groupedOutcomes[key]!;
      final aliases =
          outcomes
              .map((outcome) => outcome.speakerReference!.displayLabel)
              .toSet()
              .toList(growable: false)
            ..sort();
      final attributionIds =
          outcomes
              .map((outcome) => outcome.attributionId)
              .toList(growable: false)
            ..sort();
      final confidence =
          outcomes.fold<double>(
            0.0,
            (sum, outcome) => sum + outcome.confidence,
          ) /
          outcomes.length;
      entries.add(
        CastEntry(
          castId: _castIdForNormalizedLabel(key),
          roleKind: CastEntryRoleKind.character,
          displayLabel: aliases.first,
          confidence: confidence,
          provenance: castEntryProvenanceForAttribution(
            outcomes.first.provenance,
          ),
          observedAliases: aliases,
          attributionIds: attributionIds,
        ),
      );
    }

    return CharacterCastRegistry(
      documentId: dialogueAttributions.documentId,
      registryVersion: registryVersion,
      entries: entries,
    );
  }

  String _castIdForNormalizedLabel(String normalizedLabel) {
    final slug = normalizedLabel
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'cast_character_${slug.isEmpty ? 'unknown' : slug}';
  }
}
