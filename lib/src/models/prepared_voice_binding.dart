/// Serializable resource identity. Native handles never belong to this record.
class PreparedVoiceBinding {
  const PreparedVoiceBinding({
    required this.voiceId,
    required this.voiceDigest,
    required this.modelDigest,
    required this.engineVersion,
    required this.pronunciationProfileId,
    required this.bindingRevision,
  });
  final String voiceId;
  final String voiceDigest;
  final String modelDigest;
  final String engineVersion;
  final String pronunciationProfileId;
  final int bindingRevision;
  String get fingerprint =>
      '$modelDigest:$voiceDigest:$engineVersion:$pronunciationProfileId';
  Map<String, Object?> toMap() => {
    'voiceId': voiceId,
    'voiceDigest': voiceDigest,
    'modelDigest': modelDigest,
    'engineVersion': engineVersion,
    'pronunciationProfileId': pronunciationProfileId,
    'bindingRevision': bindingRevision,
  };
  factory PreparedVoiceBinding.fromMap(Map<Object?, Object?> value) =>
      PreparedVoiceBinding(
        voiceId: value['voiceId'] as String,
        voiceDigest: value['voiceDigest'] as String,
        modelDigest: value['modelDigest'] as String,
        engineVersion: value['engineVersion'] as String,
        pronunciationProfileId: value['pronunciationProfileId'] as String,
        bindingRevision: value['bindingRevision'] as int,
      );
}
