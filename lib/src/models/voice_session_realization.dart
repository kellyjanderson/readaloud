import 'narration_state.dart';
import 'english_pronunciation_profile.dart';
import 'pronunciation_artifact.dart';
import 'speech_annotation.dart';
import 'speech_document.dart';
import '../services/pronunciation_resource_layering_service.dart';
import '../services/pronunciation_rule_module.dart';
import 'tts_artifact.dart';

class VoiceSessionRealizationInput {
  const VoiceSessionRealizationInput({
    required this.speechDocument,
    required this.baseAnnotations,
    required this.basePronunciationArtifacts,
    required this.startSegmentId,
    required this.voiceId,
    required this.engineId,
    required this.rate,
    required this.narrationState,
    this.selectedProfile = EnglishPronunciationProfileRegistry.enUsCore,
    this.mergedPronunciationResources =
        const MergedPronunciationResources.empty(),
    this.enabledActiveRuleModules = const <PronunciationRuleModule>[],
  });

  final SpeechDocument speechDocument;
  final BaseSpeechAnnotationSet baseAnnotations;
  final BasePronunciationArtifactSet basePronunciationArtifacts;
  final String startSegmentId;
  final String voiceId;
  final String engineId;
  final double rate;
  final NarrationState narrationState;
  final EnglishPronunciationProfile selectedProfile;
  final MergedPronunciationResources mergedPronunciationResources;
  final List<PronunciationRuleModule> enabledActiveRuleModules;
}

class VoiceSessionRealization {
  const VoiceSessionRealization({
    required this.realizationId,
    required this.startSegmentId,
    required this.endSegmentId,
    required this.voiceId,
    required this.engineId,
    required this.rate,
    required this.selectedProfileId,
    required this.artifacts,
    required this.boundaryIntents,
    required this.emphasisIntents,
    required this.ttsArtifactSet,
  });

  final String realizationId;
  final String startSegmentId;
  final String endSegmentId;
  final String voiceId;
  final String engineId;
  final double rate;
  final String selectedProfileId;
  final List<RealizedPronunciationArtifact> artifacts;
  final List<RealizedBoundaryIntent> boundaryIntents;
  final List<RealizedEmphasisIntent> emphasisIntents;
  final TtsArtifactSet ttsArtifactSet;
}
