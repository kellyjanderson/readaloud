import 'package:flutter_test/flutter_test.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';
import 'package:read_aloud/src/services/english_speech_preprocessor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kokoro tokenizer lexicon overrides', () {
    test('honors app lexicon entries for stubborn pronunciations', () async {
      final tokenizer = Tokenizer(
        config: const TokenizerConfig(lexiconPath: 'assets/lexicon.json'),
      );
      await tokenizer.ensureInitialized();

      final prepared = prepareEnglishSpeechTextForPhonemizer(
        'Elliot exclaimed, stomped, and retorted.',
      );

      final phonemes = await tokenizer.phonemize(prepared, lang: 'en-us');

      expect(phonemes, contains('ˈɛliət'));
      expect(phonemes, contains('ɪksklˈeɪmd'));
      expect(phonemes, contains('stˈɑmpt'));
      expect(phonemes, contains('ɹɪtˈɔɹtɪd'));
    });
  });
}
