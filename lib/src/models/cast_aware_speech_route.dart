class CastAwareSpeechRouteSet {
  factory CastAwareSpeechRouteSet({
    required String documentId,
    required String routingVersion,
    required List<CastAwareSpeechRange> ranges,
  }) {
    if (documentId.trim().isEmpty) {
      throw ArgumentError.value(
        documentId,
        'documentId',
        'documentId must not be empty.',
      );
    }
    if (routingVersion.trim().isEmpty) {
      throw ArgumentError.value(
        routingVersion,
        'routingVersion',
        'routingVersion must not be empty.',
      );
    }

    final seenRouteIds = <String>{};
    for (final range in ranges) {
      if (!seenRouteIds.add(range.routeId)) {
        throw ArgumentError.value(
          ranges,
          'ranges',
          'routeId values must be unique within one CastAwareSpeechRouteSet.',
        );
      }
    }

    return CastAwareSpeechRouteSet._(
      documentId: documentId,
      routingVersion: routingVersion,
      ranges: List<CastAwareSpeechRange>.unmodifiable(ranges),
    );
  }

  const CastAwareSpeechRouteSet._({
    required this.documentId,
    required this.routingVersion,
    required this.ranges,
  });

  final String documentId;
  final String routingVersion;
  final List<CastAwareSpeechRange> ranges;
}

class CastAwareSpeechRange {
  factory CastAwareSpeechRange({
    required String routeId,
    required List<String> segmentIds,
    required String startSegmentId,
    required String endSegmentId,
    required int startWordIndex,
    required int endWordIndex,
    required String castId,
    required String voiceId,
    String? dialogueSpanId,
  }) {
    if (routeId.trim().isEmpty) {
      throw ArgumentError.value(
        routeId,
        'routeId',
        'routeId must not be empty.',
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
    if (castId.trim().isEmpty || voiceId.trim().isEmpty) {
      throw ArgumentError.value(
        <String>[castId, voiceId],
        'castId/voiceId',
        'castId and voiceId must not be empty.',
      );
    }

    return CastAwareSpeechRange._(
      routeId: routeId,
      segmentIds: List<String>.unmodifiable(segmentIds),
      startSegmentId: startSegmentId,
      endSegmentId: endSegmentId,
      startWordIndex: startWordIndex,
      endWordIndex: endWordIndex,
      castId: castId,
      voiceId: voiceId,
      dialogueSpanId: dialogueSpanId?.trim(),
    );
  }

  const CastAwareSpeechRange._({
    required this.routeId,
    required this.segmentIds,
    required this.startSegmentId,
    required this.endSegmentId,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.castId,
    required this.voiceId,
    required this.dialogueSpanId,
  });

  final String routeId;
  final List<String> segmentIds;
  final String startSegmentId;
  final String endSegmentId;
  final int startWordIndex;
  final int endWordIndex;
  final String castId;
  final String voiceId;
  final String? dialogueSpanId;
}
