/// Main-isolate publication of desired and validated resource identity.
/// A released last-working identity describes a reload target, never residency.
enum EngineSessionPhase {
  active,
  stopping,
  unloading,
  acquiring,
  loading,
  validating,
  cancelled,
  failed,
}

class EngineSessionIdentity {
  const EngineSessionIdentity(this.engineId, int voxtralQuantizationBits)
    : quantizationBits = engineId == 'voxtral_4b' ? voxtralQuantizationBits : 0;
  final String engineId;

  /// Legacy Voxtral runtime option; zero for other engines. Fish checkpoint
  /// precision is encoded by engineId, never a runtime quantization request.
  final int quantizationBits;
}

class EngineSession {
  const EngineSession({
    this.epoch = 0,
    this.selected = const EngineSessionIdentity('kokoro', 0),
    this.active,
    this.lastWorking,
    this.phase = EngineSessionPhase.loading,
  });
  final int epoch;
  final EngineSessionIdentity selected;
  final EngineSessionIdentity? active;
  final EngineSessionIdentity? lastWorking;
  final EngineSessionPhase phase;
}
