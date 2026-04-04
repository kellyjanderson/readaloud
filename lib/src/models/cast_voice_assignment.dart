enum VoiceAssignmentDecisionKind {
  automatic,
  storedDocumentChoice,
  userOverride,
  fallback,
}

class CastVoiceAssignmentSet {
  factory CastVoiceAssignmentSet({
    required String documentId,
    required String assignmentVersion,
    required List<CastVoiceAssignment> assignments,
  }) {
    if (documentId.trim().isEmpty) {
      throw ArgumentError.value(
        documentId,
        'documentId',
        'documentId must not be empty.',
      );
    }
    if (assignmentVersion.trim().isEmpty) {
      throw ArgumentError.value(
        assignmentVersion,
        'assignmentVersion',
        'assignmentVersion must not be empty.',
      );
    }

    final seenCastIds = <String>{};
    for (final assignment in assignments) {
      if (!seenCastIds.add(assignment.castId)) {
        throw ArgumentError.value(
          assignments,
          'assignments',
          'castId values must be unique within one CastVoiceAssignmentSet.',
        );
      }
    }

    return CastVoiceAssignmentSet._(
      documentId: documentId,
      assignmentVersion: assignmentVersion,
      assignments: List<CastVoiceAssignment>.unmodifiable(assignments),
    );
  }

  const CastVoiceAssignmentSet._({
    required this.documentId,
    required this.assignmentVersion,
    required this.assignments,
  });

  final String documentId;
  final String assignmentVersion;
  final List<CastVoiceAssignment> assignments;

  CastVoiceAssignment? forCastId(String castId) {
    for (final assignment in assignments) {
      if (assignment.castId == castId) {
        return assignment;
      }
    }
    return null;
  }
}

class CastVoiceAssignment {
  factory CastVoiceAssignment({
    required String castId,
    required String effectiveVoiceId,
    required VoiceAssignmentDecisionKind decisionKind,
    String? automaticVoiceId,
    String? storedVoiceId,
    String? userOverrideVoiceId,
  }) {
    if (castId.trim().isEmpty) {
      throw ArgumentError.value(castId, 'castId', 'castId must not be empty.');
    }
    if (effectiveVoiceId.trim().isEmpty) {
      throw ArgumentError.value(
        effectiveVoiceId,
        'effectiveVoiceId',
        'effectiveVoiceId must not be empty.',
      );
    }

    return CastVoiceAssignment._(
      castId: castId,
      effectiveVoiceId: effectiveVoiceId,
      decisionKind: decisionKind,
      automaticVoiceId: automaticVoiceId?.trim(),
      storedVoiceId: storedVoiceId?.trim(),
      userOverrideVoiceId: userOverrideVoiceId?.trim(),
    );
  }

  const CastVoiceAssignment._({
    required this.castId,
    required this.effectiveVoiceId,
    required this.decisionKind,
    required this.automaticVoiceId,
    required this.storedVoiceId,
    required this.userOverrideVoiceId,
  });

  final String castId;
  final String effectiveVoiceId;
  final VoiceAssignmentDecisionKind decisionKind;
  final String? automaticVoiceId;
  final String? storedVoiceId;
  final String? userOverrideVoiceId;
}
