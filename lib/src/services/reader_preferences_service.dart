import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'work_character_repository.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_appearance_mode.dart';
import '../models/reader_resume_state.dart';
import 'work_character_store.dart';

class ReaderPreferences {
  const ReaderPreferences({
    this.ttsEngineId = '',
    this.voxtralQuantizationBits = 0,
    required this.fontFamily,
    required this.fontScale,
    required this.appearanceMode,
    required this.multiVoiceEnabled,
    required this.voiceSpeeds,
    required this.storedDocumentCastVoiceAssignments,
    this.sourceVoiceDocumentIds = const {},
    this.characterSnapshot,
    this.resumeState,
    this.selectedVoiceId,
    this.narratorVoiceIds = const {},
    this.lastOpenedDocumentPath,
    this.lastOpenedDocumentAccessToken,
    this.lastOpenedDirectoryPath,
    this.lastOpenedDirectoryAccessToken,
  });

  static const String defaultFontFamily = 'serif';
  static const double defaultFontScale = 1.0;
  static const bool defaultMultiVoiceEnabled = true;
  static const String defaultTtsEngineId = 'kokoro';

  final String ttsEngineId;

  /// Empty means no user selection; an automatic effective default is not intent.
  bool get hasExplicitTtsEngineChoice => ttsEngineId.isNotEmpty;
  final int voxtralQuantizationBits;
  final String fontFamily;
  final double fontScale;
  final ReaderAppearanceMode appearanceMode;
  final bool multiVoiceEnabled;
  final String? selectedVoiceId;
  final Map<String, String> narratorVoiceIds;
  final Map<String, double> voiceSpeeds;
  final Map<String, Map<String, String>> storedDocumentCastVoiceAssignments;

  /// Exact source revisions map to the preference owner, independently of the
  /// temporary document IDs used while an unfinished book is being prepared.
  final Map<String, String> sourceVoiceDocumentIds;
  final CharacterStoreSnapshot? characterSnapshot;
  final ReaderResumeState? resumeState;
  final String? lastOpenedDocumentPath;
  final String? lastOpenedDocumentAccessToken;
  final String? lastOpenedDirectoryPath;
  final String? lastOpenedDirectoryAccessToken;
}

class ReaderPreferencesService {
  ReaderPreferencesService({WorkCharacterRepository? workRepository})
    : _providedRepository = workRepository;
  final WorkCharacterRepository? _providedRepository;
  Future<WorkCharacterRepository>? _repositoryFuture;
  StoredWorkCharacters? _workState;
  Future<WorkCharacterRepository> _repository() =>
      _repositoryFuture ??= () async {
        if (_providedRepository != null) return _providedRepository;
        final support = await getApplicationSupportDirectory();
        return WorkCharacterRepository(p.join(support.path, 'works'));
      }();

  Future<StoredWorkCharacters> _loadWorks(SharedPreferences preferences) async {
    try {
      final repository = await _repository();
      final state = await repository.load(
        legacyCharacters: preferences.getString(_characterSnapshotKey),
        legacyChoices: preferences.getString(
          _storedDocumentCastVoiceAssignmentsKey,
        ),
        legacySourceIds: preferences.getString(_sourceVoiceDocumentIdsKey),
      );
      // The repository's validated completion marker makes retries authoritative
      // even if a process exits halfway through retiring these legacy keys.
      for (final key in [
        _characterSnapshotKey,
        _storedDocumentCastVoiceAssignmentsKey,
        _sourceVoiceDocumentIdsKey,
      ]) {
        if (preferences.containsKey(key) && !await preferences.remove(key)) {
          throw StateError(
            'Could not retire migrated character preference $key',
          );
        }
      }
      _characterLoadError = null;
      return _workState = state;
    } catch (error) {
      _characterLoadError = error;
      rethrow;
    }
  }

  static const _narratorVoiceIdsKey = 'reader.narratorVoiceIds.v1';
  static const _voxtralBitsKey = 'reader.voxtralQuantizationBits';
  static const String _selectedVoiceIdKey = 'reader.selectedVoiceId';
  static const String _ttsEngineIdKey = 'reader.ttsEngineId';
  static const String _voiceSpeedsKey = 'reader.voiceSpeeds';
  static const String _fontFamilyKey = 'reader.fontFamily';
  static const String _fontScaleKey = 'reader.fontScale';
  static const String _appearanceModeKey = 'reader.appearanceMode';
  static const String _multiVoiceEnabledKey = 'reader.multiVoiceEnabled';
  static const String _resumeStateKey = 'reader.resumeState';
  static const String _storedDocumentCastVoiceAssignmentsKey =
      'reader.storedDocumentCastVoiceAssignments';
  static const _sourceVoiceDocumentIdsKey = 'reader.sourceVoiceDocumentIds';
  static const _characterSnapshotKey = 'reader.workCharacters.v1';
  static const String _lastOpenedDocumentPathKey =
      'reader.lastOpenedDocumentPath';
  static const String _lastOpenedDocumentAccessTokenKey =
      'reader.lastOpenedDocumentAccessToken';
  static const String _lastOpenedDirectoryPathKey =
      'reader.lastOpenedDirectoryPath';
  static const String _lastOpenedDirectoryAccessTokenKey =
      'reader.lastOpenedDirectoryAccessToken';

  Object? _characterLoadError;

  Future<ReaderPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    final workState = await _loadWorks(preferences);
    final snapshot = workState.snapshot;
    final characters = snapshot.restore();
    return ReaderPreferences(
      voxtralQuantizationBits: preferences.getInt(_voxtralBitsKey) == 4 ? 4 : 0,
      ttsEngineId: preferences.getString(_ttsEngineIdKey) ?? '',
      selectedVoiceId: preferences.getString(_selectedVoiceIdKey),
      narratorVoiceIds: _decodeNarratorVoiceIds(
        preferences.getString(_narratorVoiceIdsKey),
      ),
      voiceSpeeds: _decodeVoiceSpeeds(preferences.getString(_voiceSpeedsKey)),
      fontFamily:
          preferences.getString(_fontFamilyKey) ??
          ReaderPreferences.defaultFontFamily,
      fontScale:
          preferences.getDouble(_fontScaleKey) ??
          ReaderPreferences.defaultFontScale,
      appearanceMode: ReaderAppearanceMode.fromStorageValue(
        preferences.getString(_appearanceModeKey),
      ),
      multiVoiceEnabled:
          preferences.getBool(_multiVoiceEnabledKey) ??
          ReaderPreferences.defaultMultiVoiceEnabled,
      storedDocumentCastVoiceAssignments: characters.legacySelections,
      characterSnapshot: snapshot,
      sourceVoiceDocumentIds: workState.sourceIds,
      resumeState: _decodeResumeState(preferences.getString(_resumeStateKey)),
      lastOpenedDocumentPath: preferences.getString(_lastOpenedDocumentPathKey),
      lastOpenedDocumentAccessToken: preferences.getString(
        _lastOpenedDocumentAccessTokenKey,
      ),
      lastOpenedDirectoryPath: preferences.getString(
        _lastOpenedDirectoryPathKey,
      ),
      lastOpenedDirectoryAccessToken: preferences.getString(
        _lastOpenedDirectoryAccessTokenKey,
      ),
    );
  }

  Future<void> save({
    int voxtralQuantizationBits = 0,
    String ttsEngineId = '',
    required String fontFamily,
    required double fontScale,
    required ReaderAppearanceMode appearanceMode,
    required bool multiVoiceEnabled,
    required Map<String, double> voiceSpeeds,
    required Map<String, Map<String, String>>
    storedDocumentCastVoiceAssignments,
    Map<String, String> sourceVoiceDocumentIds = const {},
    CharacterStoreSnapshot? characterSnapshot,
    ReaderResumeState? resumeState,
    String? selectedVoiceId,
    Map<String, String> narratorVoiceIds = const {},
    String? lastOpenedDocumentPath,
    String? lastOpenedDocumentAccessToken,
    String? lastOpenedDirectoryPath,
    String? lastOpenedDirectoryAccessToken,
  }) async {
    if (_characterLoadError != null) {
      throw StateError(
        'Character storage could not be read; preserving it: $_characterLoadError',
      );
    }
    final preferences = await SharedPreferences.getInstance();

    await preferences.setInt(_voxtralBitsKey, voxtralQuantizationBits);
    await preferences.setString(
      _narratorVoiceIdsKey,
      jsonEncode(narratorVoiceIds),
    );

    if (selectedVoiceId == null || selectedVoiceId.isEmpty) {
      await preferences.remove(_selectedVoiceIdKey);
    } else {
      await preferences.setString(_selectedVoiceIdKey, selectedVoiceId);
    }

    if (ttsEngineId.isEmpty) {
      await preferences.remove(_ttsEngineIdKey);
    } else {
      await preferences.setString(_ttsEngineIdKey, ttsEngineId);
    }

    await preferences.setString(_fontFamilyKey, fontFamily);
    await preferences.setDouble(_fontScaleKey, fontScale);
    await preferences.setString(
      _appearanceModeKey,
      appearanceMode.storageValue,
    );
    await preferences.setBool(_multiVoiceEnabledKey, multiVoiceEnabled);
    await preferences.setString(_voiceSpeedsKey, jsonEncode(voiceSpeeds));
    final previous = _workState ?? await _loadWorks(preferences);
    final snapshot =
        characterSnapshot ??
        (previous.snapshot.restore()
              ..migrateLegacy(storedDocumentCastVoiceAssignments))
            .snapshot();
    await (await _repository()).save(snapshot, sourceVoiceDocumentIds);
    _workState = StoredWorkCharacters(snapshot, sourceVoiceDocumentIds);
    if (resumeState == null) {
      await preferences.remove(_resumeStateKey);
    } else {
      await preferences.setString(
        _resumeStateKey,
        jsonEncode(resumeState.toJson()),
      );
    }

    if (lastOpenedDocumentPath == null || lastOpenedDocumentPath.isEmpty) {
      await preferences.remove(_lastOpenedDocumentPathKey);
    } else {
      await preferences.setString(
        _lastOpenedDocumentPathKey,
        lastOpenedDocumentPath,
      );
    }

    if (lastOpenedDocumentAccessToken == null ||
        lastOpenedDocumentAccessToken.isEmpty) {
      await preferences.remove(_lastOpenedDocumentAccessTokenKey);
    } else {
      await preferences.setString(
        _lastOpenedDocumentAccessTokenKey,
        lastOpenedDocumentAccessToken,
      );
    }

    if (lastOpenedDirectoryPath == null || lastOpenedDirectoryPath.isEmpty) {
      await preferences.remove(_lastOpenedDirectoryPathKey);
    } else {
      await preferences.setString(
        _lastOpenedDirectoryPathKey,
        lastOpenedDirectoryPath,
      );
    }

    if (lastOpenedDirectoryAccessToken == null ||
        lastOpenedDirectoryAccessToken.isEmpty) {
      await preferences.remove(_lastOpenedDirectoryAccessTokenKey);
    } else {
      await preferences.setString(
        _lastOpenedDirectoryAccessTokenKey,
        lastOpenedDirectoryAccessToken,
      );
    }
  }

  Map<String, String> _decodeNarratorVoiceIds(String? raw) {
    try {
      final value = jsonDecode(raw ?? '{}');
      if (value is! Map<String, dynamic>) return {};
      return {
        for (final entry in value.entries)
          if (entry.key.isNotEmpty &&
              entry.value is String &&
              (entry.value as String).isNotEmpty)
            entry.key: entry.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Map<String, double> _decodeVoiceSpeeds(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) {
      return <String, double>{};
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map<String, dynamic>) {
        return <String, double>{};
      }

      final voiceSpeeds = <String, double>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value is num && key.isNotEmpty) {
          voiceSpeeds[key] = value.toDouble();
        }
      }
      return voiceSpeeds;
    } catch (_) {
      return <String, double>{};
    }
  }

  ReaderResumeState? _decodeResumeState(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    try {
      return ReaderResumeState.fromJson(jsonDecode(rawValue));
    } catch (_) {
      return null;
    }
  }
}
