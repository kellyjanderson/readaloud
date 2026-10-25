enum VoiceAssignmentPhase { current, pending, preparing, applying, failed }

/// UI-safe snapshot. Requested choices are intent; effective choices change
/// only after the current prepared playback request is acknowledged.
class VoiceAssignmentState {
  VoiceAssignmentState({
    this.requestedRevision = 0,
    this.effectiveRevision = 0,
    this.requestedDefaultVoiceId,
    this.effectiveDefaultVoiceId,
    Map<String, String> requestedCastVoices = const {},
    Map<String, String> effectiveCastVoices = const {},
    this.phase = VoiceAssignmentPhase.current,
    this.errorMessage,
    this.isInitialBuffering = false,
  }) : requestedCastVoices = Map.unmodifiable(requestedCastVoices),
       effectiveCastVoices = Map.unmodifiable(effectiveCastVoices);

  final int requestedRevision;
  final int effectiveRevision;
  final String? requestedDefaultVoiceId;
  final String? effectiveDefaultVoiceId;
  final Map<String, String> requestedCastVoices;
  final Map<String, String> effectiveCastVoices;
  final VoiceAssignmentPhase phase;
  final String? errorMessage;
  final bool isInitialBuffering;
  bool get hasPending => requestedRevision != effectiveRevision;
}
