import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'cast_voice_assignment.dart';

/// Serializable resource identity. Native handles never belong to this record.
class PreparedVoiceBinding {
  const PreparedVoiceBinding({
    required this.voiceId,
    required this.voiceDigest,
    required this.modelDigest,
    required this.engineVersion,
    required this.pronunciationProfileId,
    required this.bindingRevision,
    required this.documentId,
  });
  final String voiceId;
  final String voiceDigest;
  final String modelDigest;
  final String engineVersion;
  final String pronunciationProfileId;
  final int bindingRevision;
  final String documentId;
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'prepared-binding-v1',
            modelDigest,
            voiceDigest,
            engineVersion,
            pronunciationProfileId,
          ]),
        ),
      )
      .toString();
  Map<String, Object?> toMap() => {
    'voiceId': voiceId,
    'voiceDigest': voiceDigest,
    'modelDigest': modelDigest,
    'engineVersion': engineVersion,
    'pronunciationProfileId': pronunciationProfileId,
    'bindingRevision': bindingRevision,
    'documentId': documentId,
  };
  factory PreparedVoiceBinding.fromMap(Map<Object?, Object?> value) =>
      PreparedVoiceBinding(
        voiceId: value['voiceId'] as String,
        voiceDigest: value['voiceDigest'] as String,
        modelDigest: value['modelDigest'] as String,
        engineVersion: value['engineVersion'] as String,
        pronunciationProfileId: value['pronunciationProfileId'] as String,
        bindingRevision: value['bindingRevision'] as int,
        documentId: value['documentId'] as String,
      );
}

/// A resolved character reference preserves the assignment decision as evidence.
class ResolvedPreparedVoiceReference {
  const ResolvedPreparedVoiceReference({
    required this.assignment,
    required this.resource,
    required this.documentRevision,
  });
  final CastVoiceAssignment assignment;
  final PreparedVoiceBinding resource;
  final int documentRevision;
  Map<String, Object?> toMap() => {
    'documentId': resource.documentId,
    'documentRevision': documentRevision,
    'castId': assignment.castId,
    'decisionKind': assignment.decisionKind.name,
    'automaticVoiceId': assignment.automaticVoiceId,
    'storedVoiceId': assignment.storedVoiceId,
    'userOverrideVoiceId': assignment.userOverrideVoiceId,
    'resource': resource.toMap(),
  };
}
