import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/voice_profile.dart';
import 'tts_engine.dart';

class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine() : _tts = FlutterTts();

  final FlutterTts _tts;

  void Function()? _onStart;
  void Function(String? message)? _onStatus;
  void Function(TtsProgressUpdate update)? _onProgress;
  void Function()? _onComplete;
  void Function(String message)? _onError;
  void Function(TtsPlaybackActivity activity)? _onActivity;

  @override
  set onStart(void Function()? callback) => _onStart = callback;

  @override
  set onStatus(void Function(String? message)? callback) =>
      _onStatus = callback;

  @override
  set onProgress(void Function(TtsProgressUpdate update)? callback) =>
      _onProgress = callback;

  @override
  set onComplete(void Function()? callback) => _onComplete = callback;

  @override
  set onError(void Function(String message)? callback) => _onError = callback;

  @override
  set onActivity(void Function(TtsPlaybackActivity activity)? callback) =>
      _onActivity = callback;

  @override
  set onDebugTrace(void Function(TtsDebugTraceSnapshot trace)? callback) {}

  @override
  Future<void> initialize() async {
    _onStatus?.call(null);
    _onActivity?.call(const TtsPlaybackActivity.idle());
    _tts.setStartHandler(() {
      _onActivity?.call(
        const TtsPlaybackActivity(phase: TtsPlaybackPhase.playing),
      );
      _onStart?.call();
    });
    _tts.setCompletionHandler(() {
      _onActivity?.call(const TtsPlaybackActivity.idle());
      _onComplete?.call();
    });
    _tts.setCancelHandler(() {
      _onActivity?.call(const TtsPlaybackActivity.idle());
      _onComplete?.call();
    });
    _tts.setErrorHandler((message) {
      _onActivity?.call(const TtsPlaybackActivity.idle());
      _onError?.call(message);
    });
    _tts.setProgressHandler((_, startOffset, endOffset, word) {
      _onProgress?.call(
        TtsProgressUpdate(
          startOffset: startOffset,
          endOffset: endOffset,
          word: word,
        ),
      );
    });

    try {
      await _tts.setSharedInstance(true);
    } catch (_) {
      // Platform-specific optional configuration.
    }
  }

  @override
  Future<List<VoiceProfile>> loadVoices() async {
    try {
      final dynamic rawVoices = await _tts.getVoices;
      final voices = <VoiceProfile>[];
      if (rawVoices is List) {
        for (final voice in rawVoices) {
          if (voice is Map) {
            voices.add(VoiceProfile.fromPlatformMap(voice));
          }
        }
      }
      voices.sort((a, b) => a.displayName.compareTo(b.displayName));
      return voices;
    } on MissingPluginException {
      return const <VoiceProfile>[];
    }
  }

  @override
  Future<void> selectVoice(VoiceProfile voice) async {
    try {
      await _tts.setVoice(
        voice.rawValue.map((key, value) {
          return MapEntry(key, value.toString());
        }),
      );
    } on MissingPluginException {
      // Leave voice unavailable on unsupported platforms.
    }
  }

  @override
  Future<void> setSpeechRate(double multiplier) async {
    final normalizedRate = (multiplier / 2).clamp(0.25, 0.8);
    try {
      await _tts.setSpeechRate(normalizedRate);
    } on MissingPluginException {
      // Unsupported platform.
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _tts.setVolume(volume.clamp(0.0, 1.0));
    } on MissingPluginException {
      // Unsupported platform.
    }
  }

  @override
  Future<void> speak(TtsSpeakRequest request) async {
    try {
      _onActivity?.call(
        const TtsPlaybackActivity(phase: TtsPlaybackPhase.buffering),
      );
      await _tts.speak(request.text);
    } on MissingPluginException {
      _onActivity?.call(const TtsPlaybackActivity.idle());
      _onError?.call('Text to speech is unavailable on this platform.');
    }
  }

  @override
  Future<void> pause() async {
    try {
      _onActivity?.call(const TtsPlaybackActivity.idle());
      if (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.windows) {
        await _tts.pause();
        return;
      }
      await _tts.stop();
    } on MissingPluginException {
      _onError?.call('Text to speech is unavailable on this platform.');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
      _onActivity?.call(const TtsPlaybackActivity.idle());
    } on MissingPluginException {
      _onActivity?.call(const TtsPlaybackActivity.idle());
      _onError?.call('Text to speech is unavailable on this platform.');
    }
  }

  @override
  void dispose() {
    _tts.stop();
  }
}
