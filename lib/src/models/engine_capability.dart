import 'package:flutter/foundation.dart';
import 'speech_adjustment_context.dart';

class EngineCapabilityProfile {
  const EngineCapabilityProfile({
    required this.capabilityProfileId,
    required this.engineId,
    required this.platformFamily,
    required this.capabilityVersion,
    required this.directRepresentationTypes,
    required this.approximableRepresentationTypes,
    required this.supportsPlainTextFallback,
    this.modelId = '',
    this.modelRevision = '',
  });

  final String capabilityProfileId;
  final String engineId;
  final String platformFamily;
  final String capabilityVersion;
  final Set<String> directRepresentationTypes;
  final Set<String> approximableRepresentationTypes;
  final bool supportsPlainTextFallback;
  final String modelId;
  final String modelRevision;
  SpeechModelContext get modelContext => SpeechModelContext(
    engineId: engineId,
    modelId: modelId,
    modelRevision: modelRevision,
    capabilityVersion: capabilityVersion,
  );

  bool supportsDirectRepresentation(String representationType) {
    return directRepresentationTypes.contains(representationType);
  }

  bool supportsApproximation(String representationType) {
    return approximableRepresentationTypes.contains(representationType);
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'capabilityProfileId': capabilityProfileId,
      'engineId': engineId,
      'modelId': modelId,
      'modelRevision': modelRevision,
      'platformFamily': platformFamily,
      'capabilityVersion': capabilityVersion,
      'directRepresentationTypes': directRepresentationTypes.toList()..sort(),
      'approximableRepresentationTypes':
          approximableRepresentationTypes.toList()..sort(),
      'supportsPlainTextFallback': supportsPlainTextFallback,
    };
  }

  factory EngineCapabilityProfile.fromMap(Map<String, Object?> map) {
    return EngineCapabilityProfile(
      capabilityProfileId: map['capabilityProfileId']! as String,
      engineId: map['engineId']! as String,
      modelId: map['modelId'] as String? ?? '',
      modelRevision: map['modelRevision'] as String? ?? '',
      platformFamily: map['platformFamily']! as String,
      capabilityVersion: map['capabilityVersion']! as String,
      directRepresentationTypes: Set<String>.from(
        map['directRepresentationTypes']! as List<Object?>,
      ),
      approximableRepresentationTypes: Set<String>.from(
        map['approximableRepresentationTypes']! as List<Object?>,
      ),
      supportsPlainTextFallback: map['supportsPlainTextFallback']! as bool,
    );
  }
}

class EngineCapabilityRegistry {
  const EngineCapabilityRegistry();

  EngineCapabilityProfile lookup({
    required String engineId,
    String? platformFamily,
    String capabilityVersion = 'v1',
    String? modelId,
    String? modelRevision,
  }) {
    final resolvedPlatformFamily = platformFamily ?? currentPlatformFamily();
    switch (engineId) {
      case 'kokoro':
        return EngineCapabilityProfile(
          capabilityProfileId:
              'kokoro:$resolvedPlatformFamily:$capabilityVersion',
          engineId: engineId,
          modelId: modelId ?? 'kokoro-v1.0.onnx',
          modelRevision: modelRevision ?? '1.0',
          platformFamily: resolvedPlatformFamily,
          capabilityVersion: capabilityVersion,
          directRepresentationTypes: const <String>{
            'phoneme_string',
            'explicit_suffix_phoneme',
          },
          approximableRepresentationTypes: const <String>{
            'normalized_spoken_text',
          },
          supportsPlainTextFallback: true,
        );
      case 'qwen3_tts_base_1_7b':
      case 'qwen3_tts_1_7b':
      case 'voxtral_4b':
      case 'fish_drama3_8bit':
      case 'fish_drama3_4bit':
      case 'moss_tts_8b':
        return EngineCapabilityProfile(
          capabilityProfileId:
              '$engineId:$resolvedPlatformFamily:$capabilityVersion',
          engineId: engineId,
          modelId: modelId ?? '',
          modelRevision: modelRevision ?? '',
          platformFamily: resolvedPlatformFamily,
          capabilityVersion: capabilityVersion,
          directRepresentationTypes: const <String>{},
          approximableRepresentationTypes: const <String>{
            'normalized_spoken_text',
          },
          supportsPlainTextFallback: true,
        );
      case 'fish_drama3':
        return EngineCapabilityProfile(
          capabilityProfileId:
              '$engineId:$resolvedPlatformFamily:$capabilityVersion',
          engineId: engineId,
          modelId: modelId ?? 'mlx-community/fish-audio-drama-3-bf16',
          modelRevision:
              modelRevision ?? '8c5496f9af370bb9342ab98130b27b5389d1b1cb',
          platformFamily: resolvedPlatformFamily,
          capabilityVersion: capabilityVersion,
          directRepresentationTypes: const <String>{'inline_delivery_cue'},
          approximableRepresentationTypes: const <String>{
            'normalized_spoken_text',
          },
          supportsPlainTextFallback: true,
        );
    }

    throw UnsupportedError(
      'No engine capability profile is registered for $engineId.',
    );
  }
}

String currentPlatformFamily() {
  if (kIsWeb) {
    return 'web';
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}
