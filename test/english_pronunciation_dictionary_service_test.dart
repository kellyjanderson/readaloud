import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/english_pronunciation_dictionary_service.dart';

void main() {
  group('EnglishPronunciationDictionaryService CMUdict conversion', () {
    test(
      'raw-data initialization preserves first variant and snapshot ownership',
      () {
        final service = EnglishPronunciationDictionaryService.instance;
        addTearDown(service.resetForTesting);
        service.restoreRawDictionary(
          ';;; comment\nSAID S EH1 D\nSAID(2) S EH0 D\nJOHN JH AA1 N\ninvalid\n',
        );
        expect(service.lookup('SAID'), 'sˈɛd');
        expect(service.lookup('John'), 'dʒˈɑn');
        expect(service.isInitialized, isTrue);
        expect(() => service.entriesSnapshot.clear(), throwsUnsupportedError);
      },
    );
    test('maps stressed ER to standard IPA internally', () {
      expect(
        convertCmudictArpabetToStandardIpaForTesting('F ER1 S T'),
        'fˈɝst',
      );
      expect(convertCmudictArpabetToStandardIpaForTesting('B ER1 D'), 'bˈɝd');
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
      expect(convertCmudictArpabetToStandardIpaForTesting('JH AA1 N'), 'dʒˈɑn');
      expect(
        convertCmudictArpabetToStandardIpaForTesting('CH ER1 CH'),
        'tʃˈɝtʃ',
      );
    });
  });
}
