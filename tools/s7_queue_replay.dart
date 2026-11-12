// #144 diagnostic only: identical verified PCM, packet queue versus joined WAV.
// No model engine is constructed. The runner owns capture and normal Quit.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/services/work_character_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_main_responsiveness_probe.dart';
import 'native_queue_boundary_probe.dart';
import 'native_playback_position_probe.dart';
import 'native_timing_clock.dart';

/// Inert UI dependency, deliberately incapable of synthesis or model loading.
class _InertEngine implements TtsEngine {
  @override
  Future<void> initialize() async {}
  @override
  Future<List<VoiceProfile>> loadVoices() async => const [];
  @override
  Future<void> selectVoice(VoiceProfile voice) async {}
  @override
  Future<void> setSpeechRate(double multiplier) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> speak(TtsSpeakRequest request) async =>
      throw StateError('Replay has no synthesis route');
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
  @override
  set onStart(void Function()? callback) {}
  @override
  set onStatus(void Function(String?)? callback) {}
  @override
  set onProgress(void Function(TtsProgressUpdate)? callback) {}
  @override
  set onComplete(void Function()? callback) {}
  @override
  set onError(void Function(String)? callback) {}
  @override
  set onActivity(void Function(TtsPlaybackActivity)? callback) {}
  @override
  set onDebugTrace(void Function(TtsDebugTraceSnapshot)? callback) {}
}

class _Controller extends ReaderController {
  _Controller(Directory root)
    : super(
        ttsEngine: _InertEngine(),
        engineFactory: (_, _) => _InertEngine(),
        preferencesService: ReaderPreferencesService(
          workRepository: WorkCharacterRepository('${root.path}/works'),
        ),
        enablePlatformIntakeChannels: false,
        deferInitialSynthesis: true,
      );
  Future<void>? _initialization;
  TtsResourceProgress? progress;
  String message = 'Queue replay diagnostic; sample text is not synchronized.';
  @override
  Future<void> initialize() => _initialization ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
  // Leave the production sample reader idle: no intake, analysis or synthesis.
  @override
  Future<void> retryInitialization() async {}
  @override
  TtsResourceProgress? get speechResourceProgress => progress;
  @override
  String? get statusMessage => message;
  void report(String stage, int? completed, int? total) {
    progress = TtsResourceProgress(
      stage: stage,
      message: message,
      completed: completed,
      total: total,
      unit: 'frames',
    );
    notifyListeners();
  }
}

void _require(bool value, String message) {
  if (!value) throw StateError(message);
}

// Only sendable paths enter the worker. Hashing, validation, copies and joining
// run off the UI isolate. Input files are read only; output is private per run.
Future<Map<String, Object?>> _prepare(String input, String root) => Isolate.run(
  () async {
    final receiptFile = File(input);
    _require(await receiptFile.length() <= 8000000, 'Input receipt size bound');
    final receiptBytes = await receiptFile.readAsBytes();
    final source = jsonDecode(utf8.decode(receiptBytes)) as Map;
    final queued = source['queuedAudio'] as List;
    _require(queued.isNotEmpty && queued.length <= 2048, 'Input queue bound');
    final rows = <Map<String, Object?>>[];
    final pcm = BytesBuilder(copy: false);
    var totalBytes = 0, frames = 0;
    for (final original in queued.take(220)) {
      final reference = (original as Map)['reference'] as Map;
      final file = File(reference['path'] as String);
      final length = await file.length();
      totalBytes += length;
      _require(length >= 44 && totalBytes <= 120000000, 'PCM byte bound');
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      _require(
        length == reference['bytes'] && digest == reference['sha256'],
        'Source WAV hash/size mismatch',
      );
      _require(
        ascii.decode(bytes.sublist(0, 4)) == 'RIFF' &&
            ascii.decode(bytes.sublist(8, 12)) == 'WAVE',
        'Expected RIFF/WAVE',
      );
      final view = ByteData.sublistView(bytes);
      _require(
        view.getUint32(4, Endian.little) + 8 == bytes.length,
        'RIFF size mismatch',
      );
      Uint8List? data;
      var validFormat = false;
      for (var at = 12; at + 8 <= bytes.length;) {
        final tag = ascii.decode(bytes.sublist(at, at + 4));
        final size = view.getUint32(at + 4, Endian.little);
        final start = at + 8;
        _require(start + size <= bytes.length, 'Truncated WAV chunk');
        if (tag == 'fmt ') {
          _require(
            !validFormat &&
                size >= 16 &&
                view.getUint16(start, Endian.little) == 1 &&
                view.getUint16(start + 2, Endian.little) == 1 &&
                view.getUint32(start + 4, Endian.little) == 44100 &&
                view.getUint32(start + 8, Endian.little) == 88200 &&
                view.getUint16(start + 12, Endian.little) == 2 &&
                view.getUint16(start + 14, Endian.little) == 16,
            'Requires PCM16 mono 44100Hz',
          );
          validFormat = true;
        }
        if (tag == 'data') {
          _require(
            data == null && validFormat && size > 0 && size.isEven,
            'Expected one nonempty PCM data chunk after format',
          );
          data = Uint8List.sublistView(bytes, start, start + size);
        }
        at = start + size + size % 2;
      }
      _require(
        data != null &&
            reference['sampleRate'] == 44100 &&
            reference['channels'] == 1 &&
            reference['bitsPerSample'] == 16 &&
            reference['pcmBytes'] == data.length,
        'Source format receipt mismatch',
      );
      final payload = data!;
      final path = '$root/packet-${rows.length}.wav';
      await File(path).writeAsBytes(bytes, flush: true);
      final samples = ByteData.sublistView(payload);
      var peak = 0;
      for (var i = 0; i < payload.length; i += 2) {
        peak = math.max(peak, samples.getInt16(i, Endian.little).abs());
      }
      rows.add({
        'sourcePath': path,
        'originalReferencePath': file.path,
        'sourceReceiptIndex': rows.length,
        'startFrame': frames,
        'frameCount': payload.length ~/ 2,
        'reference': {
          'path': path,
          'sha256': digest,
          'bytes': length,
          'sampleRate': 44100,
          'channels': 1,
          'bitsPerSample': 16,
          'pcmBytes': payload.length,
          'peakPcm16': peak,
        },
      });
      pcm.add(payload);
      frames += payload.length ~/ 2;
    }
    _require(
      frames >= 65 * 44100 && frames <= 120 * 44100,
      'Replay requires 65–120 seconds of source PCM',
    );
    final joinedPcm = pcm.takeBytes();
    final header = ByteData(44)
      ..setUint32(4, 36 + joinedPcm.length, Endian.little)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, 44100, Endian.little)
      ..setUint32(28, 88200, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(40, joinedPcm.length, Endian.little);
    final joined = header.buffer.asUint8List();
    joined.setRange(0, 4, ascii.encode('RIFF'));
    joined.setRange(8, 12, ascii.encode('WAVE'));
    joined.setRange(12, 16, ascii.encode('fmt '));
    joined.setRange(36, 40, ascii.encode('data'));
    final joinedBytes =
        (BytesBuilder(copy: false)
              ..add(joined)
              ..add(joinedPcm))
            .takeBytes();
    final joinedPath = '$root/joined.wav';
    await File(joinedPath).writeAsBytes(joinedBytes, flush: true);
    return {
      'inputReceipt': input,
      'inputReceiptSha256': sha256.convert(receiptBytes).toString(),
      'expectedPackets': rows,
      'totalFrames': frames,
      'pcmSha256': sha256.convert(joinedPcm).toString(),
      'joined': {
        'path': joinedPath,
        'sha256': sha256.convert(joinedBytes).toString(),
        'bytes': joinedBytes.length,
        'sampleRate': 44100,
        'channels': 1,
        'bitsPerSample': 16,
        'pcmBytes': joinedPcm.length,
      },
    };
  },
);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final mode = Platform.environment['READALOUD_S7_REPLAY_MODE'];
  final input = Platform.environment['READALOUD_S7_REPLAY_INPUT'];
  _require(
    args.length == 2 &&
        args[0] == 'cached-8bit' &&
        (mode == 'packets' || mode == 'joined') &&
        input != null,
    'Expected cached-8bit RECEIPT and READALOUD_S7_REPLAY_MODE/INPUT',
  );
  _require(
    Platform.environment['HF_HUB_OFFLINE'] == '1',
    'Offline replay required',
  );
  final support = await getApplicationSupportDirectory();
  _require(
    support.path.contains('mlxPlaybackTest'),
    'Requires isolated QA identity',
  );
  final output = File(args[1]).absolute;
  _require(!await output.exists(), 'Preserve existing receipt');
  final root = await output.parent.createTemp('s7-replay-');
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final c = _Controller(root);
  final player = AudioPlayer(useLazyPreparation: false);
  final position = NativePlaybackPositionProbe(player);
  final watch = Stopwatch()..start();
  var phase = 'initialization', cancelled = false;
  var maxUi = 0, lastTick = 0, next = 0;
  final mutations = <Map<String, Object?>>[],
      samples = <Map<String, Object?>>[];
  final queued = <Map<String, Object?>>[], errors = <String>[];
  final shutdownErrors = <String>[];
  Future<void>? pump, playing, pendingMutation;
  Future<Map<String, Object?>>? preparing;
  Object? playbackError;
  Timer? pumpTimer;
  Map<String, Object?>? prepared;
  final segments = <Map<String, Object?>>[];
  final receipt = <String, Object?>{
    'schema': 'readaloud-native-variant-v1',
    'mode': 'cached-8bit',
    'replayMode': mode,
    'queueReplayDiagnostic': true,
    'useLazyPreparation': false,
    'passed': false,
    'functionalPassed': false,
    'modelQualification': 'NOT_APPLICABLE',
    'runRoot': root.path,
    'queuedAudio': queued,
    'playerSamples': samples,
    'queueMutations': mutations,
    'segments': segments,
    'limits':
        'Diagnostic only. Same production ReadAloudApp with static sample reader and inert engine; '
        'no reading/analysis/model/resource qualification. Playback progress is real player movement. '
        'Packet queue lead is at most 4s plus one indivisible packet; joined source necessarily admits '
        'the complete same PCM file. No production queue changes. Runner owns capture and normal Quit.',
  };
  Duration budget({bool cleanup = false}) => Duration(
    milliseconds: math.max(
      1,
      (cleanup ? 265000 : 240000) - watch.elapsedMilliseconds,
    ),
  );
  Map<String, Object?> stamp() => {
    'unixMicros': DateTime.now().microsecondsSinceEpoch,
    'elapsedMicros': watch.elapsedMicroseconds,
  };
  Future<void> until(
    bool Function() ready,
    String label, {
    int seconds = 90,
  }) async {
    final end = math.min(240000, watch.elapsedMilliseconds + seconds * 1000);
    while (!ready()) {
      if (watch.elapsedMilliseconds >= end) throw TimeoutException(label);
      if (errors.isNotEmpty) throw StateError(errors.join('; '));
      if (playbackError != null) throw StateError('$playbackError');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  final native = NativeMainResponsivenessProbe()..start(() => phase);
  final subscription = player.positionStream.listen(position.sample);
  void sampleActualPlayer() {
    final now = watch.elapsedMilliseconds;
    position.sample(player.position);
    final index = player.currentIndex;
    final source = index != null && index >= 0 && index < player.sequence.length
        ? player.sequence[index]
        : null;
    if (samples.length >= 2700) {
      errors.add('Player sample bound');
      return;
    }
    samples.add({
      ...stamp(),
      'elapsedMs': now,
      'phase': phase,
      'engineIndex': 0,
      'playing': player.playing,
      'processingState': player.processingState.name,
      'positionMs': player.position.inMilliseconds,
      'currentIndex': index,
      'source': source is UriAudioSource ? source.uri.toString() : null,
    });
    if (phase == 'replay') {
      final rows = prepared!['expectedPackets'] as List;
      final preceding =
          mode == 'packets' && index != null && index < rows.length
          ? (rows[index] as Map)['startFrame'] as int
          : 0;
      c.report(
        'replay',
        preceding + player.position.inMicroseconds * 44100 ~/ 1000000,
        prepared['totalFrames'] as int,
      );
    }
  }

  final heartbeat = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final now = watch.elapsedMilliseconds;
    maxUi = math.max(maxUi, now - lastTick - 100);
    lastTick = now;
    sampleActualPlayer();
  });
  Future<void> mutate(
    String operation,
    String path,
    Future<void> Function() action,
  ) async {
    _require(mutations.length < 2048, 'Queue mutation bound');
    final row = <String, Object?>{
      'operation': operation,
      'sourcePath': path,
      'requested': stamp(),
      'phase': phase,
    };
    mutations.add(row);
    try {
      final pending = action();
      pendingMutation = pending;
      await pending.timeout(budget());
      pendingMutation = null;
      row['completed'] = stamp();
    } catch (e) {
      row['failed'] = stamp();
      row['error'] = '$e';
      rethrow;
    }
  }

  Future<void> fill() async {
    final rows = prepared!['expectedPackets'] as List;
    while (!cancelled && next < rows.length) {
      final index = player.currentIndex ?? 0;
      final currentStart = (rows[index] as Map)['startFrame'] as int;
      final played =
          currentStart + player.position.inMicroseconds * 44100 ~/ 1000000;
      final row = Map<String, Object?>.from(rows[next] as Map);
      if (next > 0 && (row['startFrame'] as int) - played >= 4 * 44100) return;
      final path = row['sourcePath'] as String;
      await mutate(
        next == 0 ? 'setAudioSources' : 'addAudioSource',
        path,
        () async {
          if (next == 0) {
            await player.setAudioSources([AudioSource.file(path)]);
          } else {
            await player.addAudioSource(AudioSource.file(path));
          }
        },
      );
      // In-flight admission is joined even after cancellation; no next add.
      queued.add({
        ...row,
        'engineIndex': 0,
        'engineId': 'queue-replay',
        'queuedUnixMicros': DateTime.now().microsecondsSinceEpoch,
      });
      next++;
    }
  }

  void requestPump() {
    if (cancelled || pump != null) return;
    pump = fill()
        .catchError((Object e) {
          errors.add('Queue pump: $e');
        })
        .whenComplete(() {
          pump = null;
        });
  }

  runApp(ReadAloudApp(controller: c));
  try {
    await c.initialize().timeout(budget());
    await WidgetsBinding.instance.endOfFrame;
    stdout.writeln('S7_VARIANT_NATIVE_STARTED');
    receipt['startBridgeRequested'] = stamp();
    (await NativeTimingClockSnapshot.capture()).record(receipt, 'startBridge');
    receipt['startBridgeReturned'] = stamp();
    phase = 'verify-and-join';
    c.report(phase, null, null);
    preparing = _prepare(input!, root.path);
    prepared = await preparing.timeout(budget());
    receipt['sourceProvenance'] = prepared;
    c.report(
      phase,
      prepared['totalFrames'] as int,
      prepared['totalFrames'] as int,
    );
    phase = 'queue-admission';
    c.report(phase, null, null);
    if (mode == 'packets') {
      requestPump();
      await pump;
      _require(errors.isEmpty, 'Initial packet admission failed');
      pumpTimer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => requestPump(),
      );
    } else {
      final joined = prepared['joined'] as Map;
      final path = joined['path'] as String;
      await mutate('setAudioSources', path, () async {
        await player.setAudioSources([AudioSource.file(path)]);
      });
      queued.add({
        'engineIndex': 0,
        'engineId': 'queue-replay',
        'sourcePath': path,
        'queuedUnixMicros': DateTime.now().microsecondsSinceEpoch,
        'reference': joined,
      });
    }
    // Initialize the real native player before asking capture to observe its
    // process. Play still waits for actual capture frames; this is a warm
    // diagnostic, never a launch/load clock measurement.
    phase = 'capture-wait';
    c.report(phase, null, null);
    final captureGate = File('${output.parent.path}/capture.ready');
    await until(
      () => captureGate.existsSync(),
      'Capture readiness',
      seconds: 30,
    );
    phase = 'replay';
    final segment = <String, Object?>{
      'label': 'queue-replay-$mode',
      'engineIndex': 0,
      'engineId': 'queue-replay',
      'requiredWallPlaybackMs': 60000,
      'playRequestedUnixMicros': DateTime.now().microsecondsSinceEpoch,
    };
    segments.add(segment);
    playing = player.play().catchError((Object e) {
      playbackError = e;
    });
    await until(
      () => player.playing && position.sampledPositionTotalMs >= 50,
      'Real player movement',
    );
    segment['firstPositionUnixMicros'] = DateTime.now().microsecondsSinceEpoch;
    final end = watch.elapsedMilliseconds + 60000;
    await until(
      () => watch.elapsedMilliseconds >= end,
      '60s actual playback',
      seconds: 62,
    );
    // Pause an audible expected packet, keeping the silence-tail ambiguity explicit.
    await until(
      () {
        final rows = prepared!['expectedPackets'] as List;
        final index = player.currentIndex ?? 0;
        final frame = mode == 'joined'
            ? player.position.inMicroseconds * 44100 ~/ 1000000
            : (rows[index] as Map)['startFrame'] as int;
        final row = rows.cast<Map>().lastWhere(
          (r) => (r['startFrame'] as int) <= frame,
        );
        return ((row['reference'] as Map)['peakPcm16'] as num) > 327.68;
      },
      'Audible Pause boundary',
      seconds: 2,
    );
    // A periodic observation can fall in the previous short packet. Record
    // the actual current source/position at Pause instead of inferring it.
    sampleActualPlayer();
    segment['pauseRequestedUnixMicros'] = DateTime.now().microsecondsSinceEpoch;
    cancelled = true;
    pumpTimer?.cancel();
    await player.pause().timeout(budget());
    segment['pauseReturnedUnixMicros'] = DateTime.now().microsecondsSinceEpoch;
    await pump?.timeout(budget());
    await playing.timeout(budget());
    segment['terminal'] = playbackError?.toString();
    segment['positionEvidence'] = position.toMap();
    segment['observedPositionAdvanceMs'] = position.sampledPositionTotalMs;
    _require(
      position.sampledPositionTotalMs >= 51000 &&
          !position.overflow &&
          playbackError == null,
      'Insufficient actual player progress',
    );
    phase = 'quiet-tail';
    await Future<void>.delayed(const Duration(milliseconds: 1250));
    _require(!player.playing, 'Pause did not stop playback');
    receipt['replayCompleted'] = true;
  } catch (e, stack) {
    receipt['error'] = '$e';
    receipt['stack'] = '$stack';
  } finally {
    cancelled = true;
    phase = 'shutdown';
    pumpTimer?.cancel();
    heartbeat.cancel();
    Future<void> clean(String label, Future<void> Function() action) async {
      try {
        await action().timeout(budget(cleanup: true));
      } catch (e) {
        shutdownErrors.add('$label: $e');
      }
    }

    await clean('Pause', player.pause);
    await clean('Pending queue admission', () async {
      await pump;
    });
    await clean('Pending native mutation', () async {
      await pendingMutation;
    });
    await clean('File worker join', () async {
      await preparing;
    });
    await clean('Play completion', () async {
      await playing;
    });
    await clean('Position subscription', subscription.cancel);
    receipt['nativeMainResponsiveness'] = await native.close();
    await clean('Native boundary readout', () async {
      receipt['nativeQueueBoundaryAudit'] = await readNativeQueueBoundaryAudit();
    });
    await clean('Timing bridge', () async {
      receipt['endBridgeRequested'] = stamp();
      (await NativeTimingClockSnapshot.capture()).record(receipt, 'endBridge');
      receipt['endBridgeReturned'] = stamp();
    });
    await clean('Preparation shutdown', c.shutdownPreparation);
    c.dispose();
    await clean('Player disposal', player.dispose);
    receipt['maxUiHeartbeatDelayMs'] = maxUi;
    receipt['observationErrors'] = errors;
    receipt['shutdownErrors'] = shutdownErrors;
    receipt['replayCleanupComplete'] = shutdownErrors.isEmpty;
    receipt['responsivenessCriteriaMet'] =
        maxUi <= 250 &&
        (receipt['nativeMainResponsiveness'] as Map)['passed'] == true;
    receipt['passed'] =
        false; // Diagnostic can never qualify a model or product.
    await File('${output.path}.pending').writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt),
      flush: true,
    );
    await File('${output.path}.pending').rename(output.path);
    stdout.writeln('S7_VARIANT_COMPLETE passed=false diagnostic=$mode');
  }
}
