import 'speech_annotation.dart';
import 'speech_document.dart';
import 'tts_artifact.dart';
import 'cast_aware_speech_route.dart';

/// Chapter analysis can refine the boundary before a source segment.
enum FishSceneBoundary {
  continuation,
  sentence,
  paragraph,
  chapter,
  sourceRange,
}

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
    this.fishSceneBoundaries = const {},
    this.maxChunks,
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
  final Map<String, FishSceneBoundary> fishSceneBoundaries;
  final int? maxChunks;
}

class ChunkPlan {
  const ChunkPlan({
    required this.planId,
    required this.chunks,
    this.nextSegmentId,
  });

  final String? nextSegmentId;

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
    this.sceneTurns = const <ChunkSpec>[],
    this.segmentWordRanges = const <ChunkSegmentWordRange>[],
    this.routeId,
    this.castId,
    this.dialogueSpanId,
  });

  final List<ChunkSpec> sceneTurns;
  final List<ChunkSegmentWordRange> segmentWordRanges;
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

/// Half-open word interval in the planning document, for a partial segment.
class ChunkSegmentWordRange {
  const ChunkSegmentWordRange(this.segmentId, this.startWord, this.endWord);

  final String segmentId;
  final int startWord;
  final int endWord;
}
