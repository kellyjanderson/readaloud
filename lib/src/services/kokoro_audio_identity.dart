import '../models/prepared_voice_binding.dart';
import 'audio_artifact_store.dart';
import 'speech_worker_pipeline.dart';

/// Invocation revision is checked separately from reusable content identity.
void validateExpectedBinding(
  SpeechWorkerChunkRequest request,
  PreparedVoiceBinding binding,
) {
  if (request.expectedBindingFingerprint != binding.fingerprint ||
      request.expectedBindingRevision != binding.bindingRevision ||
      request.documentId != binding.documentId ||
      request.voiceId != binding.voiceId) {
    throw StateError(
      'Synthesis resource binding changed after this request was prepared.',
    );
  }
}

String kokoroRawAudioIdentity(
  SpeechWorkerChunkRequest request,
  PreparedVoiceBinding binding,
  String engineId,
  String engineVersion,
) {
  if (!request.rate.isFinite || request.rate <= 0) {
    throw ArgumentError.value(request.rate, 'rate');
  }
  return artifactIdentity({
    'schema': 'kokoro-raw-v1',
    'engineId': engineId,
    'engineVersion': engineVersion,
    'binding': binding.fingerprint,
    'voiceId': request.voiceId,
    'rate': request.rate.toString(),
    'normalization': request.normalizationVersion,
    'synthesisIdentity': request.synthesisIdentity,
    'capability': request.capabilityProfileId,
    'language': request.languageTag,
    'speakText': request.speakText,
    'tokens': request.tokens,
    'pronunciationArtifacts': request.pronunciationArtifacts,
    'missingFallbackWordCount': request.missingFallbackWordCount,
  });
}
