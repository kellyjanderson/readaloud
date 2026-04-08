import '../models/voice_profile.dart';

class KokoroVoiceCatalog {
  static const String defaultVoiceId = 'af_heart';

  static const List<String> bundledVoiceIds = <String>[
    'af_heart',
    'af_bella',
    'am_michael',
    'am_fenrir',
    'am_puck',
  ];

  static const List<String> allVoiceIds = <String>[
    'af_alloy',
    'af_aoede',
    'af_bella',
    'af_heart',
    'af_jessica',
    'af_kore',
    'af_nicole',
    'af_nova',
    'af_river',
    'af_sarah',
    'af_sky',
    'am_adam',
    'am_echo',
    'am_eric',
    'am_fenrir',
    'am_liam',
    'am_michael',
    'am_onyx',
    'am_puck',
    'am_santa',
    'bf_alice',
    'bf_emma',
    'bf_isabella',
    'bf_lily',
    'bm_daniel',
    'bm_fable',
    'bm_george',
    'bm_lewis',
    'ef_dora',
    'em_alex',
    'em_santa',
    'ff_siwis',
    'hf_alpha',
    'hf_beta',
    'hm_omega',
    'hm_psi',
    'if_sara',
    'im_nicola',
    'jf_alpha',
    'jf_gongitsune',
    'jf_nezumi',
    'jf_tebukuro',
    'jm_kumo',
    'pf_dora',
    'pm_alex',
    'pm_santa',
    'zf_xiaobei',
    'zf_xiaoni',
    'zf_xiaoxiao',
    'zf_xiaoyi',
    'zm_yunjian',
    'zm_yunxi',
    'zm_yunxia',
    'zm_yunyang',
  ];

  static List<VoiceProfile> profilesForIds(Iterable<String> voiceIds) {
    final uniqueIds = voiceIds.toSet().toList(growable: false)..sort();
    final profiles = uniqueIds.map(profileForId).toList(growable: false);
    profiles.sort((a, b) {
      final localeComparison = a.locale.compareTo(b.locale);
      if (localeComparison != 0) {
        return localeComparison;
      }
      return a.label.compareTo(b.label);
    });
    return profiles;
  }

  static List<VoiceProfile> get allProfiles => profilesForIds(allVoiceIds);

  static VoiceProfile profileForId(String voiceId) {
    final label = _voiceLabel(voiceId);
    final locale = _voiceLocale(voiceId);
    final metadata = _metadataForVoice(voiceId);
    return VoiceProfile(
      id: voiceId,
      label: label,
      locale: locale,
      rawValue: <String, dynamic>{
        'engine': 'kokoro',
        'voiceId': voiceId,
        'name': label,
        'locale': locale,
      },
      gender: metadata.gender,
      qualityGrade: metadata.qualityGrade,
      targetQuality: metadata.targetQuality,
      trainingDurationLabel: metadata.trainingDurationLabel,
      traits: metadata.traits,
      description: metadata.description,
      metadataSource: VoiceMetadataSource.engineCatalog,
    );
  }

  static bool isBundled(String voiceId) => bundledVoiceIds.contains(voiceId);

  static String bundledAssetPath(String voiceId) {
    return 'assets/kokoro/voices/$voiceId.npy';
  }

  static String languageTagForVoice(String voiceId) {
    return switch (_voiceFamily(voiceId)) {
      'a' => 'en-us',
      'b' => 'en-gb',
      'e' => 'es',
      'f' => 'fr-fr',
      'h' => 'hi',
      'i' => 'it',
      'j' => 'ja',
      'p' => 'pt-br',
      'z' => 'zh',
      _ => 'en-us',
    };
  }

  static VoiceGender genderForVoice(String voiceId) {
    if (voiceId.length >= 2) {
      return switch (voiceId[1]) {
        'f' => VoiceGender.female,
        'm' => VoiceGender.male,
        _ => VoiceGender.neutral,
      };
    }
    return VoiceGender.neutral;
  }

  static String _voiceLabel(String voiceId) {
    final segments = voiceId.split('_');
    if (segments.length < 2) {
      return voiceId;
    }
    return segments
        .skip(1)
        .map((segment) {
          if (segment.isEmpty) {
            return segment;
          }
          return '${segment[0].toUpperCase()}${segment.substring(1)}';
        })
        .join(' ');
  }

  static String _voiceLocale(String voiceId) {
    return switch (_voiceFamily(voiceId)) {
      'a' => 'en-US',
      'b' => 'en-GB',
      'e' => 'es-ES',
      'f' => 'fr-FR',
      'h' => 'hi-IN',
      'i' => 'it-IT',
      'j' => 'ja-JP',
      'p' => 'pt-BR',
      'z' => 'zh-CN',
      _ => '',
    };
  }

  static String _voiceFamily(String voiceId) {
    if (voiceId.isEmpty) {
      return '';
    }
    return voiceId[0].toLowerCase();
  }

  static _KokoroVoiceMetadata _metadataForVoice(String voiceId) {
    return _metadataByVoiceId[voiceId] ??
        _KokoroVoiceMetadata(gender: genderForVoice(voiceId));
  }

  static const Map<String, _KokoroVoiceMetadata> _metadataByVoiceId =
      <String, _KokoroVoiceMetadata>{
        'af_heart': _KokoroVoiceMetadata(
          gender: VoiceGender.female,
          qualityGrade: 'A',
          targetQuality: null,
          trainingDurationLabel: null,
          traits: <String>[],
          description: null,
        ),
        'af_bella': _KokoroVoiceMetadata(
          gender: VoiceGender.female,
          qualityGrade: 'A-',
        ),
        'af_aoede': _KokoroVoiceMetadata(
          gender: VoiceGender.female,
          qualityGrade: 'C+',
        ),
        'af_nicole': _KokoroVoiceMetadata(
          gender: VoiceGender.female,
          qualityGrade: 'B-',
        ),
        'af_kore': _KokoroVoiceMetadata(
          gender: VoiceGender.female,
          qualityGrade: 'C+',
        ),
        'af_sarah': _KokoroVoiceMetadata(
          gender: VoiceGender.female,
          qualityGrade: 'C+',
        ),
        'am_fenrir': _KokoroVoiceMetadata(
          gender: VoiceGender.male,
          qualityGrade: 'C+',
        ),
        'am_michael': _KokoroVoiceMetadata(
          gender: VoiceGender.male,
          qualityGrade: 'C+',
        ),
        'am_puck': _KokoroVoiceMetadata(
          gender: VoiceGender.neutral,
          qualityGrade: 'C+',
        ),
        'bf_emma': _KokoroVoiceMetadata(
          gender: VoiceGender.female,
          qualityGrade: 'B-',
        ),
        'bm_fable': _KokoroVoiceMetadata(
          gender: VoiceGender.male,
          qualityGrade: 'C',
        ),
      };
}

class _KokoroVoiceMetadata {
  const _KokoroVoiceMetadata({
    required this.gender,
    this.qualityGrade,
    this.targetQuality,
    this.trainingDurationLabel,
    this.traits = const <String>[],
    this.description,
  });

  final VoiceGender gender;
  final String? qualityGrade;
  final String? targetQuality;
  final String? trainingDurationLabel;
  final List<String> traits;
  final String? description;
}
