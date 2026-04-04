import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/spoken_chunk_record.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';
import 'dart:io';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PlaybackInstrumentationService.instance.clear();
  });

  group('ReaderController playback', () {
    test('tracks primary playback state through buffering, playing, and completion', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText('Alpha beta. Gamma delta.');
      await controller.startPlayback();

      expect(
        controller.playbackState,
        ReaderPlaybackPrimaryState.bufferingFirstChunk,
      );
      expect(controller.statusMessage, isNull);

      engine.emitStart();
      expect(controller.playbackState, ReaderPlaybackPrimaryState.playing);

      final documentId = controller.document.displayDocument.documentId;
      final lastSegment = controller.document.speechDocument.segments.last;
      engine.emitProgress(
        TtsProgressUpdate(
          startOffset: 0,
          endOffset: controller.document.speakableText.length,
          word: 'delta',
          documentId: documentId,
          chunkId: 'chunk-complete',
          segmentId: lastSegment.segmentId,
          wordStartIndex: controller.document.wordCount - 1,
          wordEndIndex: controller.document.wordCount,
          elapsedInChunk: const Duration(seconds: 2),
          chunkAudioDuration: const Duration(seconds: 2),
          voiceId: controller.selectedVoice!.id,
          rate: controller.currentSpeed,
        ),
      );
      engine.emitComplete();

      expect(controller.playbackState, ReaderPlaybackPrimaryState.completed);
    });

    test('uses completed chunk records for timing and snaps jumps to segment starts', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText(
        'Alpha beta. Gamma delta. Epsilon zeta.',
      );
      await controller.startPlayback();
      engine.emitStart();

      final documentId = controller.document.displayDocument.documentId;
      final segments = controller.document.speechDocument.segments;
      final voiceId = controller.selectedVoice!.id;

      engine.emitProgress(
        TtsProgressUpdate(
          startOffset: 0,
          endOffset: 10,
          word: 'beta',
          documentId: documentId,
          chunkId: 'chunk-1',
          segmentId: segments[0].segmentId,
          wordStartIndex: 0,
          wordEndIndex: 2,
          elapsedInChunk: const Duration(seconds: 2),
          chunkAudioDuration: const Duration(seconds: 2),
          voiceId: voiceId,
          rate: controller.currentSpeed,
          routeId: 'route_narration_open',
          castId: 'cast_narrator',
        ),
      );
      engine.emitProgress(
        TtsProgressUpdate(
          startOffset: 11,
          endOffset: 22,
          word: 'delta',
          documentId: documentId,
          chunkId: 'chunk-2',
          segmentId: segments[1].segmentId,
          wordStartIndex: 2,
          wordEndIndex: 4,
          elapsedInChunk: const Duration(seconds: 2),
          chunkAudioDuration: const Duration(seconds: 2),
          voiceId: voiceId,
          rate: controller.currentSpeed,
          routeId: 'route_dialogue_jennifer',
          castId: 'cast_character_jennifer',
          dialogueSpanId: 'dlg_s_1',
        ),
      );

      expect(controller.wordsPerSecond, closeTo(1.0, 0.001));
      expect(
        controller.spokenChunkRecords.any((record) => record.chunkId == 'chunk-1' && record.completed),
        isTrue,
      );
      final dialogueRecord = controller.spokenChunkRecords.firstWhere(
        (record) => record.chunkId == 'chunk-2',
      );
      expect(dialogueRecord.routeId, 'route_dialogue_jennifer');
      expect(dialogueRecord.castId, 'cast_character_jennifer');
      expect(dialogueRecord.dialogueSpanId, 'dlg_s_1');

      await controller.jumpBySeconds(-1);

      expect(controller.currentWordIndex, 2);
    });

    test('records debug playback metrics with session attribution', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText('Alpha beta. Gamma delta.');
      final sessionId = controller.narrationState.sessionId;
      final documentId = controller.document.displayDocument.documentId;

      await controller.startPlayback();

      final metricsAfterPlay = PlaybackInstrumentationService.instance.snapshot();
      final positionMetric = metricsAfterPlay.firstWhere(
        (record) => record.metric == 'positionMapConfidence',
      );
      expect(positionMetric.documentId, documentId);
      expect(positionMetric.sessionId, sessionId);
      expect(positionMetric.voiceId, controller.selectedVoice!.id);
      expect(positionMetric.engineId, 'generic');

      engine.emitStart();

      final metricsAfterStart = PlaybackInstrumentationService.instance
          .snapshot();
      final latencyMetric = metricsAfterStart.firstWhere(
        (record) => record.metric == 'firstAudioLatencyMs',
      );
      expect(latencyMetric.documentId, documentId);
      expect(latencyMetric.sessionId, sessionId);
      expect(latencyMetric.voiceId, controller.selectedVoice!.id);
      expect(latencyMetric.engineId, 'generic');
      expect(latencyMetric.value, isA<int>());
    });

    test('restores the last opened document from preferences', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-restore-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/remembered.txt');
      await file.writeAsString('Restored documents should open by default.');

      SharedPreferences.setMockInitialValues(<String, Object>{
        'reader.lastOpenedDocumentPath': file.path,
        'reader.lastOpenedDirectoryPath': tempDir.path,
      });

      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      final restored = await controller.restoreLastOpenedDocument();

      expect(restored, isTrue);
      expect(controller.document.title, 'remembered.txt');
      expect(
        controller.document.speakableText,
        contains('Restored documents should open by default.'),
      );
      expect(controller.statusMessage, 'Restored remembered.txt.');
    });

    test('surfaces debug phoneme trace snapshots from the engine', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();

      engine.emitDebugTrace(
        TtsDebugTraceSnapshot(
          logPath: '/tmp/2026-04-03T01-45-00_af_bella.log',
          startedAt: DateTime.utc(2026, 4, 3, 1, 45),
          voiceId: 'af_bella',
          recentLines: <String>[
            'voiceId: af_bella',
            'trace: plainText text=\"for the road\" prepared=\"for the road\" phonemes=\"fˈɔɹ ðə ɹˈoʊd\"',
          ],
          sessionId: 'session_debug',
        ),
      );

      expect(
        controller.ttsDebugTraceLogPath,
        '/tmp/2026-04-03T01-45-00_af_bella.log',
      );
      expect(controller.ttsDebugTraceVoiceId, 'af_bella');
      expect(
        controller.ttsDebugTraceLines.last,
        contains('phonemes=\"fˈɔɹ ðə ɹˈoʊd\"'),
      );
    });

    test('live read mode reloads the watched file in place', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-live-read-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/live.txt');
      await file.writeAsString('Alpha beta.');

      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.startLiveReadFromPath(file.path);

      expect(controller.isLiveReadEnabled, isTrue);
      expect(controller.liveReadFilePath, file.path);
      expect(controller.document.title, 'live.txt');
      expect(controller.document.speakableText, contains('Alpha beta.'));

      await file.writeAsString('Gamma delta.');

      for (var attempt = 0; attempt < 20; attempt += 1) {
        if (controller.document.speakableText.contains('Gamma delta.')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(controller.document.speakableText, contains('Gamma delta.'));
      expect(controller.statusMessage, contains('Live read updated'));
    });
  });
}

class _FakeTtsEngine implements TtsEngine {
  final List<VoiceProfile> _voices = const <VoiceProfile>[
    VoiceProfile(
      id: 'af_bella',
      label: 'Bella',
      locale: 'en-US',
      rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
    ),
  ];

  void Function()? _onStart;
  void Function(String? message)? _onStatus;
  void Function(TtsProgressUpdate update)? _onProgress;
  void Function()? _onComplete;
  void Function(String message)? _onError;
  void Function(TtsPlaybackActivity activity)? _onActivity;
  void Function(TtsDebugTraceSnapshot trace)? _onDebugTrace;

  @override
  set onStart(void Function()? callback) => _onStart = callback;

  @override
  set onStatus(void Function(String? message)? callback) => _onStatus = callback;

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
  set onDebugTrace(void Function(TtsDebugTraceSnapshot trace)? callback) =>
      _onDebugTrace = callback;

  @override
  Future<void> initialize() async {
    _onStatus?.call(null);
    _onActivity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  Future<List<VoiceProfile>> loadVoices() async => _voices;

  @override
  Future<void> selectVoice(VoiceProfile voice) async {}

  @override
  Future<void> setSpeechRate(double multiplier) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> speak(TtsSpeakRequest request) async {
    _onActivity?.call(
      const TtsPlaybackActivity(phase: TtsPlaybackPhase.buffering),
    );
  }

  @override
  Future<void> pause() async {
    _onActivity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  Future<void> stop() async {
    _onActivity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  void dispose() {}

  void emitStart() {
    _onActivity?.call(const TtsPlaybackActivity(phase: TtsPlaybackPhase.playing));
    _onStart?.call();
  }

  void emitProgress(TtsProgressUpdate update) {
    _onProgress?.call(update);
  }

  void emitComplete() {
    _onActivity?.call(const TtsPlaybackActivity.idle());
    _onComplete?.call();
  }

  void emitError(String message) {
    _onError?.call(message);
  }

  void emitDebugTrace(TtsDebugTraceSnapshot trace) {
    _onDebugTrace?.call(trace);
  }
}
