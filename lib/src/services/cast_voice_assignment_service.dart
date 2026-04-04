import '../models/cast_voice_assignment.dart';
import '../models/character_cast_registry.dart';
import '../models/voice_profile.dart';

class CastVoiceAssignmentInput {
  const CastVoiceAssignmentInput({
    required this.characterCastRegistry,
    required this.availableVoices,
    required this.fallbackVoiceId,
    this.preferredNarratorVoiceId,
    this.storedAssignments = const <String, String>{},
    this.userOverrides = const <String, String>{},
  });

  final CharacterCastRegistry characterCastRegistry;
  final List<VoiceProfile> availableVoices;
  final String fallbackVoiceId;
  final String? preferredNarratorVoiceId;
  final Map<String, String> storedAssignments;
  final Map<String, String> userOverrides;
}

class CastVoiceAssignmentService {
  const CastVoiceAssignmentService();

  static const assignmentVersion = 'read-aloud-cast-voice-assignments-v1';

  CastVoiceAssignmentSet resolve(CastVoiceAssignmentInput input) {
    final sortedVoices = List<VoiceProfile>.from(input.availableVoices)
      ..sort(_compareVoices);
    final availableVoiceIds = sortedVoices.map((voice) => voice.id).toSet();

    final narratorAutomaticVoiceId =
        _validVoiceId(input.preferredNarratorVoiceId, availableVoiceIds) ??
        (sortedVoices.isNotEmpty ? sortedVoices.first.id : null);

    final characterVoicePool = _prioritizedCharacterVoices(
      sortedVoices,
      narratorAutomaticVoiceId,
    );
    final automaticAssignments = <String, String?>{
      input.characterCastRegistry.narratorEntry.castId:
          narratorAutomaticVoiceId,
    };

    final sortedCharacters =
        input.characterCastRegistry.characterEntries.toList(growable: false)
          ..sort((left, right) => left.castId.compareTo(right.castId));

    for (var index = 0; index < sortedCharacters.length; index += 1) {
      final character = sortedCharacters[index];
      final automaticVoiceId = characterVoicePool.isNotEmpty
          ? characterVoicePool[index % characterVoicePool.length].id
          : narratorAutomaticVoiceId;
      automaticAssignments[character.castId] = automaticVoiceId;
    }

    final assignments = <CastVoiceAssignment>[];
    for (final entry in input.characterCastRegistry.entries) {
      final automaticVoiceId = automaticAssignments[entry.castId];
      final storedVoiceId = _validVoiceId(
        input.storedAssignments[entry.castId],
        availableVoiceIds,
      );
      final userOverrideVoiceId = _validVoiceId(
        input.userOverrides[entry.castId],
        availableVoiceIds,
      );

      final effectiveVoiceId =
          userOverrideVoiceId ??
          storedVoiceId ??
          automaticVoiceId ??
          input.fallbackVoiceId;
      final decisionKind = switch ((
        userOverrideVoiceId,
        storedVoiceId,
        automaticVoiceId,
      )) {
        (String _, _, _) => VoiceAssignmentDecisionKind.userOverride,
        (null, String _, _) => VoiceAssignmentDecisionKind.storedDocumentChoice,
        (null, null, String _) => VoiceAssignmentDecisionKind.automatic,
        (null, null, null) => VoiceAssignmentDecisionKind.fallback,
      };

      assignments.add(
        CastVoiceAssignment(
          castId: entry.castId,
          effectiveVoiceId: effectiveVoiceId,
          decisionKind: decisionKind,
          automaticVoiceId: automaticVoiceId,
          storedVoiceId: storedVoiceId,
          userOverrideVoiceId: userOverrideVoiceId,
        ),
      );
    }

    return CastVoiceAssignmentSet(
      documentId: input.characterCastRegistry.documentId,
      assignmentVersion: assignmentVersion,
      assignments: assignments,
    );
  }

  String? _validVoiceId(String? voiceId, Set<String> availableVoiceIds) {
    if (voiceId == null || voiceId.isEmpty) {
      return null;
    }
    return availableVoiceIds.contains(voiceId) ? voiceId : null;
  }

  List<VoiceProfile> _prioritizedCharacterVoices(
    List<VoiceProfile> sortedVoices,
    String? narratorVoiceId,
  ) {
    final nonNarratorVoices = sortedVoices
        .where((voice) => voice.id != narratorVoiceId)
        .toList(growable: false);
    if (narratorVoiceId == null) {
      return nonNarratorVoices;
    }

    final narratorVoice = sortedVoices
        .where((voice) => voice.id == narratorVoiceId)
        .firstOrNull;
    final narratorGender = narratorVoice?.gender;
    if (narratorGender == null) {
      return nonNarratorVoices;
    }

    final contrasting = <VoiceProfile>[];
    final unknown = <VoiceProfile>[];
    final similar = <VoiceProfile>[];

    for (final voice in nonNarratorVoices) {
      final gender = voice.gender;
      if (gender == null || gender == VoiceGender.neutral) {
        unknown.add(voice);
      } else if (gender != narratorGender) {
        contrasting.add(voice);
      } else {
        similar.add(voice);
      }
    }

    return <VoiceProfile>[
      ...contrasting,
      ...unknown,
      ...similar,
    ];
  }

  int _compareVoices(VoiceProfile left, VoiceProfile right) {
    final qualityComparison = _qualityScore(
      right.qualityGrade,
    ).compareTo(_qualityScore(left.qualityGrade));
    if (qualityComparison != 0) {
      return qualityComparison;
    }
    final localeComparison = left.locale.compareTo(right.locale);
    if (localeComparison != 0) {
      return localeComparison;
    }
    return left.label.compareTo(right.label);
  }

  int _qualityScore(String? grade) {
    return switch (grade) {
      'A+' => 120,
      'A' => 110,
      'A-' => 100,
      'B+' => 90,
      'B' => 80,
      'B-' => 70,
      'C+' => 60,
      'C' => 50,
      'C-' => 40,
      'D+' => 30,
      'D' => 20,
      'D-' => 10,
      _ => 0,
    };
  }
}
