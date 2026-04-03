import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/english_pronunciation_profile_selector.dart';

void main() {
  group('EnglishPronunciationProfileSelector', () {
    const selector = EnglishPronunciationProfileSelector();

    test('prefers explicit user-selected profile when available', () {
      final selected = selector.select(
        const EnglishPronunciationProfileSelectionInput(
          engineId: 'kokoro',
          voiceId: 'af_bella',
          userSelectedProfileId: 'en-gb-core',
        ),
      );

      expect(selected.profileId, 'en-gb-core');
    });

    test('uses exact known English voice mapping before generic fallback', () {
      final selected = selector.select(
        const EnglishPronunciationProfileSelectionInput(
          engineId: 'kokoro',
          voiceId: 'bf_emma',
        ),
      );

      expect(selected.profileId, 'en-gb-core');
    });

    test('falls back to en-us-core when no English mapping is available', () {
      final selected = selector.select(
        const EnglishPronunciationProfileSelectionInput(
          engineId: 'generic',
          voiceId: 'unknown_voice',
        ),
      );

      expect(selected.profileId, 'en-us-core');
    });
  });
}
