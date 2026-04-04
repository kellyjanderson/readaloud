import 'speech_annotation.dart';
import 'speech_document.dart';
import 'tts_artifact.dart';
import 'cast_aware_speech_route.dart';

class ChunkPlannerInput {
  const ChunkPlannerInput({
    required this.speechDocument,
    required this.baseAnnotations,
    required this.ttsArtifactSet,
    required this.startSegmentId,
    required this.voiceId,
    required this.rate,
    required this.engineId,
    required this.engineVersion,
    this.castAwareSpeechRoutes,
  });

  final SpeechDocument speechDocument;
  final BaseSpeechAnnotationSet baseAnnotations;
  final TtsArtifactSet ttsArtifactSet;
  final String startSegmentId;
  final String voiceId;
  final double rate;
  final String engineId;
  final String engineVersion;
  final CastAwareSpeechRouteSet? castAwareSpeechRoutes;
}

class ChunkPlan {
  const ChunkPlan({required this.planId, required this.chunks});

  final String planId;
  final List<ChunkSpec> chunks;
}

class ChunkSpec {
  const ChunkSpec({
    required this.chunkId,
    required this.segmentIds,
    required this.speakText,
    required this.voiceId,
    required this.boundaryClass,
    required this.startSegmentIndex,
    required this.endSegmentIndex,
    required this.estimatedWordCount,
    required this.cacheKey,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.ttsSegments,
    this.routeId,
    this.castId,
    this.dialogueSpanId,
  });

  final String chunkId;
  final List<String> segmentIds;
  final String speakText;
  final String voiceId;
  final BreakClass boundaryClass;
  final int startSegmentIndex;
  final int endSegmentIndex;
  final int estimatedWordCount;
  final String cacheKey;
  final int startWordIndex;
  final int endWordIndex;
  final List<TtsArtifactSegment> ttsSegments;
  final String? routeId;
  final String? castId;
  final String? dialogueSpanId;
}
