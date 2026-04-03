import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/english_pronunciation_dictionary_service.dart';

void main() {
  group('EnglishPronunciationDictionaryService CMUdict conversion', () {
    test('maps stressed ER to standard IPA internally', () {
      expect(
        convertCmudictArpabetToStandardIpaForTesting('F ER1 S T'),
        'fˈɝst',
      );
      expect(
        convertCmudictArpabetToStandardIpaForTesting('B ER1 D'),
        'bˈɝd',
      );
    });

    test('maps unstressed rhotic vowels to standard IPA schwa-r', () {
      expect(
        convertCmudictArpabetToStandardIpaForTesting('F L AH1 T AXR0'),
        'flˈʌtɚ',
      );
      expect(
        convertCmudictArpabetToStandardIpaForTesting('R AH1 N ER0'),
        'ɹˈʌnɚ',
      );
    });

    test('maps affricates to standard IPA sequences internally', () {
      expect(
        convertCmudictArpabetToStandardIpaForTesting('JH AA1 N'),
        'dʒˈɑn',
      );
      expect(
        convertCmudictArpabetToStandardIpaForTesting('CH ER1 CH'),
        'tʃˈɝtʃ',
      );
    });
  });
}
