// Real controller/player proof. Deliberate startup barriers are labeled;
// PCM, frame timing, input actions and listening remain separate evidence.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase;
import 'package:flutter/foundation.dart' show compute;
import 'package:crypto/crypto.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';

class _Controller extends ReaderController {
  _Controller(KokoroTtsEngine engine)
    : super(ttsEngine: engine, enablePlatformIntakeChannels: false);
  Future<void>? _initializing;
  @override
  Future<void> initialize() => _initializing ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

class _ObservedPins extends AudioArtifactPins {
  final paths = <String>{};
  @override
  AudioArtifactPin pin(String path) {
    paths.add(path);
    return super.pin(path);
  }

  int get total => paths.fold(0, (sum, path) => sum + pinCount(path));
}

Future<String> _digest(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 2) {
    throw ArgumentError('NEW_OUTPUT_DIRECTORY SOURCE_COMMIT');
  }
  final output = Directory(args[0]);
  if (output.existsSync()) throw StateError('Output already exists');
  output.createSync(recursive: true);
  final sink = File('${output.path}/events.jsonl').openWrite();
  final watch = Stopwatch()..start();
  var phase = 'initialize';
  var open = true;
  void record(String kind, Map<String, Object?> data) {
    if (!open) return;
    final row = {
      'kind': kind,
      'elapsedMs': watch.elapsedMilliseconds,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'phase': phase,
      ...data,
    };
    sink.writeln(jsonEncode(row));
    stdout.writeln('READALOUD_P4 ${jsonEncode(row)}');
  }

  final player = AudioPlayer(useLazyPreparation: false);
  final pins = _ObservedPins();
  Completer<void>? held;
  Completer<void>? entered;
  var holdNext = false;
  final engine = KokoroTtsEngine(
    player: player,
    artifactPins: pins,
    beforeSynthesis: () async {
      if (!holdNext) return;
      holdNext = false;
      record('startupBarrierEntered', {});
      entered!.complete();
      await held!.future;
    },
  );
  final controller = _Controller(engine);
  String? source() => player.sequenceState.currentSource is UriAudioSource
      ? (player.sequenceState.currentSource! as UriAudioSource).uri.toFilePath()
      : null;
  Map<String, Object?> snapshot() => {
    'playing': player.playing,
    'processing': player.processingState.name,
    'positionMs': player.position.inMilliseconds,
    'source': source(),
    'sources': player.sequence.length,
    'word': controller.currentWordIndex,
    'wordCount': controller.document.wordCount,
    'requested': controller.voiceAssignmentState.requestedDefaultVoiceId,
    'effective': controller.voiceAssignmentState.effectiveDefaultVoiceId,
    'requestedRevision': controller.voiceAssignmentState.requestedRevision,
    'effectiveRevision': controller.voiceAssignmentState.effectiveRevision,
    'assignmentPhase': controller.voiceAssignmentState.phase.name,
    'pending': controller.voiceAssignmentState.hasPending,
    'exporting': controller.isExporting,
    'playbackPins': engine.debugPlaybackPinCount,
    'allPins': pins.total,
    'preparationTasks': engine.pendingPlaybackPreparationTasks,
    'leadMs': engine.debugPlayableBufferedLead.inMilliseconds,
    'requestedCastVoices': controller.voiceAssignmentState.requestedCastVoices,
    'effectiveCastVoices': controller.voiceAssignmentState.effectiveCastVoices,
    'queuePins': {
      for (final audio in player.sequence)
        if (audio is UriAudioSource && audio.uri.scheme == 'file')
          audio.uri.toFilePath(): pins.pinCount(audio.uri.toFilePath()),
    },
  };
  Future<void> until(
    bool Function() predicate,
    String description, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Timed out: $description; ${jsonEncode(snapshot())}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  void frames(List<FrameTiming> values) {
    for (final frame in values) {
      record('frameTiming', {
        'buildUs': frame.buildDuration.inMicroseconds,
        'rasterUs': frame.rasterDuration.inMicroseconds,
        'totalUs': frame.totalSpan.inMicroseconds,
        'engineBuildStartUs': frame.timestampInMicroseconds(
          FramePhase.buildStart,
        ),
      });
    }
  }

  SchedulerBinding.instance.addTimingsCallback(frames);
  final seen = <PlaybackMetricRecord>{};
  var lastTick = watch.elapsedMilliseconds;
  var actionLines = 0;
  final samples = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final now = watch.elapsedMilliseconds;
    record('sample', {'tickDelayMs': now - lastTick, ...snapshot()});
    lastTick = now;
    for (final metric in PlaybackInstrumentationService.instance.snapshot()) {
      if (seen.add(metric)) record('metric', metric.toMap());
    }
    final actions = File('${output.path}/input-actions.jsonl');
    if (phase == 'ui-input' && actions.existsSync()) {
      final lines = actions.readAsLinesSync();
      for (final line in lines.skip(actionLines)) {
        record('uiAction', {'action': jsonDecode(line), ...snapshot()});
      }
      actionLines = lines.length;
    }
  });
  final playerEvents = player.playerStateStream.listen(
    (state) => record('playerState', snapshot()),
  );
  record('provenance', {
    'sourceCommit': args[1],
    'pid': pid,
    'platform': Platform.operatingSystemVersion,
    'fixtureOnly': true,
  });
  runApp(ReadAloudApp(controller: controller));
  var success = false;
  try {
    await controller.initialize();
    const paragraphs = [
      'John said, "The morning train is nearly here." He put the blue suitcase beside the door and checked the clock. "We still have time," Maria replied.',
      'Outside, a cold wind moved through the trees. A cyclist passed the gate while three children waited quietly at the crossing. The station bell rang twice.',
      '"Did you remember the tickets?" John asked. Maria opened her coat pocket. "Yes, and the little map you drew yesterday." They laughed and started down the narrow path.',
      'At the corner, a delivery truck stopped beside the bakery. Fresh bread scented the air, and someone called a cheerful greeting from an upstairs window.',
      '"Look at that sky," Maria said. Above the rooftops the clouds were turning gold. Their hurried walk slowed for a moment, then the distant train whistle sent them onward.',
    ];
    final text = List.generate(3, (_) => paragraphs.join('\n\n')).join('\n\n');
    await File('${output.path}/fixture.txt').writeAsString(text);
    await controller.importPastedText(text);
    await controller.startPlayback();
    await until(
      () =>
          player.playing &&
          player.processingState == ProcessingState.ready &&
          player.position > Duration.zero &&
          !controller.voiceAssignmentState.hasPending,
      'A actual native advancement and ack',
    );
    phase = 'ui-input';
    final exportingA = controller.exportAudioToPath(
      '${output.path}/effective-a.wav',
    );
    await until(
      () =>
          controller.isExporting && engine.pendingPlaybackPreparationTasks > 0,
      'captured A export and refill producer',
    );
    record('inputReady', snapshot());
    await File(
      '${output.path}/input-ready.json',
    ).writeAsString(jsonEncode(snapshot()));
    await until(
      () => File('${output.path}/input.done').existsSync(),
      'explicit UI input handoff',
      timeout: const Duration(minutes: 4),
    );
    record('inputFinished', snapshot());
    await exportingA;
    phase = 'pending-edit';
    if (!player.playing ||
        player.processingState == ProcessingState.completed) {
      await controller.startPlayback();
    }
    await until(
      () =>
          player.playing &&
          player.processingState == ProcessingState.ready &&
          engine.debugPlayableBufferedLead >= const Duration(seconds: 8) &&
          (engine.debugCurrentChunkDuration ?? Duration.zero) -
                  player.position >
              const Duration(seconds: 2),
      'full buffer with stable current source',
    );
    final oldSource = source()!;
    final oldHash = await compute(_digest, oldSource);
    final oldPosition = player.position;
    final oldEffective =
        controller.voiceAssignmentState.effectiveDefaultVoiceId;
    final aExport = controller.exportAudioToPath(
      '${output.path}/captured-a.wav',
    );
    await until(() => controller.isExporting, 'A export before pending edit');
    final replacementVoice = controller.voices
        .firstWhere((v) => v.id == 'af_heart')
        .id;
    record('beforePendingEdit', snapshot());
    await controller.selectVoiceById(replacementVoice);
    record('afterPendingEdit', snapshot());
    if (source() != oldSource ||
        player.position < oldPosition ||
        !player.playing ||
        controller.voiceAssignmentState.effectiveDefaultVoiceId !=
            oldEffective) {
      throw StateError('Assignment edit changed current audio');
    }
    if (await compute(_digest, oldSource) != oldHash) {
      throw StateError('Pinned current WAV mutated');
    }
    if (await controller.exportAudioToPath(
          '${output.path}/refused-pending.wav',
        ) !=
        null) {
      throw StateError('Pending export was not refused');
    }
    if (await aExport == null) {
      throw StateError('Captured effective A export failed after pending edit');
    }
    final anchor = engine.currentPlaybackResumeAnchor!;
    record('applyRequested', {
      'anchorWord': anchor.startWordIndex,
      'anchorChunk': anchor.chunkId,
      ...snapshot(),
    });
    await controller.applyPendingVoiceAssignments();
    await until(
      () =>
          !controller.voiceAssignmentState.hasPending &&
          player.playing &&
          player.processingState == ProcessingState.ready &&
          player.position > Duration.zero,
      'B acknowledged actual playback',
    );
    final bAnchor = engine.currentPlaybackResumeAnchor!;
    record('applyAcknowledged', {
      'anchorWord': bAnchor.startWordIndex,
      ...snapshot(),
    });
    if (bAnchor.startWordIndex != anchor.startWordIndex ||
        controller.voiceAssignmentState.effectiveDefaultVoiceId !=
            replacementVoice) {
      throw StateError(
        'New assignment skipped replay anchor or committed wrong choices',
      );
    }
    if (await controller.exportAudioToPath('${output.path}/effective-b.wav') ==
        null) {
      throw StateError('B export failed');
    }
    await controller.pausePlayback();
    phase = 'initial-abc';
    await controller.importPastedText(paragraphs.join('\n\n'));
    await controller.selectVoiceById('af_bella');
    held = Completer<void>();
    entered = Completer<void>();
    holdNext = true;
    final startingA = controller.startPlayback();
    await entered.future.timeout(const Duration(seconds: 90));
    if (player.playing) {
      throw StateError('A started before held startup barrier');
    }
    await controller.selectVoiceById('af_heart');
    await controller.selectVoiceById('am_fenrir');
    record('abcLatestRequested', snapshot());
    held.complete();
    await startingA;
    await until(
      () =>
          player.playing &&
          player.processingState == ProcessingState.ready &&
          player.position > Duration.zero &&
          !controller.voiceAssignmentState.hasPending,
      'latest C alone starts',
    );
    record('abcAcknowledged', snapshot());
    if (controller.voiceAssignmentState.effectiveDefaultVoiceId !=
        'am_fenrir') {
      throw StateError('Stale startup won over C');
    }
    await controller.pausePlayback();
    record('pausedPinsRetained', snapshot());
    if (pins.total == 0 || player.sequence.isEmpty) {
      throw StateError('Pause prematurely removed native sources/pins');
    }
    await engine.stop();
    if (pins.total != 0 ||
        engine.debugPlaybackPinCount != 0 ||
        player.sequence.isNotEmpty) {
      throw StateError('Native stop did not release pins after clear');
    }
    record('nativePinsDrained', snapshot());
    phase = 'listening-ready';
    await controller.importPastedText(
      'John said, "The quiet river is beautiful today." Maria replied, "We can walk home together."',
    );
    await controller.selectVoiceById('af_bella');
    controller.showStatusMessage(
      'Listening fixture ready. Press Play when ready; voice changes remain pending until Apply or Play.',
    );
    record('listeningReady', snapshot());
    await File(
      '${output.path}/listening-ready.json',
    ).writeAsString(jsonEncode(snapshot()));
    await until(
      () => File('${output.path}/finish.signal').existsSync(),
      'listening/input release',
      timeout: const Duration(minutes: 30),
    );
    success = true;
  } catch (error, stack) {
    record('failure', {'error': '$error', 'stack': '$stack', ...snapshot()});
  } finally {
    samples.cancel();
    SchedulerBinding.instance.removeTimingsCallback(frames);
    if (held != null && !held.isCompleted) held.complete();
    await controller.pausePlayback();
    await engine.shutdownResources();
    record('finalDrain', snapshot());
    await playerEvents.cancel();
    await File(
      '${output.path}/audio-files.json',
    ).writeAsString(jsonEncode(pins.paths.toList()));
    record(success ? 'success' : 'failed', {});
    controller.dispose();
    await sink.flush();
    open = false;
    await sink.close();
    exit(success ? 0 : 1);
  }
}
