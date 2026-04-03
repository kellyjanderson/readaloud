import '../models/english_pronunciation_profile.dart';
import 'kokoro_voice_catalog.dart';

class EnglishPronunciationProfileSelectionInput {
  const EnglishPronunciationProfileSelectionInput({
    required this.engineId,
    this.voiceId,
    this.voiceLocaleTag,
    this.userSelectedProfileId,
  });

  final String engineId;
  final String? voiceId;
  final String? voiceLocaleTag;
  final String? userSelectedProfileId;
}

class EnglishPronunciationProfileSelector {
  const EnglishPronunciationProfileSelector();

  EnglishPronunciationProfile select(
    EnglishPronunciationProfileSelectionInput input,
  ) {
    final explicitProfileId = input.userSelectedProfileId?.trim();
    if (explicitProfileId != null && explicitProfileId.isNotEmpty) {
      final explicitProfile = EnglishPronunciationProfileRegistry.maybeById(
        explicitProfileId,
      );
      if (explicitProfile != null) {
        return explicitProfile;
      }
    }

    final voiceId = input.voiceId?.trim();
    if (voiceId != null && voiceId.isNotEmpty) {
      final mappedProfileId = _exactVoiceMappedProfileId(
        voiceId: voiceId,
        engineId: input.engineId,
      );
      if (mappedProfileId != null) {
        return EnglishPronunciationProfileRegistry.byId(mappedProfileId);
      }
    }

    final localeFamily = _localeFamily(
      input.voiceLocaleTag ?? _localeTagForVoice(voiceId, input.engineId),
    );
    if (localeFamily != null) {
      return switch (localeFamily) {
        'en-au' => EnglishPronunciationProfileRegistry.enAuCore,
        'en-gb' => EnglishPronunciationProfileRegistry.enGbCore,
        'en-us' => EnglishPronunciationProfileRegistry.enUsCore,
        _ => EnglishPronunciationProfileRegistry.enUsCore,
      };
    }

    return EnglishPronunciationProfileRegistry.enUsCore;
  }
}

String? _exactVoiceMappedProfileId({
  required String voiceId,
  required String engineId,
}) {
  if (engineId == 'kokoro' && KokoroVoiceCatalog.allVoiceIds.contains(voiceId)) {
    final languageTag = KokoroVoiceCatalog.languageTagForVoice(voiceId);
    return switch (_localeFamily(languageTag)) {
      'en-au' => 'en-au-core',
      'en-gb' => 'en-gb-core',
      'en-us' => 'en-us-core',
      _ => null,
    };
  }
  return switch (voiceId) {
    'af_bella' || 'af_heart' || 'af_nicole' || 'am_michael' => 'en-us-core',
    'bf_emma' || 'bm_fable' => 'en-gb-core',
    _ => null,
  };
}

String? _localeTagForVoice(String? voiceId, String engineId) {
  if (voiceId == null || voiceId.isEmpty) {
    return null;
  }
  if (engineId == 'kokoro') {
    return KokoroVoiceCatalog.profileForId(voiceId).locale;
  }
  return null;
}

String? _localeFamily(String? localeTag) {
  if (localeTag == null || localeTag.isEmpty) {
    return null;
  }
  final normalized = localeTag.toLowerCase().replaceAll('_', '-');
  if (normalized.startsWith('en-au')) {
    return 'en-au';
  }
  if (normalized.startsWith('en-gb')) {
    return 'en-gb';
  }
  if (normalized.startsWith('en-us')) {
    return 'en-us';
  }
  return null;
}
