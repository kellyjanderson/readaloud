import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A bounded, request-owned macOS activity. It requests timing/I/O precision
/// during speech work and permits idle system sleep. It changes no preferences.
class NativeSpeechWorkActivity {
  NativeSpeechWorkActivity._(this._owner);
  static const _channel = MethodChannel('read_aloud/mlx_tts_lifecycle');
  static int _sequence = 0;
  final String? _owner;
  Future<void>? _released;

  static Future<NativeSpeechWorkActivity> begin() async {
    if (!Platform.isMacOS ||
        defaultTargetPlatform != TargetPlatform.macOS ||
        Platform.environment['READALOUD_DISABLE_SPEECH_ACTIVITY'] == '1') {
      return NativeSpeechWorkActivity._(null);
    }
    final owner =
        'speech_${DateTime.now().microsecondsSinceEpoch}_${++_sequence}';
    try {
      await _channel.invokeMethod<void>('beginSpeechWork', {'owner': owner});
      return NativeSpeechWorkActivity._(owner);
    } on MissingPluginException {
      // Platform-free tests and older platform hosts cannot supply activities.
      // Native acceptance separately verifies the current host's activity count.
      return NativeSpeechWorkActivity._(null);
    }
  }

  Future<void> release() => _released ??= _release();
  static Future<Map<String, Object?>?> snapshot() async {
    if (!Platform.isMacOS) return null;
    try {
      return await _channel.invokeMapMethod<String, Object?>(
        'speechWorkActivitySnapshot',
      );
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _release() async {
    if (_owner != null) {
      await _channel.invokeMethod<void>('endSpeechWork', {'owner': _owner});
    }
  }
}
