import 'dialogue_attribution.dart';
import 'voice_profile.dart';

enum CastEntryRoleKind { narrator, character }

enum CastEntryProvenance {
  syntheticNarrator,
  attributedDialogueInference,
  sourceMetadata,
  providerOutput,
}

enum CharacterGenderIdentityLabel {
  male,
  female,
  cisMale,
  cisFemale,
  transgender,
  transMale,
  transFemale,
  nonbinary,
  genderqueer,
  unknown,
}

enum CharacterGenderEvidenceSource {
  explicitIdentity,
  explicitApposition,
  descriptor,
  pronoun,
  unknown,
}

class CharacterPronounProfile {
  factory CharacterPronounProfile({
    Map<String, int> counts = const <String, int>{},
  }) {
    final normalizedCounts = <String, int>{};
    for (final entry in counts.entries) {
      final normalizedPronoun = entry.key.trim().toLowerCase();
      if (normalizedPronoun.isEmpty) {
        continue;
      }
      if (entry.value < 0) {
        throw ArgumentError.value(
          entry.value,
          'counts',
          'Pronoun counts must not be negative.',
        );
      }
      normalizedCounts[normalizedPronoun] = entry.value;
    }

    return CharacterPronounProfile._(
      counts: Map<String, int>.unmodifiable(normalizedCounts),
    );
  }

  const CharacterPronounProfile._({required this.counts});

  const CharacterPronounProfile.empty() : counts = const <String, int>{};

  final Map<String, int> counts;

  int countFor(String pronoun) => counts[pronoun.trim().toLowerCase()] ?? 0;

  bool get hasEvidence => counts.values.any((count) => count > 0);
}

class CharacterIdentityEvidenceSpan {
  factory CharacterIdentityEvidenceSpan({
    required String segmentId,
    required int startUtf16,
    required int endUtf16,
    required String text,
  }) {
    if (segmentId.trim().isEmpty) {
      throw ArgumentError.value(
        segmentId,
        'segmentId',
        'segmentId must not be empty.',
      );
    }
    if (startUtf16 < 0 || endUtf16 < startUtf16) {
      throw ArgumentError.value(
        '$startUtf16..$endUtf16',
        'startUtf16/endUtf16',
        'Identity evidence spans must be non-negative and ordered.',
      );
    }
    if (text.isEmpty) {
      throw ArgumentError.value(
        text,
        'text',
        'Identity evidence span text must not be empty.',
      );
    }
    return CharacterIdentityEvidenceSpan._(
      segmentId: segmentId.trim(),
      startUtf16: startUtf16,
      endUtf16: endUtf16,
      text: text,
    );
  }

  const CharacterIdentityEvidenceSpan._({
    required this.segmentId,
    required this.startUtf16,
    required this.endUtf16,
    required this.text,
  });

  final String segmentId;
  final int startUtf16;
  final int endUtf16;
  final String text;
}

class CharacterIdentityProfile {
  factory CharacterIdentityProfile({
    required CharacterGenderIdentityLabel genderIdentityLabel,
    required double genderConfidence,
    required CharacterGenderEvidenceSource genderSource,
    CharacterPronounProfile pronounProfile =
        const CharacterPronounProfile.empty(),
    List<CharacterIdentityEvidenceSpan> evidenceSpans =
        const <CharacterIdentityEvidenceSpan>[],
    bool conflictFlag = false,
  }) {
    if (genderConfidence < 0.0 || genderConfidence > 1.0) {
      throw ArgumentError.value(
        genderConfidence,
        'genderConfidence',
        'genderConfidence must be between 0.0 and 1.0.',
      );
    }
    return CharacterIdentityProfile._(
      genderIdentityLabel: genderIdentityLabel,
      genderConfidence: genderConfidence,
      genderSource: genderSource,
      pronounProfile: pronounProfile,
      evidenceSpans: List<CharacterIdentityEvidenceSpan>.unmodifiable(
        evidenceSpans,
      ),
      conflictFlag: conflictFlag,
    );
  }

  const CharacterIdentityProfile._({
    required this.genderIdentityLabel,
    required this.genderConfidence,
    required this.genderSource,
    required this.pronounProfile,
    required this.evidenceSpans,
    required this.conflictFlag,
  });

  const CharacterIdentityProfile.unknown()
    : genderIdentityLabel = CharacterGenderIdentityLabel.unknown,
      genderConfidence = 0.0,
      genderSource = CharacterGenderEvidenceSource.unknown,
      pronounProfile = const CharacterPronounProfile.empty(),
      evidenceSpans = const <CharacterIdentityEvidenceSpan>[],
      conflictFlag = false;

  final CharacterGenderIdentityLabel genderIdentityLabel;
  final double genderConfidence;
  final CharacterGenderEvidenceSource genderSource;
  final CharacterPronounProfile pronounProfile;
  final List<CharacterIdentityEvidenceSpan> evidenceSpans;
  final bool conflictFlag;

  VoiceGender? get preferredVoiceGender {
    return switch (genderIdentityLabel) {
      CharacterGenderIdentityLabel.male ||
      CharacterGenderIdentityLabel.cisMale ||
      CharacterGenderIdentityLabel.transMale => VoiceGender.male,
      CharacterGenderIdentityLabel.female ||
      CharacterGenderIdentityLabel.cisFemale ||
      CharacterGenderIdentityLabel.transFemale => VoiceGender.female,
      _ => null,
    };
  }
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
    CharacterIdentityProfile? identityProfile,
    VoiceGender? inferredGender,
    double? inferredGenderConfidence,
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
    if (inferredGenderConfidence != null &&
        (inferredGenderConfidence < 0.0 || inferredGenderConfidence > 1.0)) {
      throw ArgumentError.value(
        inferredGenderConfidence,
        'inferredGenderConfidence',
        'inferredGenderConfidence must be between 0.0 and 1.0.',
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
    final resolvedIdentityProfile =
        identityProfile ??
        _legacyIdentityProfile(
          inferredGender: inferredGender,
          inferredGenderConfidence: inferredGenderConfidence,
        );

    return CastEntry._(
      castId: castId,
      roleKind: roleKind,
      displayLabel: displayLabel.trim(),
      confidence: confidence,
      provenance: provenance,
      observedAliases: normalizedAliases,
      attributionIds: normalizedAttributionIds,
      identityProfile: resolvedIdentityProfile,
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
    required this.identityProfile,
  });

  final String castId;
  final CastEntryRoleKind roleKind;
  final String displayLabel;
  final double confidence;
  final CastEntryProvenance provenance;
  final List<String> observedAliases;
  final List<String> attributionIds;
  final CharacterIdentityProfile? identityProfile;

  VoiceGender? get inferredGender => identityProfile?.preferredVoiceGender;

  double? get inferredGenderConfidence =>
      inferredGender == null ? null : identityProfile?.genderConfidence;

  static CharacterIdentityProfile? _legacyIdentityProfile({
    required VoiceGender? inferredGender,
    required double? inferredGenderConfidence,
  }) {
    if (inferredGender == null) {
      return null;
    }
    return CharacterIdentityProfile(
      genderIdentityLabel: switch (inferredGender) {
        VoiceGender.male => CharacterGenderIdentityLabel.male,
        VoiceGender.female => CharacterGenderIdentityLabel.female,
        VoiceGender.neutral => CharacterGenderIdentityLabel.unknown,
      },
      genderConfidence: inferredGenderConfidence ?? 0.5,
      genderSource: CharacterGenderEvidenceSource.unknown,
    );
  }
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
