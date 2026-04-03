import 'package:flutter/foundation.dart';

class EngineCapabilityProfile {
  const EngineCapabilityProfile({
    required this.capabilityProfileId,
    required this.engineId,
    required this.platformFamily,
    required this.capabilityVersion,
    required this.directRepresentationTypes,
    required this.approximableRepresentationTypes,
    required this.supportsPlainTextFallback,
  });

  final String capabilityProfileId;
  final String engineId;
  final String platformFamily;
  final String capabilityVersion;
  final Set<String> directRepresentationTypes;
  final Set<String> approximableRepresentationTypes;
  final bool supportsPlainTextFallback;

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
  }) {
    final resolvedPlatformFamily = platformFamily ?? currentPlatformFamily();
    switch (engineId) {
      case 'kokoro':
        return EngineCapabilityProfile(
          capabilityProfileId:
              'kokoro:$resolvedPlatformFamily:$capabilityVersion',
          engineId: engineId,
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
