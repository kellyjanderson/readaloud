import 'pronunciation_artifact.dart';

class TtsArtifactSet {
  const TtsArtifactSet({
    required this.documentId,
    required this.sessionId,
    required this.engineId,
    required this.voiceId,
    required this.rate,
    this.selectedProfileId = 'en-us-core',
    required this.startSegmentId,
    required this.endSegmentId,
    required this.segments,
  });

  final String documentId;
  final String sessionId;
  final String engineId;
  final String voiceId;
  final double rate;
  final String selectedProfileId;
  final String startSegmentId;
  final String endSegmentId;
  final List<TtsArtifactSegment> segments;

  TtsArtifactSegment? segmentById(String segmentId) {
    for (final segment in segments) {
      if (segment.segmentId == segmentId) {
        return segment;
      }
    }
    return null;
  }
}

class TtsArtifactSegment {
  const TtsArtifactSegment({
    required this.segmentId,
    required this.speakText,
    required this.pronunciationArtifacts,
    this.boundaryIntents = const <RealizedBoundaryIntent>[],
    this.emphasisIntents = const <RealizedEmphasisIntent>[],
    this.diagnosticCodes = const <String>[],
  });

  final String segmentId;
  final String speakText;
  final List<RealizedPronunciationArtifact> pronunciationArtifacts;
  final List<RealizedBoundaryIntent> boundaryIntents;
  final List<RealizedEmphasisIntent> emphasisIntents;
  final List<String> diagnosticCodes;
}

class RealizedBoundaryIntent {
  const RealizedBoundaryIntent({
    required this.annotationId,
    required this.segmentId,
    required this.startWord,
    required this.endWord,
    required this.breakClass,
    required this.sourceKind,
    required this.engineTreatment,
    required this.confidence,
    this.diagnosticCodes = const <String>[],
  });

  final String annotationId;
  final String segmentId;
  final int startWord;
  final int endWord;
  final String breakClass;
  final String sourceKind;
  final String engineTreatment;
  final double confidence;
  final List<String> diagnosticCodes;
}

class RealizedEmphasisIntent {
  const RealizedEmphasisIntent({
    required this.annotationId,
    required this.segmentId,
    required this.startWord,
    required this.endWord,
    required this.confidence,
    required this.engineTreatment,
    this.diagnosticCodes = const <String>[],
  });

  final String annotationId;
  final String segmentId;
  final int startWord;
  final int endWord;
  final double confidence;
  final String engineTreatment;
  final List<String> diagnosticCodes;
}

class RealizedPronunciationArtifact {
  const RealizedPronunciationArtifact({
    required this.artifactId,
    required this.segmentId,
    required this.startWord,
    required this.endWord,
    required this.resolutionClass,
    required this.translationIntent,
    this.selectedRepresentation,
    this.diagnosticCodes = const <String>[],
  });

  final String artifactId;
  final String segmentId;
  final int startWord;
  final int endWord;
  final String resolutionClass;
  final PronunciationRepresentation? selectedRepresentation;
  final String translationIntent;
  final List<String> diagnosticCodes;

  String get spanKey => '$segmentId:$startWord:$endWord';
}
