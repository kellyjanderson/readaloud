class VoiceProfile {
  const VoiceProfile({
    required this.id,
    required this.label,
    required this.locale,
    required this.rawValue,
  });

  final String id;
  final String label;
  final String locale;
  final Map<String, dynamic> rawValue;

  String get displayName => locale.isEmpty ? label : '$label ($locale)';

  factory VoiceProfile.fromPlatformMap(Map<dynamic, dynamic> input) {
    final rawValue = Map<String, dynamic>.from(input);
    final label = (rawValue['name'] ?? rawValue['identifier'] ?? 'Voice')
        .toString();
    final locale = (rawValue['locale'] ?? rawValue['language'] ?? '')
        .toString();
    final identifier = (rawValue['identifier'] ?? '').toString();
    final id = identifier.isNotEmpty ? identifier : '$label::$locale';
    return VoiceProfile(
      id: id,
      label: label,
      locale: locale,
      rawValue: rawValue,
    );
  }
}
