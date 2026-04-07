import '../models/cast_aware_speech_route.dart';
import '../models/cast_voice_assignment.dart';
import '../models/document_voice_attribution.dart';

class CastAwareSpeechRouteInput {
  const CastAwareSpeechRouteInput({
    required this.documentVoiceAttribution,
    required this.castVoiceAssignments,
  });

  final DocumentVoiceAttributionSet documentVoiceAttribution;
  final CastVoiceAssignmentSet castVoiceAssignments;
}

class CastAwareSpeechRouteService {
  const CastAwareSpeechRouteService();

  static const routingVersion = 'read-aloud-cast-aware-routes-v1';

  CastAwareSpeechRouteSet build(CastAwareSpeechRouteInput input) {
    final narratorAssignment = input.castVoiceAssignments.assignments.firstWhere(
      (assignment) => assignment.castId == 'cast_narrator',
      orElse: () => throw StateError(
        'Cast-aware routing requires a narrator voice assignment.',
      ),
    );
    final narratorVoiceId = narratorAssignment.effectiveVoiceId;
    if (narratorVoiceId.isEmpty) {
      throw StateError(
        'Cast-aware routing requires a narrator voice assignment.',
      );
    }
    final routeSegments = input.documentVoiceAttribution.ranges
        .map(
          (range) => _RouteSegment(
            segmentIds: range.segmentIds,
            startWordIndex: range.startWordIndex,
            endWordIndex: range.endWordIndex,
            castId: range.castId,
            voiceId: input.castVoiceAssignments
                    .forCastId(range.castId)
                    ?.effectiveVoiceId ??
                narratorVoiceId,
            dialogueSpanId: range.dialogueSpanId,
          ),
        )
        .toList(growable: false);

    final mergedRanges = <CastAwareSpeechRange>[];
    _RouteSegment? active;
    for (final segment in routeSegments) {
      if (active == null) {
        active = segment;
        continue;
      }
      if (_canMerge(active, segment)) {
        active = active.copyWith(
          segmentIds: <String>[...active.segmentIds, ...segment.segmentIds],
          endWordIndex: segment.endWordIndex,
          endSegmentId: segment.endSegmentId,
        );
        continue;
      }
      mergedRanges.add(_toRoute(active));
      active = segment;
    }
    if (active != null) {
      mergedRanges.add(_toRoute(active));
    }

    return CastAwareSpeechRouteSet(
      documentId: input.documentVoiceAttribution.documentId,
      routingVersion: routingVersion,
      ranges: mergedRanges,
    );
  }

  bool _canMerge(_RouteSegment left, _RouteSegment right) {
    return left.castId == right.castId &&
        left.voiceId == right.voiceId &&
        left.endWordIndex == right.startWordIndex &&
        left.dialogueSpanId == right.dialogueSpanId;
  }

  CastAwareSpeechRange _toRoute(_RouteSegment routeSegment) {
    return CastAwareSpeechRange(
      routeId: 'route_${routeSegment.segmentIds.first}',
      segmentIds: routeSegment.segmentIds,
      startSegmentId: routeSegment.segmentIds.first,
      endSegmentId: routeSegment.endSegmentId,
      startWordIndex: routeSegment.startWordIndex,
      endWordIndex: routeSegment.endWordIndex,
      castId: routeSegment.castId,
      voiceId: routeSegment.voiceId,
      dialogueSpanId: routeSegment.dialogueSpanId,
    );
  }
}

class _RouteSegment {
  _RouteSegment({
    required List<String> segmentIds,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.castId,
    required this.voiceId,
    required this.dialogueSpanId,
  }) : segmentIds = List<String>.unmodifiable(segmentIds),
       segmentId = segmentIds.first,
       endSegmentId = segmentIds.last;

  _RouteSegment._({
    required this.segmentIds,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.castId,
    required this.voiceId,
    required this.dialogueSpanId,
    required this.endSegmentId,
  }) : segmentId = segmentIds.first;

  final String segmentId;
  final List<String> segmentIds;
  final String endSegmentId;
  final int startWordIndex;
  final int endWordIndex;
  final String castId;
  final String voiceId;
  final String? dialogueSpanId;

  _RouteSegment copyWith({
    List<String>? segmentIds,
    int? endWordIndex,
    String? endSegmentId,
  }) {
    return _RouteSegment._(
      segmentIds: segmentIds ?? this.segmentIds,
      startWordIndex: startWordIndex,
      endWordIndex: endWordIndex ?? this.endWordIndex,
      castId: castId,
      voiceId: voiceId,
      dialogueSpanId: dialogueSpanId,
      endSegmentId: endSegmentId ?? this.endSegmentId,
    );
  }
}
