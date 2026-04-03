import '../models/english_pronunciation_profile.dart';
import '../models/pronunciation_artifact.dart';
import 'pronunciation_resource_layering_service.dart';

enum PronunciationRuleModuleDecisionKind {
  noDecision,
  resolved,
  unresolvedDiagnostic,
}

class PronunciationRuleModuleContext {
  const PronunciationRuleModuleContext({
    required this.segmentId,
    required this.segmentText,
    required this.tokenIndex,
    required this.surfaceText,
    required this.normalizedSurfaceText,
    required this.selectedProfile,
    required this.mergedResources,
    this.previousToken,
    this.nextToken,
  });

  final String segmentId;
  final String segmentText;
  final int tokenIndex;
  final String surfaceText;
  final String normalizedSurfaceText;
  final EnglishPronunciationProfile selectedProfile;
  final MergedPronunciationResources mergedResources;
  final String? previousToken;
  final String? nextToken;
}

class PronunciationRuleModuleDecision {
  const PronunciationRuleModuleDecision({
    required this.kind,
    this.representations = const <PronunciationRepresentation>[],
    this.diagnosticCodes = const <String>[],
    this.confidence = 0.0,
  });

  const PronunciationRuleModuleDecision.noDecision()
    : kind = PronunciationRuleModuleDecisionKind.noDecision,
      representations = const <PronunciationRepresentation>[],
      diagnosticCodes = const <String>[],
      confidence = 0.0;

  final PronunciationRuleModuleDecisionKind kind;
  final List<PronunciationRepresentation> representations;
  final List<String> diagnosticCodes;
  final double confidence;
}

abstract class PronunciationRuleModule {
  const PronunciationRuleModule();

  String get moduleId;
  bool get supportsDocumentTime;
  bool get supportsSessionTime;

  PronunciationRuleModuleDecision apply(PronunciationRuleModuleContext context);
}
