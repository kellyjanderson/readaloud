import 'dialogue_attribution.dart';

enum CastEntryRoleKind { narrator, character }

enum CastEntryProvenance {
  syntheticNarrator,
  attributedDialogueInference,
  sourceMetadata,
  providerOutput,
}

class CharacterCastRegistry {
  factory CharacterCastRegistry({
    required String documentId,
    required String registryVersion,
    required List<CastEntry> entries,
  }) {
    if (documentId.trim().isEmpty) {
      throw ArgumentError.value(
        documentId,
        'documentId',
        'documentId must not be empty.',
      );
    }
    if (registryVersion.trim().isEmpty) {
      throw ArgumentError.value(
        registryVersion,
        'registryVersion',
        'registryVersion must not be empty.',
      );
    }

    final seenCastIds = <String>{};
    var narratorCount = 0;
    for (final entry in entries) {
      if (!seenCastIds.add(entry.castId)) {
        throw ArgumentError.value(
          entries,
          'entries',
          'castId values must be unique within one CharacterCastRegistry.',
        );
      }
      if (entry.roleKind == CastEntryRoleKind.narrator) {
        narratorCount += 1;
      }
    }
    if (narratorCount != 1) {
      throw ArgumentError.value(
        entries,
        'entries',
        'CharacterCastRegistry must contain exactly one narrator entry.',
      );
    }

    return CharacterCastRegistry._(
      documentId: documentId,
      registryVersion: registryVersion,
      entries: List<CastEntry>.unmodifiable(entries),
    );
  }

  const CharacterCastRegistry._({
    required this.documentId,
    required this.registryVersion,
    required this.entries,
  });

  final String documentId;
  final String registryVersion;
  final List<CastEntry> entries;

  CastEntry get narratorEntry => entries.firstWhere(
    (entry) => entry.roleKind == CastEntryRoleKind.narrator,
  );

  Iterable<CastEntry> get characterEntries =>
      entries.where((entry) => entry.roleKind == CastEntryRoleKind.character);

  CastEntry? forCastId(String castId) {
    for (final entry in entries) {
      if (entry.castId == castId) {
        return entry;
      }
    }
    return null;
  }
}

class CastEntry {
  factory CastEntry({
    required String castId,
    required CastEntryRoleKind roleKind,
    required String displayLabel,
    required double confidence,
    required CastEntryProvenance provenance,
    List<String> observedAliases = const <String>[],
    List<String> attributionIds = const <String>[],
  }) {
    if (castId.trim().isEmpty) {
      throw ArgumentError.value(castId, 'castId', 'castId must not be empty.');
    }
    if (displayLabel.trim().isEmpty) {
      throw ArgumentError.value(
        displayLabel,
        'displayLabel',
        'displayLabel must not be empty.',
      );
    }
    if (confidence < 0.0 || confidence > 1.0) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'confidence must be between 0.0 and 1.0.',
      );
    }

    final normalizedAliases = observedAliases
        .map((alias) => alias.trim())
        .where((alias) => alias.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final normalizedAttributionIds = attributionIds
        .map((attributionId) => attributionId.trim())
        .where((attributionId) => attributionId.isNotEmpty)
        .toSet()
        .toList(growable: false);

    return CastEntry._(
      castId: castId,
      roleKind: roleKind,
      displayLabel: displayLabel.trim(),
      confidence: confidence,
      provenance: provenance,
      observedAliases: normalizedAliases,
      attributionIds: normalizedAttributionIds,
    );
  }

  const CastEntry._({
    required this.castId,
    required this.roleKind,
    required this.displayLabel,
    required this.confidence,
    required this.provenance,
    required this.observedAliases,
    required this.attributionIds,
  });

  final String castId;
  final CastEntryRoleKind roleKind;
  final String displayLabel;
  final double confidence;
  final CastEntryProvenance provenance;
  final List<String> observedAliases;
  final List<String> attributionIds;
}

CastEntryProvenance castEntryProvenanceForAttribution(
  DialogueAttributionProvenance provenance,
) {
  return switch (provenance) {
    DialogueAttributionProvenance.heuristicInference =>
      CastEntryProvenance.attributedDialogueInference,
    DialogueAttributionProvenance.explicitSourceMetadata =>
      CastEntryProvenance.sourceMetadata,
    DialogueAttributionProvenance.providerOutput =>
      CastEntryProvenance.providerOutput,
  };
}
