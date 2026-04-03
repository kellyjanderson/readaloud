import '../models/voice_profile.dart';

class KokoroVoiceCatalog {
  static const String defaultVoiceId = 'af_bella';

  static const List<String> bundledVoiceIds = <String>[
    'af_bella',
    'af_nicole',
    'af_heart',
    'am_michael',
    'bf_emma',
    'bm_fable',
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

  static String genderForVoice(String voiceId) {
    if (voiceId.length >= 2) {
      return switch (voiceId[1]) {
        'f' => 'female',
        'm' => 'male',
        _ => 'neutral',
      };
    }
    return 'neutral';
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
}
