import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/reader_appearance_mode.dart';
import 'package:read_aloud/src/models/reader_resume_state.dart';
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
      expect(preferences.appearanceMode, ReaderAppearanceMode.system);
      expect(
        preferences.multiVoiceEnabled,
        ReaderPreferences.defaultMultiVoiceEnabled,
      );
      expect(preferences.selectedVoiceId, isNull);
      expect(preferences.voiceSpeeds, isEmpty);
      expect(preferences.resumeState, isNull);
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
        appearanceMode: ReaderAppearanceMode.dark,
        multiVoiceEnabled: false,
        resumeState: const ReaderResumeState(
          documentPath: '/tmp/books/love.txt',
          wordIndex: 42,
          wordIndexWithinSegment: 3,
          segmentTextAnchor: 'A remembered sentence anchor.',
          anchorWordText: 'sentence',
        ),
        lastOpenedDocumentPath: '/tmp/books/love.txt',
        lastOpenedDirectoryPath: '/tmp/books',
      );

      final preferences = await service.load();
      expect(preferences.selectedVoiceId, 'af_bella');
      expect(preferences.voiceSpeeds['af_bella'], 1.15);
      expect(preferences.fontFamily, 'sans-serif');
      expect(preferences.fontScale, 1.2);
      expect(preferences.appearanceMode, ReaderAppearanceMode.dark);
      expect(preferences.multiVoiceEnabled, isFalse);
      expect(preferences.resumeState, isNotNull);
      expect(preferences.resumeState!.documentPath, '/tmp/books/love.txt');
      expect(preferences.resumeState!.wordIndex, 42);
      expect(preferences.resumeState!.wordIndexWithinSegment, 3);
      expect(
        preferences.resumeState!.segmentTextAnchor,
        'A remembered sentence anchor.',
      );
      expect(preferences.resumeState!.anchorWordText, 'sentence');
      expect(preferences.lastOpenedDocumentPath, '/tmp/books/love.txt');
      expect(preferences.lastOpenedDirectoryPath, '/tmp/books');
    });
  });
}
