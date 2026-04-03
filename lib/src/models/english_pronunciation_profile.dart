class EnglishPronunciationProfile {
  const EnglishPronunciationProfile({
    required this.profileId,
    required this.localeTag,
    required this.accentFamily,
    required this.englishVariantFamily,
    required this.parentProfileId,
    required this.isOverlayProfile,
    required this.resourceLayerIds,
    required this.enabledRuleModuleIds,
  });

  final String profileId;
  final String localeTag;
  final String accentFamily;
  final String englishVariantFamily;
  final String? parentProfileId;
  final bool isOverlayProfile;
  final List<String> resourceLayerIds;
  final List<String> enabledRuleModuleIds;
}

class EnglishPronunciationProfileRegistry {
  static const EnglishPronunciationProfile enUsCore =
      EnglishPronunciationProfile(
        profileId: 'en-us-core',
        localeTag: 'en-US',
        accentFamily: 'en-us',
        englishVariantFamily: 'en-us',
        parentProfileId: null,
        isOverlayProfile: false,
        resourceLayerIds: <String>['global-en', 'en-us-core'],
        enabledRuleModuleIds: <String>['english_suffix_allomorph'],
      );

  static const EnglishPronunciationProfile enGbCore =
      EnglishPronunciationProfile(
        profileId: 'en-gb-core',
        localeTag: 'en-GB',
        accentFamily: 'en-gb',
        englishVariantFamily: 'en-gb',
        parentProfileId: null,
        isOverlayProfile: false,
        resourceLayerIds: <String>['global-en', 'en-gb-core'],
        enabledRuleModuleIds: <String>['english_suffix_allomorph'],
      );

  static const EnglishPronunciationProfile enAuCore =
      EnglishPronunciationProfile(
        profileId: 'en-au-core',
        localeTag: 'en-AU',
        accentFamily: 'en-au',
        englishVariantFamily: 'en-au',
        parentProfileId: null,
        isOverlayProfile: false,
        resourceLayerIds: <String>['global-en', 'en-au-core'],
        enabledRuleModuleIds: <String>['english_suffix_allomorph'],
      );

  static const EnglishPronunciationProfile enUsGermanAccented =
      EnglishPronunciationProfile(
        profileId: 'en-us-german-accented',
        localeTag: 'en-US',
        accentFamily: 'en-us-german-accented',
        englishVariantFamily: 'en-us',
        parentProfileId: 'en-us-core',
        isOverlayProfile: true,
        resourceLayerIds: <String>[
          'global-en',
          'en-us-core',
          'en-us-german-accented',
        ],
        enabledRuleModuleIds: <String>['english_suffix_allomorph'],
      );

  static const List<EnglishPronunciationProfile> allProfiles =
      <EnglishPronunciationProfile>[
        enAuCore,
        enGbCore,
        enUsCore,
        enUsGermanAccented,
      ];

  static EnglishPronunciationProfile? maybeById(String profileId) {
    for (final profile in allProfiles) {
      if (profile.profileId == profileId) {
        return profile;
      }
    }
    return null;
  }

  static EnglishPronunciationProfile byId(String profileId) {
    return maybeById(profileId) ?? enUsCore;
  }
}
