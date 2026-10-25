// Running-app transport probe. Queue events are not an acoustic loopback test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/spoken_chunk_record.dart';
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
  var imposedSynthesisDelay = Duration.zero;
  final engine = KokoroTtsEngine(
    player: player,
    beforeSynthesis: () async {
      if (imposedSynthesisDelay > Duration.zero) {
        await Future<void>.delayed(imposedSynthesisDelay);
      }
    },
  );
  final controller = _ProbeController(engine);
  var phase = 'initialize';
  var completion = Completer<void>();
  String? phaseFailure;
  var succeeded = false;
  final files = <String>{};
  final subscriptions = <StreamSubscription<dynamic>>[
    player.playerStateStream.listen((state) {
      record('playerState', {
        'phase': phase,
        'playing': state.playing,
        'processing': state.processingState.name,
        'index': player.currentIndex,
        'positionMs': player.position.inMilliseconds,
        'wordIndex': controller.currentWordIndex,
        'wordCount': controller.document.wordCount,
      });
      // A completed native playlist may be an underrun while more source
      // remains. Only the controller's document-complete transition ends a
      // scenario; otherwise the stress case could silently skip the suffix.
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
        'paths': [
          for (final source in sequence)
            if (source is UriAudioSource && source.uri.scheme == 'file')
              source.uri.toFilePath(),
        ],
      });
    }),
  ];
  void observeController() {
    if (controller.playbackState == ReaderPlaybackPrimaryState.failed) {
      phaseFailure = controller.statusMessage ?? 'Controller playback failed';
      record('controllerFailure', {'phase': phase, 'error': phaseFailure});
      if (!completion.isCompleted) completion.complete();
    } else if (controller.playbackState ==
            ReaderPlaybackPrimaryState.completed &&
        !completion.isCompleted) {
      record('documentCompleted', {
        'phase': phase,
        'wordIndex': controller.currentWordIndex,
        'wordCount': controller.document.wordCount,
      });
      completion.complete();
    }
  }

  controller.addListener(observeController);
  final seenMetrics = <PlaybackMetricRecord>{};
  var lastTick = watch.elapsedMilliseconds;
  final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final now = watch.elapsedMilliseconds;
    record('sample', {
      'phase': phase,
      'tickDelayMs': now - lastTick,
      'playing': player.playing,
      'playerSpeed': player.speed,
      'synthesisRate': controller.currentSpeed,
      'processing': player.processingState.name,
      'index': player.currentIndex,
      'positionMs': player.position.inMilliseconds,
      'sequenceCount': player.sequence.length,
      'wordIndex': controller.currentWordIndex,
      'wordCount': controller.document.wordCount,
      'controllerState': controller.playbackState.name,
      'currentSource': switch (player.sequenceState.currentSource) {
        final UriAudioSource source => source.uri.toString(),
        _ => null,
      },
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
    for (final scenario in [(1.0, 1.0), (1.5, 1.0), (1.0, 1.5), (1.0, 8.0)]) {
      final speed = scenario.$1;
      final transportSpeed = scenario.$2;
      imposedSynthesisDelay = transportSpeed == 8
          ? const Duration(milliseconds: 800)
          : Duration.zero;
      await player.setSpeed(1.0);
      phase = 'configure-$speed-player-$transportSpeed';
      completion = Completer<void>();
      phaseFailure = null;
      await controller.setVoiceSpeed(speed);
      phase = 'synthesis-${controller.currentSpeed}-player-$transportSpeed';
      record('playRequested', {
        'phase': phase,
        'requestedSynthesisRate': speed,
        'effectiveSynthesisRate': controller.currentSpeed,
        'transportSpeed': transportSpeed,
        'imposedSynthesisDelayMs': imposedSynthesisDelay.inMilliseconds,
      });
      await controller.startPlayback();
      final startupDeadline = DateTime.now().add(const Duration(seconds: 30));
      while (!player.playing &&
          phaseFailure == null &&
          DateTime.now().isBefore(startupDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      record('playStarted', {
        'phase': phase,
        'playing': player.playing,
        'playerSpeed': player.speed,
        'synthesisRate': controller.currentSpeed,
        'sequenceCount': player.sequence.length,
        'status': controller.statusMessage,
      });
      if (!player.playing) {
        throw StateError('Playback did not start: ${controller.statusMessage}');
      }
      await player.setSpeed(transportSpeed);
      record('transportSpeedSet', {'speed': transportSpeed});
      await Future<void>.delayed(const Duration(seconds: 2));
      record('exportRequested', {'phase': phase});
      final export = controller.exportAudioToPath(
        '${output.path}/export-${controller.currentSpeed}-$transportSpeed.wav',
      );
      await completion.future.timeout(const Duration(minutes: 3));
      if (phaseFailure != null) throw StateError(phaseFailure!);
      if (controller.currentWordIndex < controller.document.wordCount - 1) {
        throw StateError('Playback completion omitted a document suffix');
      }
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
    succeeded = true;
  } catch (error, stack) {
    record('failure', {'error': '$error', 'stack': '$stack'});
    await engine.stop();
    await engine.shutdownResources();
  } finally {
    timer.cancel();
    controller.removeListener(observeController);
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await File(
      '${output.path}/audio-files.json',
    ).writeAsString(jsonEncode(files.toList()));
    await sink.flush();
    await sink.close();
    exit(succeeded ? 0 : 1);
  }
}
