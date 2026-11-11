// Production normal-file intake, real Fish synthesis/player, no capture gate.
// Args: FISH_ENGINE INPUT_DOCUMENT RECEIPT. Runner owns normal Quit.
import 'dart:async';
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
import 'package:read_aloud/src/models/spoken_chunk_record.dart';
import 'package:read_aloud/src/services/app_launch_options.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';
import 'package:read_aloud/src/services/radoc_audio_package.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/rendered_scene_repository.dart';
import 'package:read_aloud/src/services/work_character_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_main_responsiveness_probe.dart';

// Isolation seams only. Initialization remains the production controller owner;
// the screen and this observer share that one future instead of racing it.
class _Controller extends ReaderController {
  _Controller(KokoroTtsEngine engine, Directory root)
    : super(
        ttsEngine: engine,
        renderedSceneRepository: RenderedSceneRepository(root),
        preferencesService: ReaderPreferencesService(
          workRepository: WorkCharacterRepository('${root.path}/works'),
        ),
        enablePlatformIntakeChannels: false,
        deferInitialSynthesis: true,
      );
  Future<void>? _initialization;
  @override
  Future<void> initialize() => _initialization ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

Future<void> main(List<String> args) async {
  final entered = DateTime.now().microsecondsSinceEpoch;
  final clock = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 3) {
    stderr.writeln(
      'Usage: radoc_first_load_smoke FISH_ENGINE INPUT_DOCUMENT RECEIPT',
    );
    runApp(const SizedBox.shrink());
    return;
  }
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final output = File(args[2]).absolute;
  await output.parent.create(recursive: true);
  final root = await output.parent.createTemp('s6-first-load-');
  final player = AudioPlayer(useLazyPreparation: false);
  var synthesisCalls = 0;
  final engine = KokoroTtsEngine(
    player: player,
    engineId: args[0],
    mlxArtifactStore: AudioArtifactStore(Directory('${root.path}/raw')),
    mlxModelPath: Platform.environment['READALOUD_MLX_TTS_MODEL_PATH'],
    mlxPythonPath: Platform.environment['READALOUD_MLX_PYTHON'],
    mlxQuantizationBits: int.parse(
      Platform.environment['READALOUD_SMOKE_QUANTIZATION_BITS'] ?? '0',
    ),
    beforeSynthesis: () async {
      synthesisCalls++;
    },
  );
  final c = _Controller(engine, Directory('${root.path}/scenes'));
  var phase = 'normal-intake';
  final nativeMain = NativeMainResponsivenessProbe()..start(() => phase);
  final metrics = File('${output.path}.metrics.jsonl').openWrite();
  final positions = File('${output.path}.positions.jsonl').openWrite();
  final receipt = <String, Object?>{
    'schema': 'readaloud-native-first-load-v1',
    'passed': false,
    'engine': args[0],
    'input': args[1],
    'runRoot': root.path,
    'dartEntryUnixMicros': entered,
    'controlledCaptureGate': false,
    'rawAudioCache': 'fresh private per-run store; existing model assets only',
    'emittedAudioCapture': 'external waveform comparison required',
    'humanListening': 'not established by this probe',
    'inputResponsiveness':
        'heartbeat and native roundtrip only; actual UI input separate',
  };
  final launch = int.tryParse(
    Platform.environment['READALOUD_SMOKE_LAUNCH_UNIX_MICROS'] ?? '',
  );
  receipt['processLaunchUnixMicros'] = launch;
  var lastTick = 0, maxDelay = 0, maxPosition = 0;
  int? firstPosition;
  final delays = <Map<String, Object?>>[];
  final heartbeat = Timer.periodic(const Duration(milliseconds: 50), (_) {
    final now = clock.elapsedMilliseconds;
    final delay = now - lastTick - 50;
    maxDelay = math.max(maxDelay, delay);
    if (delay > 100) {
      if (delays.length == 32) delays.removeAt(0);
      delays.add({'elapsedMs': now, 'delayMs': delay, 'phase': phase});
    }
    lastTick = now;
  });
  PlaybackInstrumentationService.instance.observer = (event) {
    metrics.writeln(jsonEncode({'phase': phase, ...event.toMap()}));
  };
  // Bounded evidence collector. One serial isolate job at a time; paths are
  // captured at native playlist admission while production retains their pins.
  // Copies survive producer shutdown and are not used as playback inputs.
  final checks = <String, Future<Map<String, Object?>>>{};
  Future<void> copying = Future.value();
  var overflow = false;
  final sequence = player.sequenceStream.listen((sources) {
    for (final source in sources) {
      if (source is! UriAudioSource || source.uri.scheme != 'file') continue;
      final path = source.uri.toFilePath();
      if (checks.containsKey(path)) continue;
      if (checks.length >= 256) {
        overflow = true;
        continue;
      }
      final index = checks.length;
      final destination = '${root.path}/queued-$index.wav';
      final check = copying
          .then(
            (_) => Isolate.run(() async {
              await File(path).copy(destination);
              return _inspectWav(destination);
            }),
          )
          .then(
            (value) => <String, Object?>{
              'queueIndex': index,
              'originalPath': path,
              ...value,
            },
            onError: (Object error) => <String, Object?>{
              'queueIndex': index,
              'originalPath': path,
              'error': '$error',
            },
          );
      checks[path] = check;
      copying = check.then<void>((_) {});
    }
  });
  final position = player.positionStream.listen((p) {
    if (player.playing && p > Duration.zero) {
      firstPosition ??= DateTime.now().microsecondsSinceEpoch;
    }
    maxPosition = math.max(maxPosition, p.inMilliseconds);
    positions.writeln(
      jsonEncode({
        'elapsedMs': clock.elapsedMilliseconds,
        'positionMs': p.inMilliseconds,
        'index': player.currentIndex,
        'playing': player.playing,
        'sourceWord': c.currentWordIndex,
        'state': c.playbackState.name,
      }),
    );
  });
  void checkFailure() {
    if (c.startupError != null ||
        c.playbackState == ReaderPlaybackPrimaryState.failed) {
      throw StateError(c.startupError ?? c.statusMessage ?? 'Playback failed');
    }
  }

  Future<void> until(bool Function() condition, String label) async {
    final end = clock.elapsedMilliseconds + 180000;
    while (!condition()) {
      checkFailure();
      if (clock.elapsedMilliseconds >= end) {
        throw TimeoutException('$label: ${c.statusMessage}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    checkFailure();
  }

  Future<void>? play;
  Object? playError;
  runApp(
    ReadAloudApp(
      controller: c,
      launchOptions: AppLaunchOptions(inputPaths: [args[1]]),
    ),
  );
  try {
    // Screen owns normal initialize/import/completeInitialIntake. Never await
    // model readiness or whole preparation before registering the Play intent.
    await until(() => c.preparedWordCount > 0, 'First prepared content');
    receipt['playRequestedMs'] = clock.elapsedMilliseconds;
    receipt['preparedWordsAtPlay'] = c.preparedWordCount;
    receipt['preparationCompleteAtPlay'] = c.isPreparationComplete;
    receipt['initializingAtPlay'] = c.isInitializing;
    phase = 'play-request';
    play = c.startPlayback().catchError((Object error) {
      playError = error;
    });
    await until(
      () => firstPosition != null || playError != null,
      'First native position',
    );
    if (playError != null) throw StateError('Play failed: $playError');
    receipt['firstNativePositionUnixMicros'] = firstPosition;
    if (launch != null) {
      receipt['launchToNativePositionMs'] = (firstPosition! - launch) / 1000;
    }
    phase = 'playing';
    await until(
      () =>
          c.playbackState == ReaderPlaybackPrimaryState.completed ||
          playError != null,
      'Complete original source',
    );
    await play;
    if (playError != null) throw StateError('Play failed: $playError');
    final chunks = c.spokenChunkRecords;
    var end = 0;
    for (final chunk in chunks) {
      if (!chunk.completed || chunk.startWordIndex != end) {
        throw StateError('Missing/repeated/incomplete source span');
      }
      end = chunk.endWordIndex;
    }
    final independentlyCounted = int.tryParse(
      Platform.environment['READALOUD_FIRST_LOAD_EXPECTED_WORDS'] ?? '',
    );
    final expected = independentlyCounted ?? c.document.wordCount;
    receipt['expectedWordCountAuthority'] = independentlyCounted == null
        ? 'complete document; independent runner count absent'
        : 'runner original plaintext whitespace-token count';
    receipt['completeDocumentWordCount'] = c.document.wordCount;
    receipt.addAll({
      'originalSourceExpectedWordCount': expected,
      'expectedSourceEndWord': expected,
      'observedSourceEndWord': end,
      'sourceEndMs': clock.elapsedMilliseconds,
      'spokenChunks': [
        for (final chunk in chunks)
          {
            'chunkId': chunk.chunkId,
            'startWord': chunk.startWordIndex,
            'endWord': chunk.endWordIndex,
            'completed': chunk.completed,
            'sceneTurns': chunk.sceneTurns.map((t) => t.toMap()).toList(),
          },
      ],
    });
    if (chunks.isEmpty ||
        expected <= 0 ||
        expected != c.document.wordCount ||
        end != expected ||
        !c.isPreparationComplete ||
        !c.hasCompleteDocumentSnapshot ||
        maxPosition < 500) {
      throw StateError('Incomplete original source: $end/$expected');
    }
    final queued = await Future.wait(checks.values);
    receipt['queuedAudio'] = queued;
    if (overflow ||
        queued.length < 2 ||
        queued.any((q) => q['error'] != null)) {
      throw StateError(
        'Need at least two real queued WAVs with complete evidence',
      );
    }
    final peak = queued.map((q) => q['peakPcm16']! as int).reduce(math.max);
    receipt['peakPcm16'] = peak;
    if (peak < 100) throw StateError('Silent queued audio');
    phase = 'save-complete-audio-book';
    final saved = await c.exportDocumentToPath(
      '${root.path}/complete.radoc',
      audioBook: true,
    );
    if (saved == null) throw StateError('Complete audio book save failed');
    final package = RadocAudioPackage();
    try {
      final book = await package.open(saved);
      if (!book.manifest.renderingComplete ||
          book.manifest.totalWords != expected) {
        throw StateError('Saved book extent incomplete');
      }
      receipt['completeAudioBook'] = saved.path;
      receipt['completeScenes'] = [
        for (final s in book.manifest.scenes)
          {
            'sceneId': s.sceneId,
            'startWord': s.startWord,
            'endWord': s.endWord,
            'audioPath': (await (await package.materializeMember(
              book,
              s.audioMember,
            )).copy('${root.path}/complete-${s.sceneId}.wav')).path,
            'rawArtifactIdentity': s.provenance['rawArtifactIdentity'],
          },
      ];
    } finally {
      await package.dispose();
    }
    receipt['functionalPassed'] = true;
    receipt['passed'] = true;
  } catch (error, stack) {
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
  } finally {
    phase = 'shutdown';
    heartbeat.cancel();
    final native = await nativeMain.close();
    receipt['nativeMainResponsiveness'] = native;
    if (maxDelay > 250 || native['passed'] != true) receipt['passed'] = false;
    final cleanup = <String>[];
    for (final operation in <Future<void> Function()>[
      engine.stop,
      c.shutdownPreparation,
      engine.shutdownResources,
    ]) {
      try {
        await operation().timeout(const Duration(seconds: 45));
      } catch (error) {
        cleanup.add('$error');
      }
    }
    try {
      await play?.timeout(const Duration(seconds: 5));
    } catch (error) {
      cleanup.add('$error');
    }
    await sequence.cancel();
    await position.cancel();
    await copying;
    PlaybackInstrumentationService.instance.observer = null;
    await metrics.close();
    await positions.close();
    receipt.addAll({
      'maxNativePositionMs': maxPosition,
      'maxUiHeartbeatDelayMs': maxDelay,
      'delayedTicks': delays,
      'synthesisCallbacks': synthesisCalls,
      'resourceShutdownComplete': cleanup.isEmpty,
      'shutdownErrors': cleanup,
      'normalQuit': 'runner must request and verify',
      'elapsedMs': clock.elapsedMilliseconds,
    });
    if (cleanup.isNotEmpty) receipt['passed'] = false;
    final staged = File('${output.path}.pending');
    await staged.writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt),
      flush: true,
    );
    await staged.rename(output.path);
    stdout.writeln(
      'RADOC_FIRST_LOAD_COMPLETE passed=${receipt['passed']} receipt=${output.path}',
    );
  }
}

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
