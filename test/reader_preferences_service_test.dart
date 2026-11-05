import 'package:read_aloud/src/models/character.dart';
import 'package:read_aloud/src/services/work_character_store.dart';
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
    test(
      'VS17 migration writes one owner; Reset and aliases survive a preference reload',
      () async {
        SharedPreferences.setMockInitialValues({
          'reader.storedDocumentCastVoiceAssignments':
              '{"old-work":{"cast_narrator":"voice-a"}}',
        });
        final service = ReaderPreferencesService();
        final initial = await service.load();
        final owner = WorkCharacterStore()
          ..migrateLegacy(initial.storedDocumentCastVoiceAssignments);
        owner.select('old-work', 'cast_narrator', null);
        owner.associate('old-work', 'canonical');
        await service.save(
          fontFamily: 'serif',
          fontScale: 1,
          appearanceMode: ReaderAppearanceMode.system,
          multiVoiceEnabled: true,
          voiceSpeeds: {},
          storedDocumentCastVoiceAssignments: {},
          characterSnapshot: owner.snapshot(),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey('reader.storedDocumentCastVoiceAssignments'),
          isFalse,
        );
        final restored = (await service.load()).characterSnapshot!.restore();
        restored.migrateLegacy(initial.storedDocumentCastVoiceAssignments);
        expect(
          restored.character('canonical', 'cast_narrator')!.selectedVoice.mode,
          VoiceSelectionMode.automatic,
        );
        expect(
          restored
              .character('canonical', 'cast_narrator')!
              .selectedVoice
              .revision,
          2,
        );
      },
    );

    test(
      'VS18 unreadable future character storage is preserved and cannot be overwritten by defaults',
      () async {
        const text = '{"schema":999,"valuable":"future data"}';
        SharedPreferences.setMockInitialValues({
          'reader.workCharacters.v1': text,
        });
        final service = ReaderPreferencesService();
        await expectLater(service.load(), throwsFormatException);
        await expectLater(
          service.save(
            fontFamily: 'serif',
            fontScale: 1,
            appearanceMode: ReaderAppearanceMode.system,
            multiVoiceEnabled: true,
            voiceSpeeds: {},
            storedDocumentCastVoiceAssignments: {},
            characterSnapshot: WorkCharacterStore().snapshot(),
          ),
          throwsStateError,
        );
        expect(
          (await SharedPreferences.getInstance()).getString(
            'reader.workCharacters.v1',
          ),
          text,
        );
      },
    );
    test('persists the selected Voxtral precision', () async {
      final service = ReaderPreferencesService();
      for (final bits in [4, 0]) {
        await service.save(
          voxtralQuantizationBits: bits,
          fontFamily: ReaderPreferences.defaultFontFamily,
          fontScale: 1,
          appearanceMode: ReaderAppearanceMode.system,
          multiVoiceEnabled: true,
          voiceSpeeds: {},
          storedDocumentCastVoiceAssignments: {},
        );
        expect((await service.load()).voxtralQuantizationBits, bits);
      }
    });
    test('loads defaults when no preferences are stored', () async {
      final service = ReaderPreferencesService();
      final preferences = await service.load();

      expect(preferences.voxtralQuantizationBits, 0);

      expect(preferences.fontFamily, ReaderPreferences.defaultFontFamily);
      expect(preferences.fontScale, ReaderPreferences.defaultFontScale);
      expect(preferences.appearanceMode, ReaderAppearanceMode.system);
      expect(
        preferences.multiVoiceEnabled,
        ReaderPreferences.defaultMultiVoiceEnabled,
      );
      expect(preferences.selectedVoiceId, isNull);
      expect(preferences.voiceSpeeds, isEmpty);
      expect(preferences.storedDocumentCastVoiceAssignments, isEmpty);
      expect(preferences.sourceVoiceDocumentIds, isEmpty);
      expect(preferences.resumeState, isNull);
      expect(preferences.lastOpenedDocumentPath, isNull);
      expect(preferences.lastOpenedDocumentAccessToken, isNull);
      expect(preferences.lastOpenedDirectoryPath, isNull);
      expect(preferences.lastOpenedDirectoryAccessToken, isNull);
    });

    test('persists last opened document and folder paths', () async {
      final service = ReaderPreferencesService();

      await service.save(
        selectedVoiceId: 'af_bella',
        sourceVoiceDocumentIds: const {'source-revision': 'doc_love'},
        voiceSpeeds: const <String, double>{'af_bella': 1.15},
        fontFamily: 'sans-serif',
        fontScale: 1.2,
        appearanceMode: ReaderAppearanceMode.dark,
        multiVoiceEnabled: false,
        storedDocumentCastVoiceAssignments: const <String, Map<String, String>>{
          'doc_love': <String, String>{
            'cast_narrator': 'af_heart',
            'cast_character_jennifer': 'am_michael',
          },
        },
        resumeState: const ReaderResumeState(
          documentPath: '/tmp/books/love.txt',
          wordIndex: 42,
          wordIndexWithinSegment: 3,
          segmentTextAnchor: 'A remembered sentence anchor.',
          anchorWordText: 'sentence',
        ),
        lastOpenedDocumentPath: '/tmp/books/love.txt',
        lastOpenedDocumentAccessToken: 'bookmark-token',
        lastOpenedDirectoryPath: '/tmp/books',
        lastOpenedDirectoryAccessToken: 'folder-bookmark-token',
      );

      final preferences = await service.load();
      expect(preferences.selectedVoiceId, 'af_bella');
      expect(preferences.sourceVoiceDocumentIds, {
        'source-revision': 'doc_love',
      });
      expect(preferences.voiceSpeeds['af_bella'], 1.15);
      expect(preferences.fontFamily, 'sans-serif');
      expect(preferences.fontScale, 1.2);
      expect(preferences.appearanceMode, ReaderAppearanceMode.dark);
      expect(preferences.multiVoiceEnabled, isFalse);
      expect(
        preferences.storedDocumentCastVoiceAssignments,
        const <String, Map<String, String>>{
          'doc_love': <String, String>{
            'cast_narrator': 'af_heart',
            'cast_character_jennifer': 'am_michael',
          },
        },
      );
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
      expect(preferences.lastOpenedDocumentAccessToken, 'bookmark-token');
      expect(preferences.lastOpenedDirectoryPath, '/tmp/books');
      expect(
        preferences.lastOpenedDirectoryAccessToken,
        'folder-bookmark-token',
      );
    });
  });
}
