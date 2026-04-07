import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_appearance_mode.dart';
import '../models/reader_resume_state.dart';

class ReaderPreferences {
  const ReaderPreferences({
    required this.fontFamily,
    required this.fontScale,
    required this.appearanceMode,
    required this.multiVoiceEnabled,
    required this.voiceSpeeds,
    this.resumeState,
    this.selectedVoiceId,
    this.lastOpenedDocumentPath,
    this.lastOpenedDirectoryPath,
  });

  static const String defaultFontFamily = 'serif';
  static const double defaultFontScale = 1.0;
  static const bool defaultMultiVoiceEnabled = true;

  final String fontFamily;
  final double fontScale;
  final ReaderAppearanceMode appearanceMode;
  final bool multiVoiceEnabled;
  final String? selectedVoiceId;
  final Map<String, double> voiceSpeeds;
  final ReaderResumeState? resumeState;
  final String? lastOpenedDocumentPath;
  final String? lastOpenedDirectoryPath;
}

class ReaderPreferencesService {
  static const String _selectedVoiceIdKey = 'reader.selectedVoiceId';
  static const String _voiceSpeedsKey = 'reader.voiceSpeeds';
  static const String _fontFamilyKey = 'reader.fontFamily';
  static const String _fontScaleKey = 'reader.fontScale';
  static const String _appearanceModeKey = 'reader.appearanceMode';
  static const String _multiVoiceEnabledKey = 'reader.multiVoiceEnabled';
  static const String _resumeStateKey = 'reader.resumeState';
  static const String _lastOpenedDocumentPathKey =
      'reader.lastOpenedDocumentPath';
  static const String _lastOpenedDirectoryPathKey =
      'reader.lastOpenedDirectoryPath';

  Future<ReaderPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    return ReaderPreferences(
      selectedVoiceId: preferences.getString(_selectedVoiceIdKey),
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
      resumeState: _decodeResumeState(preferences.getString(_resumeStateKey)),
      lastOpenedDocumentPath: preferences.getString(_lastOpenedDocumentPathKey),
      lastOpenedDirectoryPath: preferences.getString(
        _lastOpenedDirectoryPathKey,
      ),
    );
  }

  Future<void> save({
    required String fontFamily,
    required double fontScale,
    required ReaderAppearanceMode appearanceMode,
    required bool multiVoiceEnabled,
    required Map<String, double> voiceSpeeds,
    ReaderResumeState? resumeState,
    String? selectedVoiceId,
    String? lastOpenedDocumentPath,
    String? lastOpenedDirectoryPath,
  }) async {
    final preferences = await SharedPreferences.getInstance();

    if (selectedVoiceId == null || selectedVoiceId.isEmpty) {
      await preferences.remove(_selectedVoiceIdKey);
    } else {
      await preferences.setString(_selectedVoiceIdKey, selectedVoiceId);
    }

    await preferences.setString(_fontFamilyKey, fontFamily);
    await preferences.setDouble(_fontScaleKey, fontScale);
    await preferences.setString(_appearanceModeKey, appearanceMode.storageValue);
    await preferences.setBool(_multiVoiceEnabledKey, multiVoiceEnabled);
    await preferences.setString(_voiceSpeedsKey, jsonEncode(voiceSpeeds));
    if (resumeState == null) {
      await preferences.remove(_resumeStateKey);
    } else {
      await preferences.setString(_resumeStateKey, jsonEncode(resumeState.toJson()));
    }

    if (lastOpenedDocumentPath == null || lastOpenedDocumentPath.isEmpty) {
      await preferences.remove(_lastOpenedDocumentPathKey);
    } else {
      await preferences.setString(
        _lastOpenedDocumentPathKey,
        lastOpenedDocumentPath,
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
