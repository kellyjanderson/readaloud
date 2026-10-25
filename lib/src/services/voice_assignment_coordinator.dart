import '../models/voice_assignment_state.dart';

/// Main-isolate owner of requested/effective voice revisions. Engine workers
/// never mutate this state; they return an identity-checked acknowledgment.
class VoiceAssignmentCoordinator {
  int _requestedRevision = 0;
  int _effectiveRevision = 0;
  String? _requestedDefault;
  String? _effectiveDefault;
  Map<String, String> _requestedCast = const {};
  Map<String, String> _effectiveCast = const {};
  VoiceAssignmentPhase _phase = VoiceAssignmentPhase.current;
  String? _error;
  bool _initialBuffering = false;

  VoiceAssignmentState get state => VoiceAssignmentState(
    requestedRevision: _requestedRevision,
    effectiveRevision: _effectiveRevision,
    requestedDefaultVoiceId: _requestedDefault,
    effectiveDefaultVoiceId: _effectiveDefault,
    requestedCastVoices: _requestedCast,
    effectiveCastVoices: _effectiveCast,
    phase: _phase,
    errorMessage: _error,
    isInitialBuffering: _initialBuffering,
  );

  int request({
    required String? defaultVoiceId,
    required Map<String, String> castVoices,
    required bool initialBuffering,
  }) {
    ++_requestedRevision;
    _requestedDefault = defaultVoiceId;
    _requestedCast = Map.unmodifiable(castVoices);
    _initialBuffering = initialBuffering;
    _phase = initialBuffering
        ? VoiceAssignmentPhase.preparing
        : VoiceAssignmentPhase.pending;
    _error = null;
    return _requestedRevision;
  }

  bool isCurrent(int revision) => revision == _requestedRevision;
  void preparing(int revision, {required bool initialBuffering}) {
    if (!isCurrent(revision)) return;
    _initialBuffering = initialBuffering;
    _phase = initialBuffering
        ? VoiceAssignmentPhase.preparing
        : VoiceAssignmentPhase.applying;
    _error = null;
  }

  bool acknowledge(int revision) {
    if (!isCurrent(revision)) return false;
    _effectiveRevision = revision;
    _effectiveDefault = _requestedDefault;
    _effectiveCast = _requestedCast;
    _phase = VoiceAssignmentPhase.current;
    _initialBuffering = false;
    _error = null;
    return true;
  }

  void fail(int revision, Object error) {
    if (!isCurrent(revision)) return;
    _phase = VoiceAssignmentPhase.failed;
    _error = error.toString();
  }
}
