// Signed-app probe of real managed bf16 preparation and offline switch/retry.
// The external runner owns capture, process observation and normal Quit.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/native_speech_work_activity.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/rendered_scene_repository.dart';
import 'package:read_aloud/src/services/work_character_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_main_responsiveness_probe.dart';
import 'radoc_first_load_smoke.dart' show copyQueuedAudioEvidence;

class _Controller extends ReaderController {
  _Controller(
    KokoroTtsEngine initial,
    KokoroTtsEngine Function(String, int) factory,
    Directory root,
  ) : super(
        ttsEngine: initial,
        engineFactory: factory,
        preferencesService: ReaderPreferencesService(
          workRepository: WorkCharacterRepository('${root.path}/works'),
        ),
        renderedSceneRepository: RenderedSceneRepository(
          Directory('${root.path}/scenes'),
        ),
        enablePlatformIntakeChannels: false,
        deferInitialSynthesis: true,
      );
  Future<void>? _initialized;
  @override
  Future<void> initialize() => _initialized ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 2) throw ArgumentError('Expected SOURCE_MODEL RECEIPT');
  if (Platform.environment['HF_HUB_OFFLINE'] != '1') {
    throw StateError('This probe requires HF_HUB_OFFLINE=1; no downloads.');
  }
  final support = await getApplicationSupportDirectory();
  if (!support.path.contains('mlxPlaybackTest')) {
    throw StateError('Use the isolated mlxPlaybackTest app identity.');
  }
  final source = await Directory(args[0]).resolveSymbolicLinks();
  if (!await File('$source/config.json').exists()) {
    throw StateError('Existing model fixture is unavailable.');
  }
  final output = File(args[1]).absolute;
  final root = await output.parent.createTemp('s7-session-');
  final alias = Link('${support.path}/read_aloud/mlx-tts/fish_drama3');
  if (await FileSystemEntity.type(alias.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('QA model alias already occupied; preserve it.');
  }
  await alias.parent.create(recursive: true);
  await alias.create(source);
  // Only a new QA alias is owned. Original weights and user preferences remain
  // untouched; the normal processor sees an installed folder and requires the
  // exact pinned integrity reply, unlike a developer modelPath override.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    'reader.ttsEngineId': 'fish_drama3',
    'reader.selectedVoiceId': 'library_fishadrian',
  });
  final players = <AudioPlayer>[];
  final engines = <KokoroTtsEngine>[];
  final factoryEvents = <Map<String, Object?>>[];
  var phase = 'initialization';
  var synthesisCalls = 0;
  final watch = Stopwatch()..start();
  KokoroTtsEngine factory(String id, int bits) {
    if (engines.length >= 12) throw StateError('Engine observation bound');
    final player = AudioPlayer(useLazyPreparation: false);
    final engine = KokoroTtsEngine(
      player: player,
      engineId: id,
      mlxModelPath: '',
      mlxQuantizationBits: id == 'voxtral_4b' ? bits : 0,
      mlxArtifactStore: AudioArtifactStore(
        Directory('${root.path}/raw-${engines.length}'),
      ),
      beforeSynthesis: () async {
        synthesisCalls++;
      },
    );
    players.add(player);
    engines.add(engine);
    factoryEvents.add({
      'phase': phase,
      'engineId': id,
      'elapsedMs': watch.elapsedMilliseconds,
    });
    return engine;
  }

  final c = _Controller(factory('fish_drama3', 0), factory, root);
  final native = NativeMainResponsivenessProbe()..start(() => phase);
  var lastTick = 0, maxUi = 0;
  final heartbeat = Timer.periodic(const Duration(milliseconds: 50), (_) {
    final now = watch.elapsedMilliseconds;
    maxUi = math.max(maxUi, now - lastTick - 50);
    lastTick = now;
  });
  final events = <Map<String, Object?>>[];
  final receipt = <String, Object?>{
    'schema': 'readaloud-native-engine-session-v1',
    'passed': false,
    'runRoot': root.path,
    'modelSource': source,
    'ownedAlias': alias.path,
    'offline': true,
    'events': events,
    'factoryEvents': factoryEvents,
    'limits':
        'M5 bf16 and offline unavailable-variant switch only; no 8/4-bit '
        'success, full-model transfer, M3, physical-speaker or human acceptance.',
  };
  String? lastEvent;
  Map<String, Object?> snapshot(String event) => {
    'event': event,
    'phase': phase,
    'elapsedMs': watch.elapsedMilliseconds,
    'unixMicros': DateTime.now().microsecondsSinceEpoch,
    'epoch': c.engineSession.epoch,
    'selected': c.engineSession.selected.engineId,
    'active': c.engineSession.active?.engineId,
    'lastWorking': c.engineSession.lastWorking?.engineId,
    'sessionPhase': c.engineSession.phase.name,
    'startupError': c.startupError,
    'pendingPlay': c.hasPendingPlaybackIntent,
    'playing': c.isPlaying,
    'word': c.currentWordIndex,
    'voice': c.selectedVoice?.id,
  };
  void observe() {
    final value = snapshot('state');
    final key = jsonEncode(
      {...value}
        ..remove('elapsedMs')
        ..remove('unixMicros'),
    );
    if (key == lastEvent) return;
    if (events.length >= 256) throw StateError('Session observation bound');
    lastEvent = key;
    events.add(value);
  }

  c.addListener(observe);
  Future<void> until(bool Function() ready, String label) async {
    final deadline = watch.elapsedMilliseconds + 180000;
    while (!ready()) {
      if (watch.elapsedMilliseconds > deadline) throw TimeoutException(label);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void require(bool ok, String message) {
    if (!ok) throw StateError(message);
  }

  Future<Map<String, Object?>>? copiedPrefix;
  final sequence = players.first.sequenceStream.listen((sources) {
    if (copiedPrefix != null || sources.isEmpty) return;
    final first = sources.first;
    if (first is UriAudioSource && first.uri.scheme == 'file') {
      copiedPrefix = copyQueuedAudioEvidence(
        first.uri.toFilePath(),
        '${root.path}/positive-prefix.wav',
      );
    }
  });
  runApp(ReadAloudApp(controller: c));
  try {
    await c.initialize();
    await WidgetsBinding.instance.endOfFrame;
    stdout.writeln('S7_SESSION_NATIVE_STARTED');
    await c.completeInitialIntake();
    await until(
      () => c.engineSession.active?.engineId == 'fish_drama3',
      'Initial managed bf16 validation',
    );
    require(c.startupError == null, 'Initial startup failed');
    await c.importPastedText(
      'The lantern burned beside the garden gate. '
      'A narrow path curved between the tall trees behind the house. '
      'Across the valley a quiet station waited beneath the autumn sky. '
      'At dawn the fields emerged from the silver mist and the baker opened '
      'the little door beside the market square.',
    );
    await until(() => c.preparedWordCount > 0, 'Prepared target');
    await c.selectVoiceById('library_fishadrian');
    phase = 'positive-play';
    final play = c.startPlayback().catchError((Object error) {
      receipt['positivePlayTerminal'] = '$error';
    });
    await until(
      () => players.first.playing && players.first.position > Duration.zero,
      'Real first packet',
    );
    // Allow a real positive prefix to traverse the native output/capture path
    // before requesting Pause. Player position alone is not emitted audio.
    await Future<void>.delayed(const Duration(milliseconds: 750));
    receipt['positivePauseRequestedUnixMicros'] =
        DateTime.now().microsecondsSinceEpoch;
    await c.pausePlayback();
    receipt['positivePauseReturnedUnixMicros'] =
        DateTime.now().microsecondsSinceEpoch;
    await play.timeout(const Duration(seconds: 15));
    require(copiedPrefix != null, 'Missing real queued prefix');
    receipt['positiveReference'] = await copiedPrefix;
    await c.jumpBySeconds(12);
    final anchor = c.currentWordIndex;
    final document = c.document.displayDocument.documentId;
    final voice = c.selectedVoice?.id;
    require(anchor > 0, 'Need a nonzero retained reading anchor');
    receipt['retainedAnchor'] = anchor;
    phase = 'offline-unavailable';
    await c.setTtsEngineId('fish_drama3_8bit');
    require(
      c.engineSession.phase.name == 'failed' &&
          c.engineSession.active == null &&
          c.engineSession.lastWorking?.engineId == 'fish_drama3',
      'Unavailable variant published an active identity',
    );
    events.add(snapshot('offline-failed'));
    if (Platform.environment['READALOUD_S7_INSPECT'] == '1') {
      // Observe the actual failed selected/active feedback in Settings. This
      // explicit QA gate is not a startup/load timing measurement.
      receipt['inspectionRequested'] = true;
      stdout.writeln('WAITING_S7_INSPECTION');
      final gate = File('${output.parent.path}/inspection.done');
      final end = watch.elapsedMilliseconds + 180000;
      while (!await gate.exists()) {
        if (watch.elapsedMilliseconds > end) {
          throw TimeoutException('UI inspection');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      receipt['inspectionReleased'] = true;
    }
    phase = 'return-to-bf16';
    await c.setTtsEngineId('fish_drama3');
    require(
      c.engineSession.active?.engineId == 'fish_drama3' &&
          c.startupError == null,
      'Failed to reload last working model',
    );
    require(
      c.currentWordIndex == anchor &&
          c.selectedVoice?.id == voice &&
          c.document.displayDocument.documentId == document,
      'Switch lost reading or narrator intent',
    );
    phase = 'latest-wins';
    final b = c.setTtsEngineId('fish_drama3_8bit');
    await until(
      () =>
          c.isSwitchingEngine &&
          c.engineSession.selected.engineId == 'fish_drama3_8bit',
      'B switch entered retirement',
    );
    final a = c.setTtsEngineId('fish_drama3');
    await Future.wait([b, a]);
    require(
      c.engineSession.active?.engineId == 'fish_drama3' &&
          c.startupError == null,
      'Obsolete B installed or failed A',
    );
    phase = 'preview-replacement';
    final beforePreview = synthesisCalls;
    var previewSettled = false;
    final preview = c.previewVoice(voice!).whenComplete(() {
      previewSettled = true;
    });
    await until(
      // speak() acknowledges owned background preparation before synthesis.
      // A settled preview Future is therefore not a failed preparation window.
      () => synthesisCalls > beforePreview,
      'Preview synthesis boundary',
    );
    receipt['previewPreparationObservation'] = {
      'beforeSynthesisCalls': beforePreview,
      'synthesisCalls': synthesisCalls,
      'requestSettled': previewSettled,
      'requestedPlaying': players.last.playing,
      'processingState': players.last.processingState.name,
      'positionMs': players.last.position.inMilliseconds,
    };
    // just_audio's playing flag expresses intent even while it is buffering.
    // Actual emitted silence is checked independently over the captured wave.
    require(
      synthesisCalls > beforePreview && players.last.position == Duration.zero,
      'Preview missed its pre-position cancellation window',
    );
    final previewB = c.setTtsEngineId('fish_drama3_8bit');
    await until(() => c.isSwitchingEngine, 'Preview replacement');
    final previewA = c.setTtsEngineId('fish_drama3');
    await Future.wait([previewB, previewA, preview]);
    require(
      c.engineSession.active?.engineId == 'fish_drama3' &&
          !c.isPlaying &&
          players.every((p) => !p.playing),
      'Retired preview affected the replacement',
    );
    receipt['previewCancelledBeforeAudio'] = true;
    events.add(snapshot('preview-retired'));
    phase = 'export-replacement';
    await until(
      () => c.hasCompleteDocumentSnapshot,
      'Complete export snapshot',
    );
    final exportedPath = '${root.path}/cancelled-export.wav';
    final beforeExport = synthesisCalls;
    var exportSettled = false;
    final export = c.exportAudioToPath(exportedPath).whenComplete(() {
      exportSettled = true;
    });
    await until(
      () => synthesisCalls > beforeExport || exportSettled,
      'Export synthesis boundary',
    );
    require(
      synthesisCalls > beforeExport,
      'Export did not enter the real synthesis owner',
    );
    final exportB = c.setTtsEngineId('fish_drama3_8bit');
    await until(() => c.isSwitchingEngine, 'Export replacement');
    final exportA = c.setTtsEngineId('fish_drama3');
    await Future.wait<Object?>([exportB, exportA, export]);
    require(
      !await File(exportedPath).exists() &&
          c.engineSession.active?.engineId == 'fish_drama3' &&
          c.startupError == null,
      'Retired export published output or affected the replacement',
    );
    receipt['exportCancelledWithoutPublication'] = true;
    events.add(snapshot('export-retired'));
    phase = 'pending-play-replacement';
    final pending = c.startPlayback().catchError((Object error) {
      receipt['cancelledPlayTerminal'] = '$error';
    });
    await until(() => c.hasPendingPlaybackIntent, 'Pending Play');
    final pendingB = c.setTtsEngineId('fish_drama3_8bit');
    await until(() => c.isSwitchingEngine, 'Pending Play replacement');
    final pendingA = c.setTtsEngineId('fish_drama3');
    await Future.wait([pendingB, pendingA, pending]);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    require(
      c.engineSession.active?.engineId == 'fish_drama3' &&
          c.startupError == null &&
          !c.hasPendingPlaybackIntent &&
          !c.isPlaying &&
          players.every((p) => !p.playing),
      'Replacement resumed obsolete speech',
    );
    require(
      c.currentWordIndex == anchor &&
          c.selectedVoice?.id == voice &&
          c.document.displayDocument.documentId == document,
      'Latest switch lost document/anchor/narrator',
    );
    receipt['passed'] = true;
    events.add(snapshot('complete'));
  } catch (error, stack) {
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
  } finally {
    phase = 'shutdown';
    c.removeListener(observe);
    heartbeat.cancel();
    receipt['functionalPassed'] = receipt['passed'];
    receipt['nativeMainResponsiveness'] = await native.close();
    receipt['maxUiHeartbeatDelayMs'] = maxUi;
    if (maxUi > 250 ||
        (receipt['nativeMainResponsiveness'] as Map)['passed'] != true) {
      receipt['passed'] = false;
    }
    final errors = <String>[];
    for (final engine in engines) {
      try {
        await engine.shutdownResources().timeout(const Duration(seconds: 30));
      } catch (e) {
        errors.add('$e');
      }
    }
    await sequence.cancel();
    try {
      await c.shutdownPreparation();
    } catch (e) {
      errors.add('$e');
    }
    c.dispose();
    for (final player in players) {
      try {
        await player.dispose();
      } catch (e) {
        errors.add('$e');
      }
    }
    try {
      if (await alias.target() != source) throw StateError('QA alias changed');
      await alias.delete();
    } catch (e) {
      errors.add('$e');
    }
    final activity = await NativeSpeechWorkActivity.snapshot();
    receipt['speechWorkActivity'] = activity;
    receipt['resourceShutdownComplete'] =
        errors.isEmpty &&
        activity?['active'] == 0 &&
        activity?['started'] == activity?['ended'];
    receipt['shutdownErrors'] = errors;
    receipt['synthesisCallbacks'] = synthesisCalls;
    receipt['peakRuntimeBytesByEngine'] = engines
        .map((e) => e.debugPeakMlxRuntimeBytes)
        .toList();
    if (receipt['resourceShutdownComplete'] != true) receipt['passed'] = false;
    await File('${output.path}.pending').writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt),
      flush: true,
    );
    await File('${output.path}.pending').rename(output.path);
    stdout.writeln('S7_SESSION_COMPLETE passed=${receipt['passed']}');
  }
}
