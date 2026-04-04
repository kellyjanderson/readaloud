enum VoiceGender { female, male, neutral }

enum VoiceMetadataSource { platformProvided, engineCatalog, appDerived }

class VoiceProfile {
  const VoiceProfile({
    required this.id,
    required this.label,
    required this.locale,
    required this.rawValue,
    this.gender,
    this.qualityGrade,
    this.targetQuality,
    this.trainingDurationLabel,
    this.traits = const <String>[],
    this.description,
    this.metadataSource = VoiceMetadataSource.platformProvided,
  });

  final String id;
  final String label;
  final String locale;
  final Map<String, dynamic> rawValue;
  final VoiceGender? gender;
  final String? qualityGrade;
  final String? targetQuality;
  final String? trainingDurationLabel;
  final List<String> traits;
  final String? description;
  final VoiceMetadataSource metadataSource;

  String get displayName => locale.isEmpty ? label : '$label ($locale)';

  factory VoiceProfile.fromPlatformMap(Map<dynamic, dynamic> input) {
    final rawValue = Map<String, dynamic>.from(input);
    final label = (rawValue['name'] ?? rawValue['identifier'] ?? 'Voice')
        .toString();
    final locale = (rawValue['locale'] ?? rawValue['language'] ?? '')
        .toString();
    final identifier = (rawValue['identifier'] ?? '').toString();
    final id = identifier.isNotEmpty ? identifier : '$label::$locale';
    final normalizedTraits = _normalizedTraits(rawValue['traits']);
    return VoiceProfile(
      id: id,
      label: label,
      locale: locale,
      rawValue: rawValue,
      gender: _voiceGenderFromRawValue(rawValue['gender']),
      qualityGrade: _stringOrNull(rawValue['qualityGrade']),
      targetQuality: _stringOrNull(rawValue['targetQuality']),
      trainingDurationLabel: _stringOrNull(rawValue['trainingDurationLabel']),
      traits: normalizedTraits,
      description: _stringOrNull(rawValue['description']),
    );
  }
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

List<String> _normalizedTraits(Object? value) {
  if (value is! Iterable) {
    return const <String>[];
  }
  return value
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

VoiceGender? _voiceGenderFromRawValue(Object? value) {
  final normalized = value?.toString().trim().toLowerCase();
  return switch (normalized) {
    'female' => VoiceGender.female,
    'male' => VoiceGender.male,
    'neutral' => VoiceGender.neutral,
    _ => null,
  };
}
