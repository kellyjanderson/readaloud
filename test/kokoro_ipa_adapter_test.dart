import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_ipa_adapter.dart';

void main() {
  group('adaptStandardIpaToKokoroPhonemes', () {
    test('translates stressed rhotic vowels for Kokoro tokenization', () {
      expect(adaptStandardIpaToKokoroPhonemes('fˈɝst'), 'fˈɜɹst');
      expect(adaptStandardIpaToKokoroPhonemes('θˈɝtin'), 'θˈɜɹtin');
    });

    test('translates standard IPA affricates to Kokoro characters', () {
      expect(adaptStandardIpaToKokoroPhonemes('dʒˈɑn'), 'ʤˈɑn');
      expect(adaptStandardIpaToKokoroPhonemes('tʃˈɝtʃ'), 'ʧˈɜɹʧ');
    });

    test('leaves already-compatible phonemes unchanged', () {
      expect(adaptStandardIpaToKokoroPhonemes('fˈɔɹ'), 'fˈɔɹ');
      expect(adaptStandardIpaToKokoroPhonemes('ˈɛliət'), 'ˈɛliət');
    });
  });
}
