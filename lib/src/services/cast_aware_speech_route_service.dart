import '../models/cast_aware_speech_route.dart';
import '../models/cast_voice_assignment.dart';
import '../models/character_cast_registry.dart';
import '../models/dialogue_attribution.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';

class CastAwareSpeechRouteInput {
  const CastAwareSpeechRouteInput({
    required this.speechDocument,
    required this.baseAnnotations,
    required this.dialogueAttributions,
    required this.characterCastRegistry,
    required this.castVoiceAssignments,
  });

  final SpeechDocument speechDocument;
  final BaseSpeechAnnotationSet baseAnnotations;
  final DialogueAttributionSet dialogueAttributions;
  final CharacterCastRegistry characterCastRegistry;
  final CastVoiceAssignmentSet castVoiceAssignments;
}

class CastAwareSpeechRouteService {
  const CastAwareSpeechRouteService();

  static const routingVersion = 'read-aloud-cast-aware-routes-v1';

  CastAwareSpeechRouteSet build(CastAwareSpeechRouteInput input) {
    final narratorCastId = input.characterCastRegistry.narratorEntry.castId;
    final narratorVoiceId = input.castVoiceAssignments
        .forCastId(narratorCastId)
        ?.effectiveVoiceId;
    if (narratorVoiceId == null || narratorVoiceId.isEmpty) {
      throw StateError(
        'Cast-aware routing requires a narrator voice assignment.',
      );
    }

    final castIdByAttributionId = <String, String>{};
    for (final entry in input.characterCastRegistry.characterEntries) {
      for (final attributionId in entry.attributionIds) {
        castIdByAttributionId[attributionId] = entry.castId;
      }
    }

    final routeSegments = <_RouteSegment>[];
    var runningWordIndex = 0;
    for (final segment in input.speechDocument.segments) {
      final dialogueAnnotation = input.baseAnnotations
          .forSegment(segment.segmentId)
          .where(
            (annotation) =>
                annotation.kind == SpeechAnnotationKind.dialogueSpan,
          )
          .cast<SpeechAnnotation?>()
          .firstWhere((annotation) => annotation != null, orElse: () => null);
      final dialogueSpanId = dialogueAnnotation?.dialogueSpanId;
      final attribution = dialogueSpanId == null
          ? null
          : input.dialogueAttributions.forDialogueSpan(dialogueSpanId);

      final castId = switch (attribution?.resolution) {
        DialogueAttributionResolution.attributedSpeaker =>
          castIdByAttributionId[attribution!.attributionId] ?? narratorCastId,
        _ => narratorCastId,
      };
      final voiceId =
          input.castVoiceAssignments.forCastId(castId)?.effectiveVoiceId ??
          narratorVoiceId;
      routeSegments.add(
        _RouteSegment(
          segmentId: segment.segmentId,
          startWordIndex: runningWordIndex,
          endWordIndex: runningWordIndex + segment.wordCount,
          castId: castId,
          voiceId: voiceId,
          dialogueSpanId: dialogueSpanId,
        ),
      );
      runningWordIndex += segment.wordCount;
    }

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
      documentId: input.speechDocument.documentId,
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
    required this.segmentId,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.castId,
    required this.voiceId,
    required this.dialogueSpanId,
  }) : segmentIds = <String>[segmentId],
       endSegmentId = segmentId;

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
