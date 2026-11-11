// #112 ACD-M1 R1: managed quantized-model native qualification entry point.
// Build with this target and the isolated mlxPlaybackTest identity. The runner
// owns app-only capture, process observation, acoustic gates and normal Quit.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/engine_capability.dart';
import 'package:read_aloud/src/models/speech_engine_catalog.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';
import 'package:read_aloud/src/services/native_speech_work_activity.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/rendered_scene_repository.dart';
import 'package:read_aloud/src/services/work_character_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_main_responsiveness_probe.dart';
import 'native_playback_position_probe.dart';
import 'radoc_first_load_smoke.dart' show copyQueuedAudioEvidence;

class _Controller extends ReaderController {
  _Controller(
    KokoroTtsEngine? initial,
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
  Future<void>? _initialization;
  @override
  Future<void> initialize() => _initialization ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

// Only sendable paths enter this worker. File inspection never blocks Flutter.
Future<List<Map<String, Object?>>> _provenance(String root) =>
    Isolate.run(() async {
      final rows = <Map<String, Object?>>[];
      await for (final entity in Directory(root).list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        if (rows.length >= 2048) throw StateError('Provenance bound');
        final value = jsonDecode(await entity.readAsString());
        if (value is Map &&
            (value.containsKey('modelIdentity') ||
                value.containsKey('provenance') ||
                value.containsKey('capabilityProfileId'))) {
          rows.add({'path': entity.path, 'metadata': value});
        }
      }
      return rows;
    });

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  const modes = [
    'default-policy',
    'cached-bf16',
    'cached-8bit',
    'cached-4bit',
    'cached-aba',
    'online-cancel-retry',
  ];
  if (args.length != 2 || !modes.contains(args[0])) {
    throw ArgumentError('Expected ${modes.join('|')} RECEIPT');
  }
  final mode = args[0];
  final online = mode == 'online-cancel-retry';
  if (!online && Platform.environment['HF_HUB_OFFLINE'] != '1') {
    throw StateError('Cached cases require HF_HUB_OFFLINE=1.');
  }
  if (online && Platform.environment['HF_HUB_OFFLINE'] == '1') {
    throw StateError('Online case requires downloads explicitly enabled.');
  }
  final support = await getApplicationSupportDirectory();
  if (!support.path.contains('mlxPlaybackTest')) {
    throw StateError('Requires isolated mlxPlaybackTest identity.');
  }
  final output = File(args[1]).absolute;
  if (await output.exists()) throw StateError('Preserve existing receipt.');
  final root = await output.parent.createTemp('s7-variants-');
  final initial = switch (mode) {
    'default-policy' => 'fish_drama3',
    'cached-bf16' => 'fish_drama3',
    'cached-4bit' => 'fish_drama3_4bit',
    _ => 'fish_drama3_8bit',
  };
  // In-memory preferences and isolated content only; existing QA model cache is
  // read through normal application discovery. No aliases/modelPath override.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    if (mode != 'default-policy') 'reader.ttsEngineId': initial,
    'reader.selectedVoiceId': 'library_fishadrian',
  });
  final catalog = FishDramaCatalog.fromJson(
    modelsJson: await rootBundle.loadString('assets/fish_drama_models.json'),
    checksumsJson: await rootBundle.loadString(
      'assets/fish_drama_model_checksums.json',
    ),
  );
  final watch = Stopwatch()..start();
  // One work deadline plus reserved cleanup; the runner also enforces 270s.
  Duration budget(int seconds, {bool cleanup = false}) => Duration(
    milliseconds: math.max(
      1,
      math.min(
        seconds * 1000,
        (cleanup ? 265000 : 240000) - watch.elapsedMilliseconds,
      ),
    ),
  );
  var phase = 'initialization';
  final engines = <KokoroTtsEngine>[];
  final players = <AudioPlayer>[];
  final positions = <NativePlaybackPositionProbe>[];
  final subscriptions = <StreamSubscription<dynamic>>[];
  final copies = <Future<void>>[];
  final evidence = <Map<String, Object?>>[];
  final queuedPaths = <String>{};
  final observationErrors = <String>[];
  final events = <Map<String, Object?>>[];
  final segments = <Map<String, Object?>>[];
  var synthesisCalls = 0;
  KokoroTtsEngine factory(String id, int bits) {
    if (engines.length >= 8) throw StateError('Engine creation bound');
    final number = engines.length;
    final player = AudioPlayer(useLazyPreparation: false);
    final engine = KokoroTtsEngine(
      player: player,
      engineId: id,
      mlxModelPath: '',
      mlxQuantizationBits: 0,
      mlxArtifactStore: AudioArtifactStore(
        Directory('${root.path}/raw-$number'),
      ),
      beforeSynthesis: () async {
        synthesisCalls++;
      },
    );
    final position = NativePlaybackPositionProbe(player);
    players.add(player);
    engines.add(engine);
    positions.add(position);
    subscriptions.add(player.positionStream.listen(position.sample));
    subscriptions.add(
      player.sequenceStream.listen((sources) {
        for (final source in sources) {
          if (source is! UriAudioSource || source.uri.scheme != 'file') {
            continue;
          }
          final path = source.uri.toFilePath();
          if (!queuedPaths.add(path)) continue;
          if (queuedPaths.length > 2048) {
            observationErrors.add('Queued audio evidence bound');
            return;
          }
          final row = <String, Object?>{
            'engineIndex': number,
            'engineId': id,
            'sourcePath': path,
            'queuedUnixMicros': DateTime.now().microsecondsSinceEpoch,
          };
          evidence.add(row);
          // Each queued WAV is copied immediately while its production playback
          // pin is live. Failures are joined and fail the case, never discarded.
          copies.add(
            copyQueuedAudioEvidence(
                  path,
                  '${root.path}/queued-${evidence.length}.wav',
                )
                .then<void>((value) {
                  row['reference'] = value;
                })
                .catchError((Object e) {
                  observationErrors.add('Queued copy $path: $e');
                }),
          );
        }
      }),
    );
    return engine;
  }

  final c = _Controller(
    mode == 'default-policy' ? null : factory(initial, 0),
    factory,
    root,
  );
  final native = NativeMainResponsivenessProbe()..start(() => phase);
  var lastTick = 0, maxUi = 0;
  final samples = <Map<String, Object?>>[];
  final heartbeat = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final now = watch.elapsedMilliseconds;
    maxUi = math.max(maxUi, now - lastTick - 100);
    lastTick = now;
    if (players.isEmpty) return;
    if (samples.length < 2700) {
      final p = players.last;
      positions.last.sample(p.position);
      samples.add({
        'elapsedMs': now,
        'unixMicros': DateTime.now().microsecondsSinceEpoch,
        'phase': phase,
        'engineIndex': engines.length - 1,
        'playing': p.playing,
        'processingState': p.processingState.name,
        'positionMs': p.position.inMilliseconds,
        'currentIndex': p.currentIndex,
        'source':
            p.currentIndex == null ||
                p.currentIndex! >= p.sequence.length ||
                p.sequence[p.currentIndex!] is! UriAudioSource
            ? null
            : (p.sequence[p.currentIndex!] as UriAudioSource).uri.toString(),
        'word': c.currentWordIndex,
      });
    }
  });
  final receipt = <String, Object?>{
    'schema': 'readaloud-native-variant-v1',
    'mode': mode,
    'passed': false,
    'offline': !online,
    'managedModelPathOverride': false,
    'totalMemoryEnvelopeQualified': false,
    'runRoot': root.path,
    'events': events,
    'segments': segments,
    'playerSamples': samples,
    'queuedAudio': evidence,
    'catalog': {
      for (final id in ['fish_drama3_8bit', 'fish_drama3_4bit'])
        id: {
          'pinnedIdentity': catalog.variants[id]!.pinnedIdentity,
          'integrityManifestPresent':
              catalog.variants[id]!.integrityManifest != null,
          'catalogCapabilities': const EngineCapabilityRegistry()
              .lookup(engineId: id)
              .toMap(),
        },
    },
    'limits':
        'Bounded running-app routes only. Runner must independently gate emitted '
        'signal and cleanup; exact waveform matching/continuity and human listening '
        'remain separate. No M3, startup-clock or total-memory-envelope acceptance. '
        'Native scene support is recorded, never presumed for quantized variants.',
  };
  Map<String, Object?> snapshot(String event) {
    final progress = c.speechResourceProgress;
    return {
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
      'resourceProgress': progress == null
          ? null
          : {
              'stage': progress.stage,
              'message': progress.message,
              'completed': progress.completed,
              'total': progress.total,
              'unit': progress.unit,
            },
    };
  }

  String? lastKey;
  void observe() {
    final row = snapshot('state');
    final key = jsonEncode(
      {...row}
        ..remove('elapsedMs')
        ..remove('unixMicros'),
    );
    if (key == lastKey) return;
    lastKey = key;
    if (events.length < 2048) {
      events.add(row);
    } else if (observationErrors.isEmpty) {
      observationErrors.add('State bound');
    }
  }

  c.addListener(observe);
  void require(bool value, String label) {
    if (!value) throw StateError(label);
  }

  Future<void> until(
    bool Function() ready,
    String label, {
    int seconds = 90,
  }) async {
    final end = math.min(240000, watch.elapsedMilliseconds + seconds * 1000);
    while (!ready()) {
      if (watch.elapsedMilliseconds >= end) throw TimeoutException(label);
      if (observationErrors.isNotEmpty) {
        throw StateError(observationErrors.join('; '));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> switchTo(
    String id,
    int anchor,
    String document,
    String voice,
  ) async {
    phase = 'switch-$id';
    events.add(snapshot('switch-request'));
    await c.setTtsEngineId(id).timeout(budget(90));
    require(
      c.engineSession.active?.engineId == id && c.startupError == null,
      'Managed target failed: $id ${c.startupError}',
    );
    require(
      c.currentWordIndex == anchor &&
          c.document.displayDocument.documentId == document &&
          c.selectedVoice?.id == voice,
      'Switch lost document/anchor/narrator',
    );
    require(
      !c.hasPendingPlaybackIntent &&
          !c.isPlaying &&
          players.every((p) => !p.playing),
      'Switch resumed unexpected speech',
    );
    events.add(snapshot('switch-validated'));
  }

  Future<void> playFor(int seconds, String label) async {
    phase = label;
    final engine = engines.last;
    final player = players.last;
    final position = positions.last;
    final startPosition = position.sampledPositionTotalMs;
    final row = <String, Object?>{
      'label': label,
      'engineId': engine.engineId,
      'engineIndex': engines.length - 1,
      'playRequestedUnixMicros': DateTime.now().microsecondsSinceEpoch,
      'startWord': c.currentWordIndex,
      'requiredWallPlaybackMs': seconds * 1000,
    };
    segments.add(row);
    Object? terminal;
    final play = c.startPlayback().catchError((Object error) {
      terminal = error;
    });
    await until(
      () => player.playing && player.position > Duration.zero,
      '$label real player movement',
    );
    row['firstPositionUnixMicros'] = DateTime.now().microsecondsSinceEpoch;
    final end = watch.elapsedMilliseconds + seconds * 1000;
    await until(
      () => watch.elapsedMilliseconds >= end,
      '$label sustained interval',
      seconds: seconds + 2,
    );
    if (seconds == 60) {
      // A silent source has no acoustic identity. Finish this warm probe on an
      // audible source so the unchanged strict analyzer can bound its final
      // Pause-interrupted WAV. Never accept a silent tail by player intent.
      final boundaryStarted = watch.elapsedMilliseconds;
      await until(
        () {
          final index = player.currentIndex;
          if (index == null || index >= player.sequence.length) return false;
          final source = player.sequence[index];
          if (source is! UriAudioSource || source.uri.scheme != 'file') {
            return false;
          }
          final path = source.uri.toFilePath();
          for (final queued in evidence.reversed) {
            if (queued['sourcePath'] != path) continue;
            final reference = queued['reference'];
            return reference is Map &&
                reference['peakPcm16'] is num &&
                (reference['peakPcm16'] as num) > 327.68;
          }
          return false;
        },
        '$label identifiable Pause boundary',
        seconds: 2,
      );
      row['audibleBoundaryWaitMs'] =
          watch.elapsedMilliseconds - boundaryStarted;
    }
    row['pauseRequestedUnixMicros'] = DateTime.now().microsecondsSinceEpoch;
    await c.pausePlayback().timeout(budget(10));
    row['pauseReturnedUnixMicros'] = DateTime.now().microsecondsSinceEpoch;
    await play.timeout(budget(10));
    row['terminal'] = terminal?.toString();
    row['endWord'] = c.currentWordIndex;
    row['positionEvidence'] = position.toMap();
    row['observedPositionAdvanceMs'] =
        position.sampledPositionTotalMs - startPosition;
    row['runtimeVersion'] = engine.engineVersion;
    row['nativeSceneRuntimeAdvertised'] = engine.engineVersion.contains(
      'native-scene',
    );
    row['peakRuntimeBytesObserved'] = engine.debugPeakMlxRuntimeBytes;
    require(
      terminal == null &&
          position.sampledPositionTotalMs - startPosition >= seconds * 850,
      '$label insufficient actual player progress or playback failure',
    );
    require(
      !position.overflow && c.currentWordIndex > (row['startWord'] as int),
      '$label missing reading progress',
    );
    events.add(snapshot('paused-after-real-playback'));
  }

  runApp(ReadAloudApp(controller: c));
  try {
    await c.initialize().timeout(budget(100));
    await WidgetsBinding.instance.endOfFrame;
    stdout.writeln('S7_VARIANT_NATIVE_STARTED');
    // First installation can hash the full checkpoint before loading. This is
    // a bounded qualification setup budget, not a startup/document-load pass.
    await c.completeInitialIntake().timeout(budget(90));
    require(
      c.engineSession.active?.engineId == initial && c.startupError == null,
      'Initial managed variant unavailable: ${c.startupError}',
    );
    receipt['engineSelectionReason'] = c.engineSelectionReason;
    if (mode == 'default-policy') {
      require(
        (c.engineSelectionReason ?? '').startsWith('Automatic default:'),
        'Unselected startup did not use the qualified quality policy',
      );
      final preferences = await SharedPreferences.getInstance();
      require(
        !preferences.containsKey('reader.ttsEngineId'),
        'Automatic selection was incorrectly persisted as explicit intent',
      );
    }
    const places = [
      'Alderbrook',
      'Bellhaven',
      'Cedarvale',
      'Dunmere',
      'Elmford',
      'Fairwater',
      'Greenwick',
      'Hillcrest',
      'Ivydale',
      'Juniper',
      'Kingswell',
      'Longmeadow',
      'Mallow',
      'Northbridge',
      'Oakridge',
    ];
    // Distinct nearby context avoids replaying the very same cached WAV and
    // undercounting the existing per-source native-position observer.
    final text = List.generate(
      places.length,
      (i) =>
          'In ${places[i]} the lantern burned beside the garden gate at dawn. '
          'A narrow path through ${places[i]} curved among tall trees toward a quiet house. '
          'Across ${places[i]} a little station waited beneath a pale autumn sky. '
          'The baker in ${places[i]} opened his door and watched the silver mist rise.',
    ).join('\n\n');
    final fixture = File('${root.path}/input.txt');
    await fixture.writeAsString(text, flush: true);
    receipt['inputFixture'] = fixture.path;
    await c.importPastedText(text).timeout(budget(20));
    await until(
      () => c.preparedWordCount > 150,
      'Prepared bounded reading input',
    );
    await c.selectVoiceById('library_fishadrian').timeout(budget(20));
    require(
      c.selectedVoice?.id == 'library_fishadrian',
      'Narrator unavailable',
    );
    // This probe qualifies warm sustained reading, not a startup/load clock.
    // Capture setup must have actually written frames before manual Play, or
    // a delayed ScreenCaptureKit connection could miss the beginning entirely.
    phase = 'capture-setup';
    final captureGate = File('${output.parent.path}/capture.ready');
    final captureDeadline = watch.elapsedMilliseconds + 30000;
    while (!await captureGate.exists()) {
      if (watch.elapsedMilliseconds > captureDeadline) {
        throw TimeoutException('App-only capture setup');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    receipt['captureReadyBeforePlayUnixMicros'] =
        DateTime.now().microsecondsSinceEpoch;
    if (mode == 'default-policy' ||
        mode == 'cached-bf16' ||
        mode == 'cached-8bit' ||
        mode == 'cached-4bit') {
      await playFor(60, 'sustained-$initial');
    } else {
      await playFor(3, 'initial-A8');
      await c.jumpBySeconds(-1000000);
      await c.jumpBySeconds(12);
      final anchor = c.currentWordIndex;
      final document = c.document.displayDocument.documentId;
      final voice = c.selectedVoice!.id;
      require(anchor > 0, 'Nonzero retained anchor required');
      receipt['retainedAnchor'] = anchor;
      if (!online) {
        phase = 'rapid-latest-selection';
        final obsolete = c.setTtsEngineId('fish_drama3_4bit');
        await until(() => c.isSwitchingEngine, 'Rapid switch retirement');
        final latest = c.setTtsEngineId(initial);
        await Future.wait([obsolete, latest]).timeout(budget(90));
        require(
          c.engineSession.active?.engineId == initial &&
              c.startupError == null &&
              !c.hasPendingPlaybackIntent &&
              !c.isPlaying,
          'Rapid selection installed an obsolete target or resumed speech',
        );
        receipt['rapidLatestSelectionValidated'] = true;
      }
      if (online) {
        if (Platform.environment['READALOUD_S7_UI_CANCEL'] == '1') {
          stdout.writeln('WAITING_S7_UI_SETTINGS');
          final settingsGate = File('${output.parent.path}/ui-settings.ready');
          final deadline = watch.elapsedMilliseconds + 60000;
          while (!await settingsGate.exists()) {
            if (watch.elapsedMilliseconds > deadline) {
              throw TimeoutException('Settings observation');
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
        phase = 'online-download-4bit';
        final pending = c.setTtsEngineId('fish_drama3_4bit');
        int? baseline;
        await until(
          () {
            final p = c.speechResourceProgress;
            if (p == null ||
                !p.stage.toLowerCase().contains('download') ||
                p.unit != 'bytes' ||
                p.completed == null) {
              return false;
            }
            baseline ??= p.completed;
            return p.completed! > baseline!;
          },
          'Actual download progress before retirement',
          seconds: 30,
        );
        receipt['downloadBaselineBytes'] = baseline;
        receipt['downloadInterruptedAt'] = snapshot('download-interruption');
        final uiCancel = Platform.environment['READALOUD_S7_UI_CANCEL'] == '1';
        if (uiCancel) {
          stdout.writeln('WAITING_S7_UI_CANCEL');
          await until(
            () => c.engineSession.phase.name == 'cancelled',
            'Settings Cancel',
            seconds: 60,
          );
        }
        final cancelled = c.cancelSpeechResourcePreparation();
        final twice = c.cancelSpeechResourcePreparation();
        require(
          c.engineSession.phase.name == 'cancelled' &&
              c.engineSession.selected.engineId == 'fish_drama3_4bit' &&
              c.engineSession.active == null &&
              c.engineSession.lastWorking?.engineId == initial &&
              !c.hasPendingPlaybackIntent &&
              !c.isPlaying,
          'Explicit download cancellation did not fence the current owner',
        );
        await Future.wait([pending, cancelled, twice]).timeout(budget(30));
        require(
          c.engineSession.phase.name == 'cancelled' &&
              c.engineSession.active == null &&
              c.startupError == null,
          'Retired download published late state',
        );
        receipt['doubleCancelValidated'] = true;
        receipt['cancelActionSource'] = uiCancel ? 'settings-ui' : 'controller';
        receipt['downloadRetiredWithoutLateActivation'] = true;
        if (uiCancel) {
          stdout.writeln('WAITING_S7_UI_RETRY');
          await until(
            () =>
                c.engineSession.active?.engineId == 'fish_drama3_4bit' &&
                c.startupError == null,
            'Settings Retry',
            seconds: 120,
          );
          receipt['retryActionSource'] = 'settings-ui';
          stdout.writeln('WAITING_S7_UI_RETRY_OBSERVATION');
          final retryGate = File(
            '${output.parent.path}/ui-retry-observed.ready',
          );
          final deadline = watch.elapsedMilliseconds + 60000;
          while (!await retryGate.exists()) {
            if (watch.elapsedMilliseconds > deadline) {
              throw TimeoutException('Retry observation');
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
        // Explicit retry uses retained cache/partials through the existing owner.
        // A large incomplete transfer may exceed this case's 240s work budget;
        // that is a failed/partial receipt, never an assumed resume success.
      }
      if (online && receipt['retryActionSource'] != 'settings-ui') {
        await c.retryInitialization().timeout(budget(90));
      }
      await switchTo('fish_drama3_4bit', anchor, document, voice);
      receipt['retryValidated'] = online;
      await playFor(3, 'B4');
      // Use real navigation controls to put B at the original anchor. This
      // avoids comparing different sentences after the three-second B sample.
      await c.jumpBySeconds(-1000000);
      await c.jumpBySeconds(12);
      final backAnchor = c.currentWordIndex;
      require(backAnchor == anchor, 'Could not restore matched A/B/A anchor');
      receipt['returnAnchor'] = backAnchor;
      await switchTo(initial, backAnchor, document, voice);
      await playFor(3, 'returned-A8');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    require(
      !c.hasPendingPlaybackIntent &&
          !c.isPlaying &&
          players.every((player) => !player.playing),
      'Unexpected speech after final Pause',
    );
    receipt['quietTailObservationMs'] = 1000;
    receipt['functionalPassed'] = true;
  } catch (error, stack) {
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
  } finally {
    phase = 'shutdown';
    c.removeListener(observe);
    heartbeat.cancel();
    receipt['lastRuntimeMemorySnapshot'] = MlxSpeechWorkerChunkProcessor
        .debugNativeMemorySnapshot
        ?.toMap();
    receipt['nativeMainResponsiveness'] = await native.close();
    receipt['maxUiHeartbeatDelayMs'] = maxUi;
    // Capture before shutdown because some owners intentionally release their
    // processor reference. Zero/null are unknown, never a qualified 0-byte peak.
    receipt['peakRuntimeBytesByEngine'] = engines
        .map(
          (e) => {
            'engineId': e.engineId,
            'bytes': e.debugPeakMlxRuntimeBytes,
            'measured': (e.debugPeakMlxRuntimeBytes ?? 0) > 0,
            'scope':
                'Existing runtime sampler; not a total application memory envelope',
          },
        )
        .toList();
    final errors = <String>[];
    try {
      await c.pausePlayback().timeout(budget(5, cleanup: true));
    } catch (e) {
      errors.add('Pause: $e');
    }
    // Shutdown owners serially; never allow a late synthesis result to outlive
    // its engine. The runner still owns normal application termination.
    for (final engine in engines) {
      try {
        await engine.shutdownResources().timeout(budget(10, cleanup: true));
      } catch (e) {
        errors.add('Engine shutdown: $e');
      }
    }
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    try {
      await Future.wait(copies).timeout(budget(10, cleanup: true));
    } catch (e) {
      errors.add('Evidence copy join: $e');
    }
    try {
      receipt['generatedProvenance'] = await _provenance(
        root.path,
      ).timeout(budget(10, cleanup: true));
    } catch (e) {
      errors.add('Provenance: $e');
    }
    try {
      await c.shutdownPreparation().timeout(budget(10, cleanup: true));
    } catch (e) {
      errors.add('Preparation shutdown: $e');
    }
    c.dispose();
    for (final player in players) {
      try {
        await player.dispose().timeout(budget(3, cleanup: true));
      } catch (e) {
        errors.add('Player disposal: $e');
      }
    }
    receipt['speechWorkActivity'] = await NativeSpeechWorkActivity.snapshot();
    final activity = receipt['speechWorkActivity'] as Map?;
    receipt['shutdownErrors'] = errors;
    receipt['observationErrors'] = observationErrors;
    receipt['synthesisCallbacks'] = synthesisCalls;
    receipt['resourceShutdownComplete'] =
        errors.isEmpty &&
        activity?['active'] == 0 &&
        activity?['started'] == activity?['ended'];
    receipt['passed'] =
        receipt['functionalPassed'] == true &&
        receipt['resourceShutdownComplete'] == true &&
        observationErrors.isEmpty &&
        evidence.isNotEmpty &&
        synthesisCalls > 0 &&
        maxUi <= 250 &&
        (receipt['nativeMainResponsiveness'] as Map)['passed'] == true;
    await File('${output.path}.pending').writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt),
      flush: true,
    );
    await File('${output.path}.pending').rename(output.path);
    stdout.writeln('S7_VARIANT_COMPLETE passed=${receipt['passed']}');
  }
}
