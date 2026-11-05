import 'character_cast_registry.dart';

enum VoiceSelectionMode { automatic, explicit }

/// Durable intent. A Reset has its own revision; absence is not a Reset.
class VoiceSelection {
  const VoiceSelection({
    this.mode = VoiceSelectionMode.automatic,
    this.voiceId,
    this.revision = 0,
    this.provenance = 'automatic',
  });
  final VoiceSelectionMode mode;
  final String? voiceId;
  final int revision;
  final String provenance;
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'voiceId': voiceId,
    'revision': revision,
    'provenance': provenance,
  };
  factory VoiceSelection.fromJson(Map<String, dynamic> json) {
    final value = VoiceSelection(
      mode: VoiceSelectionMode.values.byName(json['mode']),
      voiceId: json['voiceId'],
      revision: json['revision'],
      provenance: json['provenance'],
    );
    if (value.revision < 0 ||
        (value.mode == VoiceSelectionMode.explicit &&
            (value.voiceId == null || value.voiceId!.isEmpty)) ||
        (value.mode == VoiceSelectionMode.automatic && value.voiceId != null)) {
      throw const FormatException('Invalid character voice selection');
    }
    return value;
  }
}

/// Gender facts retain their evidence category; choosing a voice never creates
/// identity evidence. Presentation is stored separately with source scope.
class GenderEvidence {
  GenderEvidence({
    this.value = CharacterGenderIdentityLabel.unknown,
    this.conflict = false,
    List<CharacterIdentityEvidenceSpan> observations = const [],
  }) : observations = List.unmodifiable(observations);
  const GenderEvidence.empty()
    : value = CharacterGenderIdentityLabel.unknown,
      conflict = false,
      observations = const [];
  final CharacterGenderIdentityLabel value;
  final bool conflict;
  final List<CharacterIdentityEvidenceSpan> observations;
  Map<String, Object?> toJson() => {
    'value': value.name,
    'conflict': conflict,
    'observations': observations
        .map(
          (s) => {
            'segmentId': s.segmentId,
            'start': s.startUtf16,
            'end': s.endUtf16,
            'text': s.text,
            'source': s.source.name,
            'gender': s.genderIdentityLabel?.name,
          },
        )
        .toList(),
  };
  factory GenderEvidence.fromJson(Map<String, dynamic> json) => GenderEvidence(
    value: CharacterGenderIdentityLabel.values.byName(json['value']),
    conflict: json['conflict'],
    observations: List.unmodifiable(
      (json['observations'] as List).map(
        (s) => CharacterIdentityEvidenceSpan(
          segmentId: s['segmentId'],
          startUtf16: s['start'],
          endUtf16: s['end'],
          text: s['text'],
          source: CharacterGenderEvidenceSource.values.byName(s['source']),
          genderIdentityLabel: s['gender'] == null
              ? null
              : CharacterGenderIdentityLabel.values.byName(s['gender']),
        ),
      ),
    ),
  );

  GenderEvidence merge(GenderEvidence newer) {
    final observationsById = {
      for (final s in [...observations, ...newer.observations])
        '${s.segmentId}:${s.startUtf16}:${s.endUtf16}:${s.source.name}': s,
    };
    return GenderEvidence(
      value: newer.value == CharacterGenderIdentityLabel.unknown
          ? value
          : newer.value,
      conflict:
          conflict ||
          newer.conflict ||
          (value != CharacterGenderIdentityLabel.unknown &&
              newer.value != CharacterGenderIdentityLabel.unknown &&
              value != newer.value),
      observations: List.unmodifiable(observationsById.values),
    );
  }
}

class ScopedGenderEvidence {
  ScopedGenderEvidence({
    required this.sourceRevision,
    required List<String> segmentIds,
    required this.evidence,
  }) : segmentIds = List.unmodifiable(segmentIds);
  final String sourceRevision;
  final List<String> segmentIds;
  final GenderEvidence evidence;
  Map<String, Object?> toJson() => {
    'sourceRevision': sourceRevision,
    'segmentIds': segmentIds,
    'evidence': evidence.toJson(),
  };
  factory ScopedGenderEvidence.fromJson(Map<String, dynamic> json) =>
      ScopedGenderEvidence(
        sourceRevision: json['sourceRevision'],
        segmentIds: List<String>.unmodifiable(json['segmentIds']),
        evidence: GenderEvidence.fromJson(
          Map<String, dynamic>.from(json['evidence']),
        ),
      );
}

/// References to canonical defaults/adjustments, never a model's speaker slot,
/// tensor, temporary utterance emotion or silently inherited model instruction.
class CharacterSpeechProfile {
  CharacterSpeechProfile({List<String> directionReferences = const []})
    : directionReferences = List.unmodifiable(directionReferences);
  const CharacterSpeechProfile.empty() : directionReferences = const [];
  final List<String> directionReferences;
}

abstract interface class Character {
  String get workId;
  String get id;
  int get revision;
  String get displayName;
  List<String> get aliases;
  GenderEvidence get explicitGender;
  GenderEvidence get implicitGender;
  List<ScopedGenderEvidence> get presentedGender;
  CharacterIdentityProfile? get attributes;
  VoiceSelection get selectedVoice;
  CharacterSpeechProfile get speechProfile;
}

/// Persisted aggregate fields embedded in CastEntry, not a parallel cast store.
class CharacterState {
  CharacterState({
    this.workId = '',
    this.revision = 0,
    this.selectedVoice = const VoiceSelection(),
    this.explicitGender = const GenderEvidence.empty(),
    this.implicitGender = const GenderEvidence.empty(),
    List<ScopedGenderEvidence> presentedGender = const [],
    this.speechProfile = const CharacterSpeechProfile.empty(),
    Map<String, String> automaticVoices = const {},
    List<VoiceSelection> selectionConflicts = const [],
  }) : presentedGender = List.unmodifiable(presentedGender),
       automaticVoices = Map.unmodifiable(automaticVoices),
       selectionConflicts = List.unmodifiable(selectionConflicts);
  final String workId;
  final int revision;
  final VoiceSelection selectedVoice;
  final GenderEvidence explicitGender;
  final GenderEvidence implicitGender;
  final List<ScopedGenderEvidence> presentedGender;
  final CharacterSpeechProfile speechProfile;

  /// Derived resolutions, scoped by engine identity. Only the aggregate owner
  /// updates these; they never masquerade as an explicit voice selection.
  final Map<String, String> automaticVoices;
  final List<VoiceSelection> selectionConflicts;

  factory CharacterState.fromProfile(CharacterIdentityProfile? profile) {
    if (profile == null) return CharacterState();
    bool explicit(CharacterGenderEvidenceSource source) =>
        source == CharacterGenderEvidenceSource.explicitIdentity ||
        source == CharacterGenderEvidenceSource.explicitApposition;
    GenderEvidence evidence(bool isExplicit) {
      final spans = profile.evidenceSpans
          .where((s) => explicit(s.source) == isExplicit)
          .toList();
      final values = spans
          .map((s) => s.genderIdentityLabel)
          .whereType<CharacterGenderIdentityLabel>()
          .toSet();
      final resolved = explicit(profile.genderSource) == isExplicit
          ? profile.genderIdentityLabel
          : (values.length == 1
                ? values.single
                : CharacterGenderIdentityLabel.unknown);
      return GenderEvidence(
        value: resolved,
        conflict:
            values.length > 1 || (profile.conflictFlag && spans.isNotEmpty),
        observations: List.unmodifiable(spans),
      );
    }

    return CharacterState(
      explicitGender: evidence(true),
      implicitGender: evidence(false),
    );
  }
  CharacterState copyWith({
    String? workId,
    int? revision,
    VoiceSelection? selectedVoice,
    GenderEvidence? explicitGender,
    GenderEvidence? implicitGender,
    Map<String, String>? automaticVoices,
    List<VoiceSelection>? selectionConflicts,
    List<ScopedGenderEvidence>? presentedGender,
    CharacterSpeechProfile? speechProfile,
  }) => CharacterState(
    workId: workId ?? this.workId,
    revision: revision ?? this.revision,
    selectedVoice: selectedVoice ?? this.selectedVoice,
    explicitGender: explicitGender ?? this.explicitGender,
    implicitGender: implicitGender ?? this.implicitGender,
    presentedGender: presentedGender ?? this.presentedGender,
    speechProfile: speechProfile ?? this.speechProfile,
    automaticVoices: Map.unmodifiable(automaticVoices ?? this.automaticVoices),
    selectionConflicts: List.unmodifiable(
      selectionConflicts ?? this.selectionConflicts,
    ),
  );
  Map<String, Object?> toJson() => {
    'schema': 1,
    'workId': workId,
    'revision': revision,
    'selectedVoice': selectedVoice.toJson(),
    'explicitGender': explicitGender.toJson(),
    'implicitGender': implicitGender.toJson(),
    'presentedGender': presentedGender.map((s) => s.toJson()).toList(),
    'directions': speechProfile.directionReferences,
    'automaticVoices': automaticVoices,
    'selectionConflicts': selectionConflicts.map((s) => s.toJson()).toList(),
  };
  factory CharacterState.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw const FormatException('Unsupported character schema');
    }
    if (json['workId'] is! String ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0) {
      throw const FormatException('Invalid character identity/revision');
    }
    return CharacterState(
      workId: json['workId'],
      revision: json['revision'],
      selectedVoice: VoiceSelection.fromJson(
        Map<String, dynamic>.from(json['selectedVoice']),
      ),
      explicitGender: GenderEvidence.fromJson(
        Map<String, dynamic>.from(json['explicitGender']),
      ),
      implicitGender: GenderEvidence.fromJson(
        Map<String, dynamic>.from(json['implicitGender']),
      ),
      presentedGender: List.unmodifiable(
        (json['presentedGender'] as List).map(
          (s) => ScopedGenderEvidence.fromJson(Map<String, dynamic>.from(s)),
        ),
      ),
      speechProfile: CharacterSpeechProfile(
        directionReferences: List<String>.unmodifiable(json['directions']),
      ),
      automaticVoices: Map<String, String>.unmodifiable(
        json['automaticVoices'],
      ),
      selectionConflicts: List.unmodifiable(
        (json['selectionConflicts'] as List).map(
          (s) => VoiceSelection.fromJson(Map<String, dynamic>.from(s)),
        ),
      ),
    );
  }
}

/// Data-only provider handoff. Analysis never carries an authorized selection
/// mutation. The consumer checks source/revision and provider sequence first.
class CharacterAnalysisDelta {
  const CharacterAnalysisDelta({
    required this.workId,
    required this.sourceRevision,
    required this.analysisRevision,
    required this.sequence,
    required this.providerId,
    required this.registry,
  });
  final String workId, sourceRevision, providerId;
  final int analysisRevision, sequence;
  final CharacterCastRegistry registry;
}
