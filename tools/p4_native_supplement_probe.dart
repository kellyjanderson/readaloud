// Supplemental running-app ownership proof. The pre-assembly wait and injected
// failures are deliberate barriers, never normal export/CPU performance claims.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase;
import 'package:crypto/crypto.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/models/voice_assignment_state.dart';
import 'package:read_aloud/src/services/exported_audio_assembler.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'p4_native_assignment_probe.dart' show P4ProbeController, P4ProbePins;

class _AssemblyBarrier extends ExportedAudioAssembler {
  _AssemblyBarrier(this.record);
  final void Function(String, Map<String, Object?>) record;
  bool _armed = false;
  bool _released = false;
  set arm(bool value) {
    _armed = value;
    if (value) {
      cancelled = false;
      _released = false;
    }
  }

  bool held = false;
  bool cancelled = false;
  void Function()? onCancellation;
  Completer<void>? _release;
  @override
  Future<TtsExportResult> assemble(ExportedAudioAssemblyRequest request) async {
    if (_armed) {
      _armed = false;
      if (cancelled) {
        throw StateError('Controlled export cancelled before assembly hold');
      }
      held = true;
      _release = Completer<void>();
      record('assemblyHoldEntered', {
        'chunks': request.chunks.length,
        'diagnosticOnly': true,
      });
      if (_released) _release!.complete();
      try {
        await _release!.future.timeout(const Duration(minutes: 5));
      } finally {
        held = false;
      }
      if (cancelled) throw StateError('Controlled pre-assembly cancellation');
    }
    return super.assemble(request);
  }

  void release() {
    _released = true;
    final gate = _release;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  void cancel() {
    cancelled = true;
    if (held) {
      record('assemblyCancellationRequested', {'diagnosticOnly': true});
      onCancellation?.call();
      release();
    }
    super.cancel();
  }

  @override
  Future<void> shutdown() async {
    cancelled = true;
    release();
    await super.shutdown();
  }
}

class _MutedPlayer extends AudioPlayer {
  _MutedPlayer() : super(useLazyPreparation: false);
  @override
  Future<void> setVolume(double volume) => super.setVolume(0);
}

Future<String> _pcmHash(String path) async {
  final bytes = await File(path).readAsBytes();
  return sha256.convert(bytes.sublist(44)).toString();
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 2) throw ArgumentError('NEW_OUTPUT SOURCE_COMMIT');
  final output = Directory(args[0]);
  if (output.existsSync()) throw StateError('Output exists');
  output.createSync(recursive: true);
  final sink = File('${output.path}/events.jsonl').openWrite();
  final clock = Stopwatch()..start();
  var phase = 'initialize';
  var open = true;
  void record(String kind, Map<String, Object?> data) {
    if (!open) return;
    final row = {
      'kind': kind,
      'elapsedMs': clock.elapsedMilliseconds,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'phase': phase,
      ...data,
    };
    sink.writeln(jsonEncode(row));
    stdout.writeln('READALOUD_P4_SUPPLEMENT ${jsonEncode(row)}');
  }

  final player = _MutedPlayer();
  final pins = P4ProbePins();
  final assembler = _AssemblyBarrier(record);
  var failNext = false;
  var holdNext = false;
  var failHeld = false;
  Completer<void>? synthesisEntered;
  Completer<void>? synthesisRelease;
  final engine = KokoroTtsEngine(
    player: player,
    artifactPins: pins,
    exportAssembler: assembler,
    beforeSynthesis: () async {
      if (failNext) {
        failNext = false;
        record('injectedCurrentFailure', {'diagnosticOnly': true});
        throw StateError('Controlled current pre-ack failure');
      }
      if (!holdNext) return;
      holdNext = false;
      synthesisEntered!.complete();
      record('staleStartupHeld', {'diagnosticOnly': true});
      await synthesisRelease!.future;
      if (failHeld) {
        failHeld = false;
        record('injectedStaleFailure', {'diagnosticOnly': true});
        throw StateError('Controlled obsolete startup A failure');
      }
    },
  );
  final controller = P4ProbeController(engine);
  String? source() => player.sequenceState.currentSource is UriAudioSource
      ? (player.sequenceState.currentSource! as UriAudioSource).uri.toFilePath()
      : null;
  Map<String, Object?> state() => {
    'playing': player.playing,
    'processing': player.processingState.name,
    'positionMs': player.position.inMilliseconds,
    'source': source(),
    'sources': player.sequence.length,
    'word': controller.currentWordIndex,
    'requested': controller.voiceAssignmentState.requestedDefaultVoiceId,
    'effective': controller.voiceAssignmentState.effectiveDefaultVoiceId,
    'requestedRevision': controller.voiceAssignmentState.requestedRevision,
    'effectiveRevision': controller.voiceAssignmentState.effectiveRevision,
    'assignmentPhase': controller.voiceAssignmentState.phase.name,
    'pending': controller.voiceAssignmentState.hasPending,
    'requestedCastVoices': controller.voiceAssignmentState.requestedCastVoices,
    'effectiveCastVoices': controller.voiceAssignmentState.effectiveCastVoices,
    'exporting': controller.isExporting,
    'assemblyHeld': assembler.held,
    'preparationTasks': engine.pendingPlaybackPreparationTasks,
    'playbackPins': engine.debugPlaybackPinCount,
    'allPins': pins.total,
    'leadMs': engine.debugPlayableBufferedLead.inMilliseconds,
    'queuePins': {
      for (final a in player.sequence)
        if (a is UriAudioSource && a.uri.scheme == 'file')
          a.uri.toFilePath(): pins.pinCount(a.uri.toFilePath()),
    },
  };
  Future<void> until(
    bool Function() predicate,
    String label, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Timeout $label ${jsonEncode(state())}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> ready(String label) => until(
    () =>
        player.playing &&
        player.processingState == ProcessingState.ready &&
        player.position > Duration.zero &&
        !controller.voiceAssignmentState.hasPending,
    label,
  );
  Future<void> full() => until(
    () =>
        player.playing &&
        engine.debugPlayableBufferedLead >= const Duration(seconds: 8) &&
        (engine.debugCurrentChunkDuration ?? Duration.zero) - player.position >
            const Duration(seconds: 2),
    'stable full buffer',
  );
  void frames(List<FrameTiming> values) {
    for (final f in values) {
      record('frameTiming', {
        'buildUs': f.buildDuration.inMicroseconds,
        'rasterUs': f.rasterDuration.inMicroseconds,
        'totalUs': f.totalSpan.inMicroseconds,
        'engineBuildStartUs': f.timestampInMicroseconds(FramePhase.buildStart),
      });
    }
  }

  SchedulerBinding.instance.addTimingsCallback(frames);
  var tick = clock.elapsedMilliseconds;
  var actionLines = 0;
  final metrics = <PlaybackMetricRecord>{};
  final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final now = clock.elapsedMilliseconds;
    record('sample', {'tickDelayMs': now - tick, ...state()});
    tick = now;
    for (final m in PlaybackInstrumentationService.instance.snapshot()) {
      if (metrics.add(m)) record('metric', m.toMap());
    }
    final actions = File('${output.path}/input-actions.jsonl');
    if (phase == 'ui-export' && actions.existsSync()) {
      final lines = actions.readAsLinesSync();
      for (final line in lines.skip(actionLines)) {
        record('uiAction', {'action': jsonDecode(line), ...state()});
      }
      actionLines = lines.length;
    }
  });
  final playerEvents = player.playerStateStream.listen(
    (_) => record('playerState', state()),
  );
  record('provenance', {
    'sourceCommit': args[1],
    'pid': pid,
    'os': Platform.operatingSystemVersion,
    'mutedDiagnostic': true,
  });
  runApp(ReadAloudApp(controller: controller));
  var success = false;
  try {
    await controller.initialize();
    const short =
        'John said, "The morning train is nearly here." He put the blue suitcase beside the door and checked the clock. "We still have time," Maria replied.\n\nOutside, a cold wind moved through the trees. A cyclist passed the gate while three children waited quietly at the crossing. The station bell rang twice.\n\n"Did you remember the tickets?" John asked. Maria opened her coat pocket. "Yes, and the little map you drew yesterday." They laughed and started down the narrow path.\n\nAt the corner, a delivery truck stopped beside the bakery. Fresh bread scented the air, and someone called a cheerful greeting from an upstairs window.\n\n"Look at that sky," Maria said. Above the rooftops the clouds were turning gold. Their hurried walk slowed for a moment, then the distant train whistle sent them onward.';
    final long = List.generate(10, (_) => short).join('\n\n');
    await File('${output.path}/fixture-long.txt').writeAsString(long);
    await File('${output.path}/fixture-short.txt').writeAsString(short);
    await controller.importPastedText(long);
    await controller.selectVoiceById('af_bella');
    await controller.startPlayback();
    await ready('initial A');
    phase = 'ui-prebind';
    record('prebindReady', state());
    await File(
      '${output.path}/prebind-ready.json',
    ).writeAsString(jsonEncode(state()));
    await until(
      () => File('${output.path}/start.request').existsSync(),
      'UI prebind and explicit start',
      timeout: const Duration(minutes: 5),
    );
    phase = 'ui-export';
    assembler.arm = true;
    final firstExport = controller.exportAudioToPath(
      '${output.path}/long-a.wav',
    );
    await until(() => controller.isExporting, 'export ownership');
    record('inputReady', state());
    await File(
      '${output.path}/input-ready.json',
    ).writeAsString(jsonEncode(state()));
    await until(
      () => File('${output.path}/input.done').existsSync(),
      'UI actions done',
      timeout: const Duration(minutes: 4),
    );
    record('inputFinished', state());
    assembler.release();
    if (await firstExport == null) throw StateError('Long A export failed');

    phase = 'paused-pending';
    await full();
    final firstAnchor = engine.currentPlaybackResumeAnchor!;
    await until(
      () => controller.currentWordIndex > firstAnchor.startWordIndex,
      'audible midchunk',
    );
    await controller.pausePlayback();
    final saved = controller.currentWordIndex;
    record('noEditPaused', {
      'savedWord': saved,
      'anchorWord': firstAnchor.startWordIndex,
      ...state(),
    });
    await controller.startPlayback();
    if (controller.currentWordIndex != saved) {
      throw StateError('No-edit resume changed saved controller word');
    }
    await ready('unchanged resume');
    await full();
    final pauseAnchor = engine.currentPlaybackResumeAnchor!;
    await controller.pausePlayback();
    await controller.selectVoiceById('af_heart');
    await controller.startPlayback();
    await ready('paused pending B Play');
    if (engine.currentPlaybackResumeAnchor!.startWordIndex !=
        pauseAnchor.startWordIndex) {
      throw StateError('Paused pending Play lost source anchor');
    }
    record('pausedPendingAcknowledged', {
      'anchorWord': pauseAnchor.startWordIndex,
      ...state(),
    });

    phase = 'failure-retry';
    await full();
    final failureAnchor = engine.currentPlaybackResumeAnchor!;
    await controller.selectVoiceById('af_bella');
    failNext = true;
    await controller.applyPendingVoiceAssignments();
    await until(
      () =>
          controller.voiceAssignmentState.phase == VoiceAssignmentPhase.failed,
      'current replacement failed',
    );
    if (controller.voiceAssignmentState.effectiveDefaultVoiceId != 'af_heart' ||
        !controller.voiceAssignmentState.hasPending) {
      throw StateError('Failure committed unacknowledged choices');
    }
    record('replacementFailed', {
      'anchorWord': failureAnchor.startWordIndex,
      ...state(),
    });
    await controller.retryVoiceAssignments();
    await ready('retry A');
    if (engine.currentPlaybackResumeAnchor!.startWordIndex !=
        failureAnchor.startWordIndex) {
      throw StateError('Retry lost retained anchor');
    }
    record('retryAcknowledged', state());

    phase = 'export-cancel';
    await full();
    assembler.arm = true;
    final cancelledExport = controller.exportAudioToPath(
      '${output.path}/cancelled-a.wav',
    );
    await until(
      () => assembler.held,
      'real export raw audio pinned before assembly',
    );
    final exportPaths = pins.paths
        .where((path) => pins.pinCount(path) > 0)
        .toSet();
    final cancelAnchor = engine.currentPlaybackResumeAnchor!;
    var cancellationObservedPinned = false;
    assembler.onCancellation = () {
      cancellationObservedPinned =
          pins.total > 0 &&
          controller.voiceAssignmentState.effectiveDefaultVoiceId == 'af_bella';
      record('exportCancelWait', {
        'anchorWord': cancelAnchor.startWordIndex,
        'ownedExportPaths': exportPaths.length,
        ...state(),
      });
    };
    await controller.selectVoiceById('af_heart');
    final applying = controller.applyPendingVoiceAssignments();
    await applying;
    assembler.onCancellation = null;
    if (!cancellationObservedPinned) {
      throw StateError(
        'Export cancellation lost owned pins or effective snapshot',
      );
    }
    if (await cancelledExport != null) {
      throw StateError('Cancelled export was reported successful');
    }
    await ready('B after export drain');
    if (pins.total != engine.debugPlaybackPinCount) {
      throw StateError('Cancelled export retained non-playback pins');
    }
    if (engine.currentPlaybackResumeAnchor!.startWordIndex !=
        cancelAnchor.startWordIndex) {
      throw StateError('Export cancel replacement skipped anchor');
    }
    record('exportCancelDrained', state());

    phase = 'abc-stale-failure';
    await controller.pausePlayback();
    await controller.importPastedText(short);
    await controller.selectVoiceById('af_bella');
    synthesisEntered = Completer<void>();
    synthesisRelease = Completer<void>();
    holdNext = true;
    failHeld = true;
    final starting = controller.startPlayback();
    await synthesisEntered.future;
    await controller.selectVoiceById('af_heart');
    await controller.selectVoiceById('am_fenrir');
    synthesisRelease.complete();
    await starting;
    await ready('C after stale A failure');
    if (controller.voiceAssignmentState.effectiveDefaultVoiceId !=
            'am_fenrir' ||
        (controller.statusMessage?.contains('obsolete') ?? false)) {
      throw StateError('Old A failure displaced C');
    }
    record('abcFailureLatestAcknowledged', state());

    phase = 'aba-pcm';
    Future<TtsExportResult> choice(String voice, String name) async {
      await controller.pausePlayback();
      await controller.importPastedText(short);
      await controller.selectVoiceById(voice);
      await controller.startPlayback();
      await ready(name);
      record('abaAcknowledged', {'name': name, ...state()});
      final value = await controller.exportAudioToPath(
        '${output.path}/$name.wav',
      );
      if (value == null) throw StateError('Export $name failed');
      return value;
    }

    final a1 = await choice('af_bella', 'a1');
    final b = await choice('af_heart', 'b');
    final a2 = await choice('af_bella', 'a2');
    final hashA1 = await _pcmHash(a1.outputPath),
        hashB = await _pcmHash(b.outputPath),
        hashA2 = await _pcmHash(a2.outputPath);
    if (hashA1 != hashA2 || hashA1 == hashB) {
      throw StateError('A/B/A PCM identity contrast failed');
    }
    record('abaPcmCompared', {'a1': hashA1, 'b': hashB, 'a2': hashA2});
    await controller.pausePlayback();
    await engine.stop();
    if (pins.total != 0 || player.sequence.isNotEmpty) {
      throw StateError('Final native pin drain failed');
    }
    record('nativePinsDrained', state());
    phase = 'listening-ready';
    await controller.importPastedText(
      'John said, "The quiet river is beautiful today." Maria replied, "We can walk home together."',
    );
    await controller.selectVoiceById('af_bella');
    record('listeningReady', state());
    await File(
      '${output.path}/listening-ready.json',
    ).writeAsString(jsonEncode(state()));
    await until(
      () => File('${output.path}/finish.signal').existsSync(),
      'listening release',
      timeout: const Duration(minutes: 30),
    );
    success = true;
  } catch (error, stack) {
    record('failure', {'error': '$error', 'stack': '$stack', ...state()});
  } finally {
    assembler.release();
    if (synthesisRelease != null && !synthesisRelease.isCompleted) {
      synthesisRelease.complete();
    }
    timer.cancel();
    SchedulerBinding.instance.removeTimingsCallback(frames);
    await controller.pausePlayback();
    await engine.shutdownResources();
    record('finalDrain', state());
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
