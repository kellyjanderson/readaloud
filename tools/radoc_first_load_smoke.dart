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
import 'package:read_aloud/src/services/native_speech_work_activity.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';
import 'package:read_aloud/src/services/radoc_audio_package.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/rendered_scene_repository.dart';
import 'package:read_aloud/src/services/work_character_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_main_responsiveness_probe.dart';
import 'native_playback_position_probe.dart';
import 'native_timing_clock.dart';

// This separate scope deliberately captures only sendable paths. A closure
// created inside main's stream callback can retain its unsendable owner context.
Future<Map<String, Object?>> copyQueuedAudioEvidence(
  String source,
  String destination,
) => Isolate.run(() async {
  await File(source).copy(destination);
  return _inspectWav(destination);
});

/// The last spoken record owns the active scene. Its end is the exclusive
/// heard-coverage boundary, not the complete parent scene's end; the current
/// word may equal that boundary before final scene duration is published.
bool hasUnknownActiveSpokenScene(
  Iterable<SpokenChunkRecord> records, {
  required String documentId,
  required int currentWordIndex,
}) {
  if (records.isEmpty) return false;
  final active = records.last;
  return active.documentId == documentId &&
      !active.completed &&
      active.audioDuration == Duration.zero &&
      active.startWordIndex <= currentWordIndex &&
      currentWordIndex <= active.endWordIndex;
}

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

Future<void> main(
  List<String> args, {
  bool packetCancellation = false,
  bool loadAfterStartup = false,
}) async {
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
    'schema': packetCancellation
        ? 'readaloud-native-packet-cancellation-v1'
        : 'readaloud-native-first-load-v1',
    'passed': false,
    'engine': args[0],
    'input': args[1],
    'runRoot': root.path,
    'dartEntryUnixMicros': entered,
    'controlledCaptureGate': false,
    'timingMode': loadAfterStartup
        ? 'load-after-startup'
        : 'launch-with-document-diagnostic',
    'documentLoadClockScope': loadAfterStartup
        ? 'Explicit target import after ordinary no-target app startup; all '
              'target intake, preparation, binding and synthesis included'
        : 'No independent post-startup target load; launch diagnostic only',
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
  var completedExports = 0;
  var completedOrdinaryScenes = 0;
  List<Map<String, Object?>> spokenScenes() => [
    for (final chunk in c.spokenChunkRecords)
      {
        'chunkId': chunk.chunkId,
        'startWord': chunk.startWordIndex,
        'endWord': chunk.endWordIndex,
        'audioDurationMicros': chunk.audioDuration.inMicroseconds,
        'completed': chunk.completed,
      },
  ];
  bool hasUnknownActiveScene() => hasUnknownActiveSpokenScene(
    c.spokenChunkRecords,
    documentId: c.document.displayDocument.documentId,
    currentWordIndex: c.currentWordIndex,
  );
  int? completedExportsAtFirstPosition;
  Map<String, Object?>? firstPacketState;
  PlaybackInstrumentationService.instance.observer = (event) {
    if (event.metric == 'exportChunkReady') completedExports++;
    if (event.metric == 'chunkRegenerated') completedOrdinaryScenes++;
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
      if (checks.length >= 512) {
        overflow = true;
        continue;
      }
      final index = checks.length;
      final destination = '${root.path}/queued-$index.wav';
      final check = copying
          .then((_) => copyQueuedAudioEvidence(path, destination))
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
  final playerStates = <Map<String, Object?>>[];
  var playerStateOverflow = false;
  final playerStateSubscription = player.playerStateStream.listen((state) {
    if (!packetCancellation) return;
    if (playerStates.length >= 256) {
      playerStateOverflow = true;
      return;
    }
    playerStates.add({
      'elapsedMs': clock.elapsedMilliseconds,
      'unixMicros': DateTime.now().microsecondsSinceEpoch,
      'phase': phase,
      'playing': state.playing,
      'processingState': state.processingState.name,
      'positionMs': player.position.inMilliseconds,
      'index': player.currentIndex,
    });
  });
  final nativePosition = NativePlaybackPositionProbe(player);
  final position = player.positionStream.listen((p) {
    nativePosition.sample(p);
    if (player.playing && p > Duration.zero) {
      if (firstPosition == null) {
        firstPosition = DateTime.now().microsecondsSinceEpoch;
        completedExportsAtFirstPosition = completedExports;
        firstPacketState = {
          'elapsedMs': clock.elapsedMilliseconds,
          'unixMicros': firstPosition,
          'nativePositionMs': p.inMilliseconds,
          'nativeIndex': player.currentIndex,
          'queuedSources': player.sequence.length,
          'source': player.audioSource?.toString(),
          'completedExports': completedExports,
          'completedOrdinaryScenes': completedOrdinaryScenes,
          'unknownActiveScene': hasUnknownActiveScene(),
          'spokenScenes': spokenScenes(),
          'pendingPlaybackPreparationTasks':
              engine.pendingPlaybackPreparationTasks,
          'playbackPins': engine.debugPlaybackPinCount,
        };
      }
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
  Future<void>? targetImport;
  Object? playError;
  String? startupDocumentId;
  runApp(
    ReadAloudApp(
      controller: c,
      launchOptions: AppLaunchOptions(
        inputPaths: loadAfterStartup ? const [] : [args[1]],
      ),
    ),
  );
  var previousResourceStage = '';
  final resourceStages = <Map<String, Object?>>[];
  receipt['resourceStages'] = resourceStages;
  c.addListener(() {
    final progress = c.speechResourceProgress;
    final stage = progress?.stage ?? '';
    if (stage.isEmpty ||
        stage == previousResourceStage ||
        resourceStages.length >= 128) {
      return;
    }
    previousResourceStage = stage;
    final event = <String, Object?>{
      'elapsedMs': clock.elapsedMilliseconds,
      'stage': stage,
      'message': progress?.message,
    };
    resourceStages.add(event);
    stdout.writeln('RADOC_FIRST_LOAD_RESOURCE ${jsonEncode(event)}');
  });
  try {
    if (loadAfterStartup) {
      phase = 'ordinary-app-startup';
      await c.initialize();
      // The screen uses this same existing intake/model-startup path. The
      // cached initialize future and production retry owner prevent duplicates.
      await WidgetsBinding.instance.endOfFrame;
      await c.completeInitialIntake();
      checkFailure();
      if (c.isInitializing ||
          synthesisCalls != 0 ||
          checks.isNotEmpty ||
          player.sequence.isNotEmpty ||
          player.playing ||
          firstPosition != null) {
        throw StateError('Ordinary startup synthesized or admitted audio');
      }
      receipt['startupSynthesisCallbacks'] = synthesisCalls;
      receipt['startupNativeSources'] = player.sequence.length;
      receipt['startupPreparedWordCount'] = c.preparedWordCount;
      startupDocumentId = c.document.displayDocument.documentId;
      receipt['startupDocumentId'] = startupDocumentId;
      (await NativeTimingClockSnapshot.capture()).record(
        receipt,
        'appStartupComplete',
      );
      phase = 'target-document-load';
      (await NativeTimingClockSnapshot.capture()).record(
        receipt,
        'documentLoadRequested',
      );
      // Invoke the real intake immediately after the native timestamp. Do not
      // await whole-document completion before registering target Play.
      targetImport = c.importFilePaths([args[1]]).catchError((Object error) {
        playError = error;
      });
    }
    if (packetCancellation) {
      receipt['cancellationScope'] =
          'Controller commands through normal app/player; native flags and '
          'positions do not establish emitted silence or keyboard/mouse input.';
      final events = <Map<String, Object?>>[];
      receipt['cancellationEvents'] = events;
      Map<String, Object?> snapshot(String event) => {
        'event': event,
        'elapsedMs': clock.elapsedMilliseconds,
        'unixMicros': DateTime.now().microsecondsSinceEpoch,
        'stage': c.speechResourceProgress?.stage,
        'initializing': c.isInitializing,
        'pendingIntent': c.hasPendingPlaybackIntent,
        'controllerState': c.playbackState.name,
        'playerPlaying': player.playing,
        'playerProcessingState': player.processingState.name,
        'nativePositionMs': player.position.inMilliseconds,
        'nativeIndex': player.currentIndex,
        'queuedSources': player.sequence.length,
        'completedExports': completedExports,
        'completedOrdinaryScenes': completedOrdinaryScenes,
        'unknownActiveScene': hasUnknownActiveScene(),
        'spokenScenes': spokenScenes(),
        'pendingPlaybackPreparationTasks':
            engine.pendingPlaybackPreparationTasks,
        'playbackPins': engine.debugPlaybackPinCount,
      };
      Future<void> observeStopped(String label) async {
        // Poll alongside the player-state stream (below), catching transient
        // resume as well as sustained playback. This is native-state evidence.
        final end = clock.elapsedMilliseconds + 1000;
        while (clock.elapsedMilliseconds < end) {
          if (player.playing || c.isPlaying || c.hasPendingPlaybackIntent) {
            throw StateError('$label: stale playback resumed');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      await until(() => c.preparedWordCount > 0, 'First prepared content');
      phase = 'cold-pending-play';
      play = c.startPlayback().catchError((Object error) {
        playError = error;
      });
      await until(
        () => c.speechResourceProgress?.stage == 'modelLoad',
        'Cold modelLoad stage (required, no warm substitution)',
      );
      if (!c.hasPendingPlaybackIntent ||
          player.playing ||
          firstPosition != null) {
        throw StateError('Cold modelLoad did not contain pending Play');
      }
      events.add(snapshot('cold-cancel-request'));
      final cancelledAt = clock.elapsedMilliseconds;
      final nativeInput =
          Platform.environment['READALOUD_CANCEL_INPUT_MODE'] == 'native';
      receipt['coldInputMode'] = nativeInput
          ? 'external-native-input'
          : 'controller-command';
      Future<void> coldPause;
      if (nativeInput) {
        // No test-owned pause or model hold: the running app's normal input
        // handler must cancel pending intent during naturally occurring speech
        // initialization. Model stage transitions are not the end of that work.
        // Root owns the actual click/keyboard evidence.
        stdout.writeln(
          'WAITING_NATIVE_CANCEL ${jsonEncode(snapshot('waiting-native-cancel'))}',
        );
        final inputDeadline = clock.elapsedMilliseconds + 15000;
        var lastPendingInitialization = snapshot('native-input-pending');
        while (c.hasPendingPlaybackIntent) {
          if (!c.isInitializing ||
              player.playing ||
              clock.elapsedMilliseconds >= inputDeadline) {
            throw StateError(
              'Native cancellation missed bounded initialization window',
            );
          }
          lastPendingInitialization = snapshot('native-input-pending');
          checkFailure();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        events.add(snapshot('native-cancel-intent-observed'));
        receipt['nativeCancelObservedStage'] = c.speechResourceProgress?.stage;
        receipt['nativeInputLastPendingInitialization'] =
            lastPendingInitialization;
        receipt['nativeInputWaitMs'] = clock.elapsedMilliseconds - cancelledAt;
        receipt['nativeInputEvidence'] =
            'External input and timestamp must be supplied by root';
        coldPause = Future<void>.value();
      } else {
        coldPause = c.pausePlayback();
        // Deliberately sample before awaiting the native drain.
        events.add(snapshot('cold-cancel-immediate-intent'));
        receipt['coldIntentCancellationMs'] =
            clock.elapsedMilliseconds - cancelledAt;
      }
      if (c.hasPendingPlaybackIntent ||
          c.isPlaying ||
          c.playbackState != ReaderPlaybackPrimaryState.paused) {
        throw StateError('Pending Play intent was not cancelled synchronously');
      }
      var staleResume = false;
      final coldStates = player.playerStateStream.listen((state) {
        if (state.playing) staleResume = true;
      });
      try {
        await coldPause.timeout(const Duration(seconds: 45));
        events.add(snapshot('cold-pause-returned'));
        await until(() => !c.isInitializing, 'Cold preparation drain');
        await play.timeout(const Duration(seconds: 5));
        await observeStopped('Cold cancellation');
        events.add(snapshot('cold-preparation-drained'));
        receipt['coldCancelDrainMs'] = clock.elapsedMilliseconds - cancelledAt;
        receipt['coldCancellationActivity'] =
            await NativeSpeechWorkActivity.snapshot();
        if (staleResume ||
            playerStates.any((event) => event['playing'] == true) ||
            firstPosition != null ||
            playError != null) {
          throw StateError(
            'Cold cancellation produced stale playback/error: $playError',
          );
        }
      } finally {
        await coldStates.cancel();
      }

      phase = 'fresh-play-retry';
      events.add(snapshot('retry-play-request'));
      playError = null;
      play = c.startPlayback().catchError((Object error) {
        playError = error;
      });
      await until(
        () => firstPosition != null || playError != null,
        'Retry first real native packet',
      );
      if (playError != null) throw StateError('Retry Play failed: $playError');
      receipt['firstNativePacket'] = firstPacketState;
      receipt['firstNativePositionUnixMicros'] = firstPosition;
      receipt['sceneIncompleteAtFirstPacket'] =
          firstPacketState?['unknownActiveScene'] == true &&
          completedExportsAtFirstPosition == 0 &&
          firstPacketState?['completedOrdinaryScenes'] == 0;
      // Require positive ordinary-pipeline evidence: a real source anchor with
      // unknown final duration, plus native position. Zero export metrics alone
      // would be vacuous for ordinary playback. Ordinary finalization records
      // chunkRegenerated; export finalization records exportChunkReady.
      if (receipt['sceneIncompleteAtFirstPacket'] != true ||
          !hasUnknownActiveScene() ||
          completedOrdinaryScenes != 0 ||
          completedExports != 0) {
        final knownComplete =
            completedOrdinaryScenes != 0 ||
            completedExports != 0 ||
            c.spokenChunkRecords.any(
              (chunk) => chunk.audioDuration > Duration.zero,
            );
        receipt['packetPauseCoverage'] = knownComplete
            ? 'producer already completed; not qualified'
            : 'incomplete-scene source evidence absent; not qualified';
        throw StateError(
          'First native packet was not paused before scene completion',
        );
      }
      phase = 'packet-native-playback-observation';
      final audibleWindowDeadline = clock.elapsedMilliseconds + 5000;
      // Give the external capture a real native playback interval rather than
      // pausing on a sub-millisecond first-position tick. Sampled native time
      // still does not establish emitted speech; root checks the waveform.
      while (nativePosition.sampledPositionTotalMs < 180 || !player.playing) {
        checkFailure();
        if (playError != null) {
          throw StateError('Retry Play failed: $playError');
        }
        if (!hasUnknownActiveScene() ||
            completedOrdinaryScenes != 0 ||
            completedExports != 0) {
          receipt['packetPauseCoverage'] =
              'producer completed before native playback interval; not qualified';
          throw StateError(
            'Scene finalized before 180ms native playback interval',
          );
        }
        if (clock.elapsedMilliseconds >= audibleWindowDeadline) {
          throw TimeoutException(
            'No playing 180ms sampled native interval within 5s',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      receipt['nativePlaybackIntervalBeforePause'] = {
        'elapsedMs': clock.elapsedMilliseconds,
        'unixMicros': DateTime.now().microsecondsSinceEpoch,
        'sampledPositionTotalMs': nativePosition.sampledPositionTotalMs,
        'nativePositionMicros': player.position.inMicroseconds,
        'nativePositionMs': player.position.inMilliseconds,
        'playerPlaying': player.playing,
        'unknownActiveScene': hasUnknownActiveScene(),
        'completedOrdinaryScenes': completedOrdinaryScenes,
        'completedExports': completedExports,
      };
      // Recheck fresh ownership/publication after the observation interval,
      // including when its final position tick also published the scene.
      if (!hasUnknownActiveScene() ||
          completedOrdinaryScenes != 0 ||
          completedExports != 0 ||
          nativePosition.overflow ||
          !player.playing) {
        receipt['packetPauseCoverage'] =
            'incomplete-scene playback interval absent; not qualified';
        throw StateError(
          'Scene was not unfinished and playing immediately before Pause',
        );
      }
      events.add(snapshot('packet-pause-request'));
      phase = 'packet-pause';
      final pauseAt = clock.elapsedMilliseconds;
      final packetPause = c.pausePlayback();
      events.add(snapshot('packet-pause-immediate-intent'));
      receipt['packetIntentCancellationMs'] =
          clock.elapsedMilliseconds - pauseAt;
      if (c.hasPendingPlaybackIntent ||
          c.isPlaying ||
          c.playbackState != ReaderPlaybackPrimaryState.paused) {
        throw StateError(
          'Packet Pause did not clear controller intent immediately',
        );
      }
      await packetPause.timeout(const Duration(seconds: 45));
      events.add(snapshot('packet-pause-returned'));
      receipt['packetPauseDrainMs'] = clock.elapsedMilliseconds - pauseAt;
      var lateResume = false;
      final pausedStates = player.playerStateStream.listen((state) {
        if (state.playing) lateResume = true;
      });
      try {
        await play.timeout(const Duration(seconds: 5));
        await until(
          () => engine.pendingPlaybackPreparationTasks == 0,
          'Packet playback preparation drain',
        );
        await observeStopped('Packet Pause');
        final pauseStates = playerStates
            .where((event) => (event['elapsedMs']! as int) >= pauseAt)
            .toList();
        final stopped = pauseStates.indexWhere(
          (event) => event['playing'] == false,
        );
        if (lateResume ||
            player.playing ||
            stopped < 0 ||
            playerStateOverflow ||
            pauseStates
                .skip(stopped + 1)
                .any((event) => event['playing'] == true)) {
          throw StateError(
            'Native player did not stop or late producer resumed it',
          );
        }
        receipt['nativePlayerStoppedEventIndex'] = playerStates.indexOf(
          pauseStates[stopped],
        );
        receipt['nativePlayerStoppedMs'] = pauseStates[stopped]['elapsedMs'];
        receipt['nativePlayerStopLatencyMs'] =
            (pauseStates[stopped]['elapsedMs']! as int) - pauseAt;
        events.add(snapshot('packet-pause-observation-ended'));
        receipt['packetPauseActivity'] =
            await NativeSpeechWorkActivity.snapshot();
        receipt['packetPauseCoverage'] =
            'native packet before complete scene; paused';
        receipt['functionalPassed'] = true;
        receipt['passed'] = true;
      } finally {
        await pausedStates.cancel();
      }
      return; // The shared finally drains all owners and writes the receipt.
    }
    // Startup-with-document remains an ungated launch diagnostic. The R25
    // mode has finished ordinary startup but never waits for whole TARGET
    // preparation before registering the Play intent.
    await until(
      () =>
          (playError != null) ||
          (c.preparedWordCount > 0 &&
              (!loadAfterStartup ||
                  c.document.displayDocument.documentId != startupDocumentId)),
      'First target prepared content',
    );
    if (playError != null) throw StateError('Target import failed: $playError');
    receipt['playRequestedMs'] = clock.elapsedMilliseconds;
    receipt['preparedWordsAtPlay'] = c.preparedWordCount;
    receipt['targetDocumentIdAtPlay'] = c.document.displayDocument.documentId;
    receipt['preparationCompleteAtPlay'] = c.isPreparationComplete;
    receipt['initializingAtPlay'] = c.isInitializing;
    phase = 'play-request';
    if (loadAfterStartup) {
      (await NativeTimingClockSnapshot.capture()).record(
        receipt,
        'playRequested',
      );
    }
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
    await targetImport;
    if (playError != null) throw StateError('Play failed: $playError');
    final chunks = c.spokenChunkRecords;
    receipt['observedChunkRecords'] = [
      for (final chunk in chunks)
        {
          'chunkId': chunk.chunkId,
          'startWord': chunk.startWordIndex,
          'endWord': chunk.endWordIndex,
          'completed': chunk.completed,
          'durationMicros': chunk.audioDuration.inMicroseconds,
        },
    ];
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
        nativePosition.sampledPositionTotalMs < 500 ||
        nativePosition.overflow) {
      throw StateError('Incomplete original source: $end/$expected');
    }
    final queued = await Future.wait(checks.values);
    receipt['nativePlaybackPositions'] = nativePosition.toMap();
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
      await targetImport?.timeout(const Duration(seconds: 5));
    } catch (error) {
      cleanup.add('$error');
    }
    await playerStateSubscription.cancel();
    await sequence.cancel();
    await position.cancel();
    await copying;
    if (packetCancellation) {
      receipt['queuedAudio'] = await Future.wait(checks.values);
      receipt['playerStateEvents'] = playerStates;
      receipt['playerStateOverflow'] = playerStateOverflow;
      receipt['finalNativeResources'] = {
        'playerPlaying': player.playing,
        'pendingPlaybackPreparationTasks':
            engine.pendingPlaybackPreparationTasks,
        'playbackPins': engine.debugPlaybackPinCount,
        'resourcesReady': engine.resourcesReady,
      };
      final stoppedIndex = receipt['nativePlayerStoppedEventIndex'] as int?;
      final latePlaying =
          stoppedIndex != null &&
          playerStates
              .skip(stoppedIndex + 1)
              .any((event) => event['playing'] == true);
      if (latePlaying ||
          playerStateOverflow ||
          player.playing ||
          engine.pendingPlaybackPreparationTasks != 0 ||
          engine.debugPlaybackPinCount != 0 ||
          engine.resourcesReady) {
        cleanup.add('Native player/work/pins/resources not drained');
      }
    }
    final activity = await NativeSpeechWorkActivity.snapshot();
    receipt['speechWorkActivity'] = activity;
    receipt['speechWorkActivitySuppressed'] =
        Platform.environment['READALOUD_DISABLE_SPEECH_ACTIVITY'] == '1';
    if (activity == null ||
        activity['active'] != 0 ||
        activity['started'] != activity['ended'] ||
        (receipt['speechWorkActivitySuppressed'] != true &&
            (activity['started'] as int? ?? 0) == 0)) {
      cleanup.add('Native speech activity missing, unused or not drained.');
    }
    PlaybackInstrumentationService.instance.observer = null;
    await metrics.close();
    await positions.close();
    receipt.addAll({
      'nativePlaybackPositions': nativePosition.toMap(),
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
