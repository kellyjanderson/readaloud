// Running-app transport probe. Queue events are not an acoustic loopback test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';

class _ProbeController extends ReaderController {
  _ProbeController(KokoroTtsEngine engine)
    : super(ttsEngine: engine, enablePlatformIntakeChannels: false);
  Future<void>? _initialization;
  @override
  Future<void> initialize() => _initialization ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.length != 2) {
    throw ArgumentError('NEW_OUTPUT_DIRECTORY SOURCE_COMMIT');
  }
  final output = Directory(arguments.first);
  if (await output.exists()) {
    throw StateError('Output directory already exists');
  }
  await output.create(recursive: true);
  final sink = File('${output.path}/events.jsonl').openWrite();
  final watch = Stopwatch()..start();
  void record(String kind, Map<String, Object?> data) {
    final value = {
      'kind': kind,
      'elapsedMs': watch.elapsedMilliseconds,
      'rssBytes': ProcessInfo.currentRss,
      ...data,
    };
    sink.writeln(jsonEncode(value));
    stdout.writeln('READALOUD_P3 ${jsonEncode(value)}');
  }

  final player = AudioPlayer();
  final engine = KokoroTtsEngine(player: player);
  final controller = _ProbeController(engine);
  var phase = 'initialize';
  var completion = Completer<void>();
  final files = <String>{};
  final subscriptions = <StreamSubscription<dynamic>>[
    player.playerStateStream.listen((state) {
      record('playerState', {
        'phase': phase,
        'playing': state.playing,
        'processing': state.processingState.name,
        'index': player.currentIndex,
        'positionMs': player.position.inMilliseconds,
      });
      if (state.processingState == ProcessingState.completed &&
          !completion.isCompleted) {
        completion.complete();
      }
    }),
    player.sequenceStream.listen((sequence) {
      for (final source in sequence) {
        if (source is UriAudioSource && source.uri.scheme == 'file') {
          files.add(source.uri.toFilePath());
        }
      }
      record('sequence', {
        'phase': phase,
        'count': sequence.length,
        'index': player.currentIndex,
        'positionMs': player.position.inMilliseconds,
      });
    }),
  ];
  final seenMetrics = <PlaybackMetricRecord>{};
  var lastTick = watch.elapsedMilliseconds;
  final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final now = watch.elapsedMilliseconds;
    record('sample', {
      'phase': phase,
      'tickDelayMs': now - lastTick,
      'playing': player.playing,
      'processing': player.processingState.name,
      'index': player.currentIndex,
      'positionMs': player.position.inMilliseconds,
      'sequenceCount': player.sequence.length,
      'status': controller.statusMessage,
    });
    lastTick = now;
    for (final metric in PlaybackInstrumentationService.instance.snapshot()) {
      if (seenMetrics.add(metric)) record('metric', metric.toMap());
    }
  });
  record('start', {
    'sourceCommit': arguments[1],
    'startupSeconds': 4,
    'lowSeconds': 4,
    'highSeconds': 8,
    'maxChunks': 64,
  });
  runApp(ReadAloudApp(controller: controller));
  try {
    await controller.initialize();
    const paragraphs = [
      'John said, "The morning train is nearly here." He put the blue suitcase beside the door and checked the clock. "We still have time," Maria replied.',
      'Outside, a cold wind moved through the trees. A cyclist passed the gate while three children waited quietly at the crossing. The station bell rang twice.',
      '"Did you remember the tickets?" John asked. Maria opened her coat pocket. "Yes, and the little map you drew yesterday." They laughed and started down the narrow path.',
      'At the corner, a delivery truck stopped beside the bakery. Fresh bread scented the air, and someone called a cheerful greeting from an upstairs window.',
      '"Look at that sky," Maria said. Above the rooftops the clouds were turning gold. Their hurried walk slowed for a moment, then the distant train whistle sent them onward.',
    ];
    await File(
      '${output.path}/fixture.txt',
    ).writeAsString(paragraphs.join('\n\n'));
    await controller.importPastedText(paragraphs.join('\n\n'));
    for (final speed in [1.0, 1.5]) {
      phase = 'speed-$speed';
      completion = Completer<void>();
      await controller.setVoiceSpeed(speed);
      record('playRequested', {'phase': phase});
      await controller.startPlayback();
      record('playStarted', {
        'phase': phase,
        'playing': player.playing,
        'sequenceCount': player.sequence.length,
        'status': controller.statusMessage,
      });
      if (!player.playing) {
        throw StateError('Playback did not start: ${controller.statusMessage}');
      }
      await Future<void>.delayed(const Duration(seconds: 7));
      record('exportRequested', {'phase': phase});
      final export = controller.exportAudioToPath(
        '${output.path}/export-$speed.wav',
      );
      await completion.future.timeout(const Duration(minutes: 3));
      record('playCompleted', {'phase': phase});
      final result = await export.timeout(const Duration(minutes: 3));
      record('exportCompleted', {
        'phase': phase,
        'path': result?.outputPath,
        'status': controller.statusMessage,
      });
      if (result == null) throw StateError('Concurrent export failed');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    phase = 'interactive';
    record('interactiveReady', {'seconds': 40});
    await Future<void>.delayed(const Duration(seconds: 40));
    await controller.pausePlayback();
    await engine.shutdownResources();
    await controller.shutdownPreparation();
    record('success', {'audioFiles': files.toList()});
  } catch (error, stack) {
    record('failure', {'error': '$error', 'stack': '$stack'});
    await engine.shutdownResources();
  } finally {
    timer.cancel();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await File(
      '${output.path}/audio-files.json',
    ).writeAsString(jsonEncode(files.toList()));
    await sink.flush();
    await sink.close();
    exit(0);
  }
}
