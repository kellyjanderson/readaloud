import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/english_speech_preprocessor.dart';

void main() {
  group('EnglishSpeechPreprocessor', () {
    test('normalizes smart punctuation and invisible separators', () {
      final normalized = normalizeEnglishSpeechText(
        'Mara\u2019s hand\u00ADed\u00A0note\u200B.',
      );

      expect(normalized, "Mara's handed note.");
    });

    test('rewrites apostrophe s to apostrophe z for phonemization', () {
      final prepared = prepareEnglishSpeechTextForPhonemizer(
        "It's Mara's and dogs' turn, but we're late and can't stay.",
      );

      expect(
        prepared,
        "It'z Mara'z and dogs' turn, but we're late and can't stay.",
      );
    });

    test('does not inject inline phoneme markup into prepared text', () {
      final prepared = prepareEnglishSpeechTextForPhonemizer(
        "Elliot exclaimed, stomped, retorted, and reached for the door.",
      );

      expect(
        prepared,
        "Elliot exclaimed, stomped, retorted, and reached for the door.",
      );
    });
  });
}
