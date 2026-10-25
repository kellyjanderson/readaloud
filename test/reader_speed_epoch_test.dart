import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Public controller contract only; no PCM generation or private planner injection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'above-supported rate is normalized before plan, synthesis and export',
    () async {
      final engine = _RateLimitedEngine();
      final controller = ReaderController(
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.startPlayback();
      await controller.setVoiceSpeed(1.5);
      expect(controller.currentSpeed, 1.4);
      expect(engine.ratesAtSpeak.last, 1.4);
      expect(engine.requests.last.planningContext!.realization.rate, 1.4);
      final keys = engine.requests.last.chunkPlan!.chunks
          .map((c) => c.cacheKey)
          .toList();
      await controller.setVoiceSpeed(1.4);
      expect(engine.requests.last.planningContext!.realization.rate, 1.4);
      expect(
        engine.requests.last.chunkPlan!.chunks.map((c) => c.cacheKey),
        keys,
      );
      final export = await controller.exportAudioToPath(
        '/tmp/effective-rate.wav',
      );
      expect(export?.rate, 1.4);
      expect(engine.exports.single.planningContext!.realization.rate, 1.4);
    },
  );

  test(
    'buffering speed edit restarts with coherent new rate and plan',
    () async {
      final engine = _RateEngine();
      final controller = ReaderController(
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.startPlayback();
      final original = engine.requests.single;
      final originalRate = original.planningContext!.realization.rate;
      final originalKeys = original.chunkPlan!.chunks
          .map((c) => c.cacheKey)
          .toList();
      expect(controller.isPlaying, isFalse);
      expect(controller.playbackActivity.isBuffering, isTrue);
      final stops = engine.stops;
      await controller.setVoiceSpeed(1.25);
      expect(engine.stops, greaterThan(stops));
      expect(engine.requests, hasLength(2));
      final current = engine.requests.last;
      expect(current.planningContext!.realization.rate, 1.25);
      expect(engine.ratesAtSpeak.last, 1.25);
      expect(current.documentId, original.documentId);
      expect(
        current.chunkPlan!.chunks.map((c) => c.cacheKey),
        isNot(originalKeys),
      );
      expect(original.planningContext!.realization.rate, originalRate);
      expect(original.chunkPlan!.chunks.map((c) => c.cacheKey), originalKeys);
      expect(
        current.chunkPlan!.chunks.first.startWordIndex,
        original.chunkPlan!.chunks.first.startWordIndex,
      );
    },
  );

  test(
    'new rate cannot dispatch while old buffering owner stop is pending',
    () async {
      final engine = _RateEngine();
      final controller = ReaderController(
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.startPlayback();
      final stop = _StopBarrier();
      engine.nextStop = stop;
      final change = controller.setVoiceSpeed(1.3);
      await stop.started.future.timeout(const Duration(seconds: 2));
      expect(engine.requests, hasLength(1));
      stop.release.complete();
      await change;
      expect(engine.requests, hasLength(2));
      expect(engine.requests.last.planningContext!.realization.rate, 1.3);
      expect(engine.ratesAtSpeak.last, 1.3);
    },
  );
}

class _RateLimitedEngine extends _RateEngine
    implements SpeechRateNormalizationCapable, AudioExportCapable {
  final exports = <TtsExportRequest>[];
  @override
  double normalizeSpeechRate(double requested) =>
      kokoroNormalizeSpeechRate(requested);
  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    exports.add(request);
    return TtsExportResult(
      outputPath: request.outputPath,
      sidecarPath: '${request.outputPath}.json',
      duration: const Duration(seconds: 1),
      chunkCount: 1,
      voiceId: 'af_bella',
      rate: request.planningContext!.realization.rate,
      engineId: 'kokoro',
      engineVersion: 'test',
    );
  }
}

class _StopBarrier {
  final started = Completer<void>();
  final release = Completer<void>();
}

class _RateEngine implements TtsEngine {
  static const voice = VoiceProfile(
    id: 'af_bella',
    label: 'Bella',
    locale: 'en-US',
    rawValue: {'name': 'Bella', 'locale': 'en-US'},
  );
  final requests = <TtsSpeakRequest>[];
  final ratesAtSpeak = <double>[];
  double rate = 1;
  int stops = 0;
  _StopBarrier? nextStop;
  void Function(TtsPlaybackActivity)? activity;
  @override
  Future<void> initialize() async {}
  @override
  Future<List<VoiceProfile>> loadVoices() async => [voice];
  @override
  Future<void> selectVoice(VoiceProfile voice) async {}
  @override
  Future<void> setSpeechRate(double multiplier) async {
    rate = multiplier;
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> speak(TtsSpeakRequest request) async {
    requests.add(request);
    ratesAtSpeak.add(rate);
    activity?.call(
      const TtsPlaybackActivity(phase: TtsPlaybackPhase.buffering),
    );
  }

  @override
  Future<void> stop() async {
    ++stops;
    final barrier = nextStop;
    nextStop = null;
    if (barrier != null) {
      barrier.started.complete();
      await barrier.release.future;
    }
    activity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  Future<void> pause() async {}
  @override
  void dispose() {}
  @override
  set onActivity(void Function(TtsPlaybackActivity activity)? callback) =>
      activity = callback;
  @override
  set onStart(void Function()? callback) {}
  @override
  set onStatus(void Function(String? message)? callback) {}
  @override
  set onProgress(void Function(TtsProgressUpdate update)? callback) {}
  @override
  set onComplete(void Function()? callback) {}
  @override
  set onError(void Function(String message)? callback) {}
  @override
  set onDebugTrace(void Function(TtsDebugTraceSnapshot trace)? callback) {}
}
