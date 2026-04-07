enum DocumentVoiceAttributionKind {
  narration,
  attributedDialogue,
  unattributedDialogue,
}

class DocumentVoiceAttributionSet {
  factory DocumentVoiceAttributionSet({
    required String documentId,
    required String attributionVersion,
    required List<DocumentVoiceAttributionRange> ranges,
  }) {
    if (documentId.trim().isEmpty) {
      throw ArgumentError.value(
        documentId,
        'documentId',
        'documentId must not be empty.',
      );
    }
    if (attributionVersion.trim().isEmpty) {
      throw ArgumentError.value(
        attributionVersion,
        'attributionVersion',
        'attributionVersion must not be empty.',
      );
    }

    final seenRangeIds = <String>{};
    for (final range in ranges) {
      if (!seenRangeIds.add(range.rangeId)) {
        throw ArgumentError.value(
          ranges,
          'ranges',
          'rangeId values must be unique within one DocumentVoiceAttributionSet.',
        );
      }
    }

    return DocumentVoiceAttributionSet._(
      documentId: documentId,
      attributionVersion: attributionVersion,
      ranges: List<DocumentVoiceAttributionRange>.unmodifiable(ranges),
    );
  }

  const DocumentVoiceAttributionSet._({
    required this.documentId,
    required this.attributionVersion,
    required this.ranges,
  });

  final String documentId;
  final String attributionVersion;
  final List<DocumentVoiceAttributionRange> ranges;
}

class DocumentVoiceAttributionRange {
  factory DocumentVoiceAttributionRange({
    required String rangeId,
    required List<String> segmentIds,
    required String startSegmentId,
    required String endSegmentId,
    required int startWordIndex,
    required int endWordIndex,
    required String castId,
    required DocumentVoiceAttributionKind kind,
    String? dialogueSpanId,
  }) {
    if (rangeId.trim().isEmpty) {
      throw ArgumentError.value(
        rangeId,
        'rangeId',
        'rangeId must not be empty.',
      );
    }
    if (segmentIds.isEmpty) {
      throw ArgumentError.value(
        segmentIds,
        'segmentIds',
        'segmentIds must not be empty.',
      );
    }
    if (startSegmentId.trim().isEmpty || endSegmentId.trim().isEmpty) {
      throw ArgumentError.value(
        <String>[startSegmentId, endSegmentId],
        'startSegmentId/endSegmentId',
        'Segment ids must not be empty.',
      );
    }
    if (startWordIndex < 0 || endWordIndex < startWordIndex) {
      throw ArgumentError.value(
        <int>[startWordIndex, endWordIndex],
        'startWordIndex/endWordIndex',
        'Word bounds must be non-negative and ordered.',
      );
    }
    if (castId.trim().isEmpty) {
      throw ArgumentError.value(castId, 'castId', 'castId must not be empty.');
    }

    final normalizedDialogueSpanId = dialogueSpanId?.trim();
    if (kind == DocumentVoiceAttributionKind.narration &&
        normalizedDialogueSpanId != null &&
        normalizedDialogueSpanId.isNotEmpty) {
      throw ArgumentError.value(
        dialogueSpanId,
        'dialogueSpanId',
        'Narration ranges must not carry a dialogue span id.',
      );
    }
    if (kind != DocumentVoiceAttributionKind.narration &&
        (normalizedDialogueSpanId == null || normalizedDialogueSpanId.isEmpty)) {
      throw ArgumentError.value(
        dialogueSpanId,
        'dialogueSpanId',
        'Dialogue attribution ranges must carry a dialogue span id.',
      );
    }

    return DocumentVoiceAttributionRange._(
      rangeId: rangeId,
      segmentIds: List<String>.unmodifiable(segmentIds),
      startSegmentId: startSegmentId,
      endSegmentId: endSegmentId,
      startWordIndex: startWordIndex,
      endWordIndex: endWordIndex,
      castId: castId,
      kind: kind,
      dialogueSpanId: normalizedDialogueSpanId,
    );
  }

  const DocumentVoiceAttributionRange._({
    required this.rangeId,
    required this.segmentIds,
    required this.startSegmentId,
    required this.endSegmentId,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.castId,
    required this.kind,
    required this.dialogueSpanId,
  });

  final String rangeId;
  final List<String> segmentIds;
  final String startSegmentId;
  final String endSegmentId;
  final int startWordIndex;
  final int endWordIndex;
  final String castId;
  final DocumentVoiceAttributionKind kind;
  final String? dialogueSpanId;
}
