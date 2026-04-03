enum PronunciationArtifactClass {
  resolvedLexicalCase,
  contextSensitiveCase,
  unresolvedCase,
}

enum PronunciationArtifactSource {
  appLexicon,
  sourceMetadata,
  ruleBasedInference,
  userOverride,
  fallbackUnresolved,
}

class BasePronunciationArtifactSet {
  const BasePronunciationArtifactSet({
    required this.documentId,
    required this.artifactVersion,
    required this.normalizationVersion,
    required this.pronunciationProfileId,
    required this.artifacts,
  });

  final String documentId;
  final String artifactVersion;
  final String normalizationVersion;
  final String pronunciationProfileId;
  final List<PronunciationArtifact> artifacts;

  Iterable<PronunciationArtifact> forSegment(String segmentId) =>
      artifacts.where((artifact) => artifact.segmentId == segmentId);
}

class PronunciationArtifact {
  const PronunciationArtifact({
    required this.artifactId,
    required this.segmentId,
    required this.startWord,
    required this.endWord,
    required this.surfaceText,
    required this.normalizedSurfaceText,
    required this.artifactClass,
    required this.source,
    required this.confidence,
    required this.representations,
    this.diagnosticCodes = const <String>[],
  });

  final String artifactId;
  final String segmentId;
  final int startWord;
  final int endWord;
  final String surfaceText;
  final String normalizedSurfaceText;
  final PronunciationArtifactClass artifactClass;
  final PronunciationArtifactSource source;
  final double confidence;
  final List<PronunciationRepresentation> representations;
  final List<String> diagnosticCodes;

  String get spanKey => '$segmentId:$startWord:$endWord';
}

class PronunciationRepresentation {
  const PronunciationRepresentation({
    required this.representationId,
    required this.representationType,
    required this.representationValue,
    required this.priority,
    this.accentFamily,
  });

  final String representationId;
  final String representationType;
  final String representationValue;
  final String? accentFamily;
  final int priority;
}
