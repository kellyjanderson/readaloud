import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/kokoro_voice_catalog.dart';

void main() {
  group('Voice metadata normalization', () {
    test('platform voices keep metadata optional when absent', () {
      final profile = VoiceProfile.fromPlatformMap(<String, Object?>{
        'identifier': 'voice_a',
        'name': 'Voice A',
        'locale': 'en-US',
      });

      expect(profile.gender, isNull);
      expect(profile.qualityGrade, isNull);
      expect(profile.targetQuality, isNull);
      expect(profile.trainingDurationLabel, isNull);
      expect(profile.traits, isEmpty);
      expect(profile.description, isNull);
      expect(profile.metadataSource, VoiceMetadataSource.platformProvided);
    });

    test('platform voices normalize supported raw metadata fields', () {
      final profile = VoiceProfile.fromPlatformMap(<String, Object?>{
        'identifier': 'voice_a',
        'name': 'Voice A',
        'locale': 'en-US',
        'gender': 'female',
        'qualityGrade': 'A-',
        'targetQuality': 'high',
        'trainingDurationLabel': 'extended',
        'traits': <String>['warm', 'clear'],
        'description': 'A test voice.',
      });

      expect(profile.gender, VoiceGender.female);
      expect(profile.qualityGrade, 'A-');
      expect(profile.targetQuality, 'high');
      expect(profile.trainingDurationLabel, 'extended');
      expect(profile.traits, <String>['warm', 'clear']);
      expect(profile.description, 'A test voice.');
    });

    test('kokoro profiles expose normalized app-owned metadata', () {
      final profile = KokoroVoiceCatalog.profileForId('af_bella');

      expect(profile.gender, VoiceGender.female);
      expect(profile.qualityGrade, 'A-');
      expect(profile.metadataSource, VoiceMetadataSource.engineCatalog);
      expect(profile.targetQuality, isNull);
      expect(profile.trainingDurationLabel, isNull);
      expect(profile.traits, isEmpty);
      expect(profile.description, isNull);
    });

    test('bundled starter set is a curated US-English balance', () {
      final bundledProfiles = KokoroVoiceCatalog.profilesForIds(
        KokoroVoiceCatalog.bundledVoiceIds,
      );

      expect(KokoroVoiceCatalog.defaultVoiceId, 'af_heart');
      expect(
        KokoroVoiceCatalog.bundledVoiceIds,
        <String>[
          'af_heart',
          'af_bella',
          'am_michael',
          'am_fenrir',
          'am_puck',
        ],
      );
      expect(
        bundledProfiles.every((profile) => profile.locale == 'en-US'),
        isTrue,
      );
      expect(
        bundledProfiles.where((profile) => profile.gender == VoiceGender.female),
        hasLength(2),
      );
      expect(
        bundledProfiles.where((profile) => profile.gender == VoiceGender.male),
        hasLength(2),
      );
      expect(
        bundledProfiles.where((profile) => profile.gender == VoiceGender.neutral),
        hasLength(1),
      );
      expect(
        bundledProfiles.singleWhere(
          (profile) => profile.id == 'am_puck',
        ).qualityGrade,
        'C+',
      );
    });
  });
}
