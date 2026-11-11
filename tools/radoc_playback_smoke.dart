// Actual app/player probe for a copied, fully rendered .radoc audio book.
// Build target: tools/radoc_playback_smoke.dart. Arguments: BOOK RECEIPT.
// The runner owns normal Quit. This entrypoint never exits the process.
import 'dart:async';
import 'native_main_responsiveness_probe.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/spoken_chunk_record.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/app_launch_options.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/rendered_scene_repository.dart';
import 'package:read_aloud/src/services/work_character_repository.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmokeController extends ReaderController {
  SmokeController(KokoroTtsEngine engine, String statePath)
    : super(
        ttsEngine: engine,
        preferencesService: ReaderPreferencesService(
          workRepository: WorkCharacterRepository('$statePath/works'),
        ),
        renderedSceneRepository: RenderedSceneRepository(
          Directory('$statePath/scenes'),
        ),
        enablePlatformIntakeChannels: false,
        deferInitialSynthesis: true,
      );
  Future<void>? _initialization;
  void Function(String path, bool started)? onBookSave;
  bool _recordingBookSave = false;

  @override
  Future<File?> exportDocumentToPath(
    String outputPath, {
    bool audioBook = false,
  }) async {
    final record = audioBook && !_recordingBookSave;
    if (record) {
      _recordingBookSave = true;
      onBookSave?.call(outputPath, true);
    }
    try {
      return await super.exportDocumentToPath(outputPath, audioBook: audioBook);
    } finally {
      if (record) {
        _recordingBookSave = false;
        onBookSave?.call(outputPath, false);
      }
    }
  }

  @override
  Future<void> initialize() => _initialization ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

/// Keep the real Kokoro player/playlist/cancellation path. Every synthesis entry
/// fails visibly, including startup and voice/resource/model preparation.
class OfflinePlaybackEngine extends KokoroTtsEngine {
  OfflinePlaybackEngine(AudioPlayer player) : super(player: player);
  final Map<String, int> forbiddenCalls = {};
  Never _forbidden(String operation) {
    forbiddenCalls.update(operation, (count) => count + 1, ifAbsent: () => 1);
    throw StateError('Offline playback called $operation');
  }

  @override
  Future<void> initialize() async => _forbidden('initialize');
  @override
  Future<List<VoiceProfile>> loadVoices() async => _forbidden('loadVoices');
  @override
  Future<void> prepareSelectedModel() async =>
      _forbidden('prepareSelectedModel');
  @override
  Future<void> installVoice(String voiceId) async => _forbidden('installVoice');
  @override
  Future<void> selectVoice(VoiceProfile voice) async =>
      _forbidden('selectVoice');
  @override
  Future<List<PreparedVoiceBinding>> prepareDocumentResources({
    required String documentId,
    required int revision,
    required Set<String> voiceIds,
    required String pronunciationProfileId,
  }) async => _forbidden('prepareDocumentResources');
  @override
  Future<void> speak(TtsSpeakRequest request) async => _forbidden('speak');
  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async =>
      _forbidden('exportAudio');
}

Future<void> main(List<String> args) async {
  final enteredAt = DateTime.now().microsecondsSinceEpoch;
  final watch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // Isolate this probe from saved reader preferences and resume state.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  if (args.length != 2) {
    stderr.writeln('Usage: radoc_playback_smoke BOOK RECEIPT');
    runApp(const SizedBox.shrink());
    return;
  }
  final receipt = <String, Object?>{
    'schema': 'readaloud-radoc-native-smoke-v1',
    'passed': false,
    'book': args[0],
    'dartEntryUnixMicros': enteredAt,
    'emittedAudioCapture': 'external evidence required',
    'humanListening': 'external evidence required',
  };
  final launchedAt = int.tryParse(
    Platform.environment['READALOUD_SMOKE_LAUNCH_UNIX_MICROS'] ?? '',
  );
  receipt['processLaunchUnixMicros'] = launchedAt;
  final player = AudioPlayer(useLazyPreparation: false);
  final engine = OfflinePlaybackEngine(player);
  final controller = SmokeController(engine, '${args[1]}.state');
  final audioChecks = <String, Future<Map<String, Object?>>>{};
  final sampleLog = File('${args[1]}.positions.jsonl').openWrite();
  var collectingFirstRun = true;
  int? firstNativePositionAt;
  var maxPositionMs = 0;
  var lastUiTick = 0;
  var maxUiDelayMs = 0;
  var heartbeatCount = 0;
  var probePhase = 'startup';
  final nativeMain = NativeMainResponsivenessProbe()..start(() => probePhase);
  var previousTickPhase = probePhase;
  final delayedTicks = <Map<String, Object?>>[];
  // The interactive File → Save Audio Book path requests audioBook=true
  // after the native panel returns. Keep its export delay separate from
  // startup, waiting for the operator, and programmatic reopen checks.
  final bookSaves = <Map<String, Object?>>[];
  int? saveStarted;
  int maxSaveDelayMs = 0;
  controller.onBookSave = (path, started) {
    final now = watch.elapsedMilliseconds;
    final start = saveStarted;
    if (started) {
      saveStarted = now;
      maxSaveDelayMs = 0;
    } else if (start != null) {
      final lastGap = math.max(0, now - math.max(lastUiTick, start) - 50);
      if (bookSaves.length == 16) bookSaves.removeAt(0);
      bookSaves.add({
        'path': path,
        'elapsedMs': now - start,
        'maxUiHeartbeatDelayMs': math.max(maxSaveDelayMs, lastGap),
      });
      saveStarted = null;
    }
  };
  final heartbeat = Timer.periodic(const Duration(milliseconds: 50), (_) {
    final now = watch.elapsedMilliseconds;
    final delay = now - lastUiTick - 50;
    maxUiDelayMs = math.max(maxUiDelayMs, delay);
    if (delay > 100) {
      if (delayedTicks.length == 16) delayedTicks.removeAt(0);
      delayedTicks.add({
        'elapsedMs': now,
        'delayMs': delay,
        'previousTickPhase': previousTickPhase,
        'currentPhase': probePhase,
        'bookExportActive': saveStarted != null,
      });
    }
    previousTickPhase = probePhase;
    final start = saveStarted;
    if (start != null) {
      maxSaveDelayMs = math.max(
        maxSaveDelayMs,
        (now - math.max(lastUiTick, start) - 50).toInt(),
      );
    }
    lastUiTick = now;
    heartbeatCount++;
  });
  // One native source observer; at most 256 immutable file checks are admitted.
  // Each check reads in a worker isolate while the real player pins its file.
  // The probe awaits all checks before replacement and closes every observer.
  final sequenceSubscription = player.sequenceStream.listen((sequence) {
    if (!collectingFirstRun) return;
    for (final source in sequence) {
      if (source is! UriAudioSource || source.uri.scheme != 'file') continue;
      final path = source.uri.toFilePath();
      if (!audioChecks.containsKey(path) && audioChecks.length < 256) {
        audioChecks[path] = _inspectWavOnWorker(path).then(
          (value) => value,
          onError: (Object error) => <String, Object?>{
            'path': path,
            'error': '$error',
          },
        );
      }
    }
  });
  final positionSubscription = player.positionStream.listen((position) {
    if (!collectingFirstRun) return;
    final now = watch.elapsedMilliseconds;
    if (player.playing && position > Duration.zero) {
      firstNativePositionAt ??= DateTime.now().microsecondsSinceEpoch;
    }
    maxPositionMs = math.max(maxPositionMs, position.inMilliseconds);
    sampleLog.writeln(
      jsonEncode({
        'dartElapsedMs': now,
        'positionMs': position.inMilliseconds,
        'index': player.currentIndex,
        'playing': player.playing,
        'processing': player.processingState.name,
        'sourceWord': controller.currentWordIndex,
        'state': controller.playbackState.name,
      }),
    );
  });

  void checkFailure() {
    if (engine.forbiddenCalls.isNotEmpty ||
        controller.startupError != null ||
        controller.playbackState == ReaderPlaybackPrimaryState.failed) {
      throw StateError(
        'Playback failed: ${controller.startupError ?? controller.statusMessage}; '
        'forbidden=${engine.forbiddenCalls}',
      );
    }
  }

  Future<void> until(
    bool Function() condition,
    String description, {
    int timeoutMs = 60000,
  }) async {
    final deadline = watch.elapsedMilliseconds + timeoutMs;
    while (!condition()) {
      checkFailure();
      if (watch.elapsedMilliseconds >= deadline) {
        throw TimeoutException('$description: ${controller.statusMessage}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    checkFailure();
  }

  stdout.writeln('RADOC_SMOKE_READY pid=$pid receipt=${args[1]}');
  receipt['importRequestedMs'] = watch.elapsedMilliseconds;
  runApp(
    ReadAloudApp(
      controller: controller,
      launchOptions: AppLaunchOptions(inputPaths: [args[0]]),
    ),
  );
  try {
    await controller.initialize();
    // ReadAloudScreen invokes normal importFilePaths for the launch input. Do
    // not race a second import or let empty intake trigger synthesis startup.
    await until(
      () => controller.hasPublishedAudio && !controller.isImporting,
      'Normal launch intake',
    );
    await controller.completeInitialIntake();
    if (!controller.hasPublishedAudio) throw StateError('No published audio');
    receipt['importCompleteMs'] = watch.elapsedMilliseconds;
    receipt['playRequestedMs'] = watch.elapsedMilliseconds;
    probePhase = 'play-request';
    final captureGate = Platform.environment['READALOUD_RADOC_CAPTURE_GATE'];
    receipt['controlledCaptureGate'] = captureGate != null;
    if (captureGate != null) {
      probePhase = 'operator-capture-wait';
      stdout.writeln('RADOC_CAPTURE_WAITING');
      await until(
        () => File(captureGate).existsSync(),
        'External capture readiness',
      );
    }
    probePhase = 'initial-playback';
    unawaited(controller.startPlayback());
    await until(() => firstNativePositionAt != null, 'First native position');
    receipt['firstNativePositionUnixMicros'] = firstNativePositionAt;
    receipt['dartEntryToNativePositionMs'] =
        (firstNativePositionAt! - enteredAt) / 1000;
    if (launchedAt != null) {
      final elapsed = (firstNativePositionAt! - launchedAt) / 1000;
      receipt['launchToNativePositionMs'] = elapsed;
      // Position is a native playback observation; acoustic onset is measured
      // separately in the platform capture, never inferred from this flag.
      receipt['nativePositionWithinTwoSeconds'] = elapsed <= 2000;
    }
    await until(
      () => controller.playbackState == ReaderPlaybackPrimaryState.completed,
      'Full book source end',
      timeoutMs: 100000,
    );
    receipt['sourceEndMs'] = watch.elapsedMilliseconds;
    final chunks = controller.spokenChunkRecords;
    var nextWord = 0;
    for (final chunk in chunks) {
      if (!chunk.completed || chunk.startWordIndex != nextWord) {
        throw StateError('Missing, repeated or incomplete source span');
      }
      nextWord = chunk.endWordIndex;
    }
    final expectedEnd = controller.preparedWordCount;
    receipt['spokenChunks'] = chunks
        .map(
          (chunk) => {
            'chunkId': chunk.chunkId,
            'startWord': chunk.startWordIndex,
            'endWord': chunk.endWordIndex,
            'completed': chunk.completed,
            'durationMs': chunk.audioDuration.inMilliseconds,
            'sceneTurns': chunk.sceneTurns.map((turn) => turn.toMap()).toList(),
          },
        )
        .toList();
    receipt['expectedSourceEndWord'] = expectedEnd;
    receipt['observedSourceEndWord'] = nextWord;
    if (chunks.isEmpty ||
        expectedEnd <= 0 ||
        nextWord != expectedEnd ||
        !controller.isPreparationComplete) {
      throw StateError('Playback did not cover complete prepared source');
    }
    collectingFirstRun = false;
    final checked = await Future.wait(audioChecks.values);
    receipt['queuedAudio'] = checked;
    if (checked.isEmpty || checked.any((item) => item['error'] != null)) {
      throw StateError('Native queued WAV inspection failed');
    }
    final peak = checked
        .map((item) => item['peakPcm16'] as int)
        .reduce(math.max);
    receipt['peakPcm16'] = peak;
    if (peak < 100 || maxPositionMs < 500) {
      throw StateError('Native audio did not advance or queued PCM is silent');
    }
    // Export via the same controller, then reopen a physically separate copy.
    probePhase = 'programmatic-export';
    final exportedPath = '${args[1]}.export.radoc';
    final exported = await controller.exportDocumentToPath(exportedPath);
    if (exported == null) throw StateError('Audio book export returned null');
    final reopenedPath = '${args[1]}.reopened.radoc';
    await exported.copy(reopenedPath);
    probePhase = 'programmatic-reopen';
    await controller.importFilePaths([reopenedPath]);
    await controller.completeInitialIntake();
    if (!controller.hasPublishedAudio) throw StateError('Reopen lost audio');
    unawaited(controller.startPlayback());
    await until(
      () => player.playing && player.position.inMilliseconds >= 500,
      'Reopened book native playback',
    );
    receipt['reopen'] = {
      'exportPath': exportedPath,
      'copiedPath': reopenedPath,
      'positionMs': player.position.inMilliseconds,
      'hasPublishedAudio': controller.hasPublishedAudio,
    };
    probePhase = 'transport';
    final pauseAt = watch.elapsedMilliseconds;
    await controller.pausePlayback();
    receipt['pauseMs'] = watch.elapsedMilliseconds - pauseAt;
    final paused = player.position;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (player.playing || player.position != paused) {
      throw StateError('Native position advanced after completed Pause');
    }
    final pending = controller.startPlayback();
    await controller.pausePlayback();
    await pending;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (player.playing ||
        controller.isPlaying ||
        controller.hasPendingPlaybackIntent) {
      throw StateError('Cancelled pending Play triggered stale speech');
    }
    receipt['cancelledPlayStayedStopped'] = true;
    unawaited(controller.startPlayback());
    await until(
      () => player.playing && player.position.inMilliseconds >= 500,
      'Restart after cancellation',
    );
    await controller.pausePlayback();
    receipt['restartAfterCancellation'] = true;
    checkFailure();
    if (maxUiDelayMs > 250) {
      throw StateError('UI heartbeat delayed $maxUiDelayMs ms');
    }
    receipt['passed'] = true;
  } catch (error, stack) {
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
  } finally {
    heartbeat.cancel();
    final mainReceipt = await nativeMain.close();
    receipt['nativeMainResponsiveness'] = mainReceipt;
    if (mainReceipt['passed'] != true) {
      receipt['passed'] = false;
      receipt['nativeMainError'] =
          'Native main-thread response exceeded its bound or failed.';
    }
    try {
      await engine.stop();
      await controller.shutdownPreparation();
      await engine.shutdownResources();
      receipt['resourceShutdownComplete'] = true;
    } catch (error) {
      receipt['passed'] = false;
      receipt['shutdownError'] = '$error';
    }
    await sequenceSubscription.cancel();
    await positionSubscription.cancel();
    await sampleLog.close();
    receipt.addAll({
      'forbiddenModelCalls': engine.forbiddenCalls,
      'forbiddenModelCallCount': engine.forbiddenCalls.values.fold<int>(
        0,
        (a, b) => a + b,
      ),
      'maxNativePositionMs': maxPositionMs,
      'maxUiHeartbeatDelayMs': maxUiDelayMs,
      'bookSaves': bookSaves,
      'delayedTicks': delayedTicks,
      'uiHeartbeatCount': heartbeatCount,
      'elapsedMs': watch.elapsedMilliseconds,
      'normalQuit': 'runner must request and verify',
    });
    final staged = File('${args[1]}.pending');
    await staged.writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt),
      flush: true,
    );
    await staged.rename(args[1]);
    stdout.writeln('RADOC_SMOKE_COMPLETE passed=${receipt['passed']}');
  }
}

// Hashing and chunked PCM inspection are worker-owned. No full scene PCM is
// materialized in the UI isolate, and file handles close even on malformed WAVs.
Future<Map<String, Object?>> _inspectWav(String path) async {
  final file = File(path);
  final digest = await sha256.bind(file.openRead()).first;
  final input = await file.open();
  try {
    final length = await input.length();
    final header = await input.read(12);
    if (header.length != 12 ||
        ascii.decode(header.sublist(0, 4)) != 'RIFF' ||
        ascii.decode(header.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Expected PCM WAV');
    }
    int? rate, channels, bits, format;
    var peak = 0;
    var pcmBytes = 0;
    while (await input.position() + 8 <= length) {
      final chunk = await input.read(8);
      final tag = ascii.decode(chunk.sublist(0, 4));
      final size = ByteData.sublistView(chunk).getUint32(4, Endian.little);
      final start = await input.position();
      if (start + size > length) throw const FormatException('Truncated WAV');
      if (tag == 'fmt ') {
        if (size < 16) throw const FormatException('Invalid WAV format');
        final fields = ByteData.sublistView(await input.read(16));
        format = fields.getUint16(0, Endian.little);
        channels = fields.getUint16(2, Endian.little);
        rate = fields.getUint32(4, Endian.little);
        bits = fields.getUint16(14, Endian.little);
      } else if (tag == 'data') {
        if (format != 1 || bits != 16 || size.isOdd) {
          throw const FormatException('Expected native PCM16');
        }
        pcmBytes += size;
        var remaining = size;
        while (remaining > 0) {
          final bytes = await input.read(math.min(65536, remaining));
          if (bytes.isEmpty || bytes.length.isOdd) {
            throw const FormatException('Truncated PCM');
          }
          final data = ByteData.sublistView(bytes);
          for (var i = 0; i < bytes.length; i += 2) {
            peak = math.max(peak, data.getInt16(i, Endian.little).abs());
          }
          remaining -= bytes.length;
        }
      }
      await input.setPosition(start + size + size % 2);
    }
    if (pcmBytes == 0 || rate == null || channels == null) {
      throw const FormatException('Missing WAV PCM/format');
    }
    return {
      'path': path,
      'sha256': digest.toString(),
      'bytes': length,
      'sampleRate': rate,
      'channels': channels,
      'bitsPerSample': bits,
      'pcmBytes': pcmBytes,
      'peakPcm16': peak,
    };
  } finally {
    await input.close();
  }
}

Future<Map<String, Object?>> _inspectWavOnWorker(String path) =>
    Isolate.run(() => _inspectWav(path));
