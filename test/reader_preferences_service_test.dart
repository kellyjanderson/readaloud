import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ReaderPreferencesService', () {
    test('loads defaults when no preferences are stored', () async {
      final service = ReaderPreferencesService();
      final preferences = await service.load();

      expect(preferences.fontFamily, ReaderPreferences.defaultFontFamily);
      expect(preferences.fontScale, ReaderPreferences.defaultFontScale);
      expect(preferences.selectedVoiceId, isNull);
      expect(preferences.voiceSpeeds, isEmpty);
      expect(preferences.lastOpenedDocumentPath, isNull);
      expect(preferences.lastOpenedDirectoryPath, isNull);
    });

    test('persists last opened document and folder paths', () async {
      final service = ReaderPreferencesService();

      await service.save(
        selectedVoiceId: 'af_bella',
        voiceSpeeds: const <String, double>{'af_bella': 1.15},
        fontFamily: 'sans-serif',
        fontScale: 1.2,
        lastOpenedDocumentPath: '/tmp/books/love.txt',
        lastOpenedDirectoryPath: '/tmp/books',
      );

      final preferences = await service.load();
      expect(preferences.selectedVoiceId, 'af_bella');
      expect(preferences.voiceSpeeds['af_bella'], 1.15);
      expect(preferences.fontFamily, 'sans-serif');
      expect(preferences.fontScale, 1.2);
      expect(preferences.lastOpenedDocumentPath, '/tmp/books/love.txt');
      expect(preferences.lastOpenedDirectoryPath, '/tmp/books');
    });
  });
}
