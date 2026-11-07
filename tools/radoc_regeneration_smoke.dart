// Native S6 selective-regeneration probe; build this target, args ENGINE RECEIPT.
// Requires existing Fish assets and READALOUD_MLX_{TTS_MODEL_PATH,PYTHON}.
// Optional READALOUD_RADOC_CAPTURE_GATE_PREFIX waits for PREFIX.PHASE files.
// Root runner owns external capture, human listening and normal Quit. No exit().
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/radoc_audio_manifest.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/spoken_chunk_record.dart';
import 'package:read_aloud/src/services/base_speech_annotation_inference_service.dart';
import 'package:read_aloud/src/services/app_launch_options.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';
import 'package:read_aloud/src/services/radoc_audio_package.dart';
import 'package:read_aloud/src/services/rendered_scene_repository.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Only Anna's opening quotation uses her cast identity. The later narration
// exceeds two native scene budgets. Real planner boundaries are asserted below.
const _fixture =
    '''"Keep the little lantern burning until morning," Anna whispered.
The old stone bridge stood above the river while the evening light faded slowly.
Below the narrow arch the water carried fallen leaves towards the distant sea.
A small brass bell hung beside the gate and moved gently in the cool wind.
The path beyond the garden curved between tall trees and disappeared behind a hill.

Across the valley the empty station waited beneath a pale and cloudless autumn sky.
Its wooden benches held a thin layer of dust from the road outside the fence.
Beside the closed ticket window a clock continued counting every quiet minute of the night.
The railway tracks shone softly where the moonlight reached them through the branches overhead.
Nothing moved on the platform except a loose paper turning slowly near the doorway.

At dawn the eastern clouds became pink and the fields emerged from the silver mist.
The first light touched the roofs and windows of the houses along the winding road.
Smoke rose above the village as the baker opened the door beside the market square.
Far beyond the last house the river continued quietly towards the open and waiting sea.''';

class _Controller extends ReaderController {
  _Controller(KokoroTtsEngine engine, Directory root)
    : super(
        ttsEngine: engine,
        renderedSceneRepository: RenderedSceneRepository(root),
        enablePlatformIntakeChannels: false,
        deferInitialSynthesis: true,
      );
  Future<void>? _initialization;
  @override
  Future<void> initialize() => _initialization ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

// Observation only: requests, real cancellation, real callbacks and return
// values are passed unchanged to the production engine. No synthesized output
// or native acknowledgment is substituted by the probe.
class _Engine extends KokoroTtsEngine {
  _Engine(
    AudioPlayer player,
    String id,
    this.events,
    this.phase,
    Future<void> Function() onSynthesis,
  ) : super(
        player: player,
        engineId: id,
        mlxQuantizationBits: int.parse(
          Platform.environment['READALOUD_SMOKE_QUANTIZATION_BITS'] ?? '0',
        ),
        mlxModelPath: Platform.environment['READALOUD_MLX_TTS_MODEL_PATH'],
        mlxPythonPath: Platform.environment['READALOUD_MLX_PYTHON'],
        beforeSynthesis: onSynthesis,
      );
  final List<Map<String, Object?>> events;
  final String Function() phase;
  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    if (events.length >= 32) {
      throw StateError('Export observation bound exceeded');
    }
    final event = <String, Object?>{
      'phase': phase(),
      'sessionId': request.sessionId,
      'sourceWordOffset': request.sourceWordOffset,
      'assignmentRevision': request.assignmentRevision,
      'spans': [
        for (final chunk in request.chunkPlan?.chunks ?? [])
          {
            'chunkId': chunk.chunkId,
            'startWord': request.sourceWordOffset + chunk.startWordIndex,
            'endWord': request.sourceWordOffset + chunk.endWordIndex,
            'turns': [
              for (final turn in chunk.sceneTurns)
                {'castId': turn.castId, 'voice': turn.voiceId},
            ],
          },
      ],
      'completed': false,
    };
    events.add(event);
    try {
      final result = await super.exportAudio(request);
      event['completed'] = true;
      event['chunkCount'] = result.chunkCount;
      return result;
    } catch (error) {
      event['error'] = '$error';
      rethrow;
    }
  }
}

class _Session {
  _Session(this.player, this.engine, this.controller);
  final AudioPlayer player;
  final _Engine engine;
  final _Controller controller;
  bool closed = false;
  Future<void> close() async {
    if (closed) return;
    // Attempt every owner even when an earlier cleanup fails. No app exit here;
    // a stuck native owner is a failed receipt and the runner still normal-Quits.
    final errors = <String>[];
    for (final operation in <Future<void> Function()>[
      engine.stop,
      controller.shutdownPreparation,
      engine.shutdownResources,
    ]) {
      try {
        await operation().timeout(const Duration(seconds: 45));
      } catch (error) {
        errors.add('$error');
      }
    }
    if (errors.isNotEmpty) throw StateError('Resource shutdown: $errors');
    closed = true;
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // In-memory preferences only; never overwrite user selections/resume state.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  if (args.length != 2) {
    stderr.writeln('Usage: radoc_regeneration_smoke FISH_ENGINE RECEIPT');
    runApp(const SizedBox.shrink());
    return;
  }
  final output = File(args[1]).absolute;
  await output.parent.create(recursive: true);
  final runRoot = await Directory(
    output.parent.path,
  ).createTemp('s6-regeneration-');
  final watch = Stopwatch()..start();
  var phase = 'setup';
  var synthesisCallbacks = 0;
  final exports = <Map<String, Object?>>[];
  final metrics = <Map<String, Object?>>[];
  final sessions = <_Session>[];
  final phaseLog = File('${output.path}.phases.jsonl').openWrite();
  final metricLog = File('${output.path}.metrics.jsonl').openWrite();
  final receipt = <String, Object?>{
    'schema': 'readaloud-native-selective-regeneration-v1',
    'passed': false,
    'engine': args[0],
    'runRoot': runRoot.path,
    'firstLaunchTiming': 'not tested; model-backed controlled fixture',
    'emittedAudioCapture': 'external evidence required',
    'humanListening': 'external evidence required',
    'normalQuit': 'runner must request and verify after receipt',
    'exportRequests': exports,
    'phases': <Map<String, Object?>>[],
  };
  var lastTick = 0, maxUiDelayMs = 0;
  final heartbeat = Timer.periodic(const Duration(milliseconds: 50), (_) {
    final now = watch.elapsedMilliseconds;
    maxUiDelayMs = math.max(maxUiDelayMs, now - lastTick - 50);
    lastTick = now;
  });
  PlaybackInstrumentationService.instance.observer = (record) {
    final event = {'phase': phase, ...record.toMap()};
    metricLog.writeln(jsonEncode(event));
    if (record.metric == 'exportChunkReady') {
      if (metrics.length >= 64) {
        receipt['metricObservationOverflow'] = true;
      } else {
        metrics.add(event);
      }
    }
  };
  void mark(String name) {
    phase = name;
    final event = {
      'phase': name,
      'elapsedMs': watch.elapsedMilliseconds,
      'unixMicros': DateTime.now().microsecondsSinceEpoch,
    };
    (receipt['phases']! as List).add(event);
    phaseLog.writeln(jsonEncode(event));
    stdout.writeln('RADOC_REGEN_PHASE ${jsonEncode(event)}');
  }

  _Session createSession(String name, {String? inputPath}) {
    final player = AudioPlayer(useLazyPreparation: false);
    final engine = _Engine(player, args[0], exports, () => phase, () async {
      synthesisCallbacks++;
    });
    final session = _Session(
      player,
      engine,
      _Controller(engine, Directory('${runRoot.path}/$name')),
    );
    sessions.add(session);
    runApp(
      ReadAloudApp(
        controller: session.controller,
        key: ValueKey(name),
        launchOptions: AppLaunchOptions(
          inputPaths: inputPath == null ? const [] : [inputPath],
        ),
      ),
    );
    return session;
  }

  void checkFailure(_Controller controller) {
    if (controller.startupError != null ||
        controller.playbackState == ReaderPlaybackPrimaryState.failed ||
        (controller.statusMessage?.toLowerCase().contains('failed') ?? false)) {
      throw StateError(
        controller.startupError ??
            controller.statusMessage ??
            'Native playback failed',
      );
    }
  }

  Future<void> until(
    bool Function() condition,
    String label,
    _Controller controller, {
    int seconds = 300,
  }) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!condition()) {
      checkFailure(controller);
      if (DateTime.now().isAfter(end)) {
        throw TimeoutException(
          '$label: ${controller.statusMessage}',
          Duration(seconds: seconds),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    checkFailure(controller);
  }

  Future<void> playToEnd(_Session session, String name) async {
    mark(name);
    final gate = Platform.environment['READALOUD_RADOC_CAPTURE_GATE_PREFIX'];
    receipt['controlledCaptureGate'] = gate != null;
    if (gate != null) {
      stdout.writeln(
        'RADOC_REGEN_CAPTURE_WAITING phase=$name path=$gate.$name',
      );
      await until(
        () => File('$gate.$name').existsSync(),
        'External capture readiness',
        session.controller,
        seconds: 120,
      );
    }
    final began = watch.elapsedMilliseconds;
    Object? playError;
    var playFinished = false;
    // Exactly one Play per phase. Errors remain owned/observed while the main
    // isolate samples the real native player. Timeout cleanup cancels the owner.
    final play = session.controller.startPlayback().then<void>(
      (_) => playFinished = true,
      onError: (Object error) {
        playError = error;
        playFinished = true;
      },
    );
    var maxPosition = 0;
    final deadline = DateTime.now().add(const Duration(minutes: 8));
    while (session.controller.playbackState !=
        ReaderPlaybackPrimaryState.completed) {
      checkFailure(session.controller);
      if (playError != null) throw StateError('Play failed: $playError');
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Full source end in $name');
      }
      if (session.player.playing) {
        maxPosition = math.max(
          maxPosition,
          session.player.position.inMilliseconds,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await play.timeout(const Duration(seconds: 5));
    if (playError != null) throw StateError('Play failed: $playError');
    final chunks = session.controller.spokenChunkRecords;
    var nextWord = 0;
    for (final chunk in chunks) {
      if (!chunk.completed || chunk.startWordIndex != nextWord) {
        throw StateError(
          'Missing, repeated or incomplete source span in $name',
        );
      }
      nextWord = chunk.endWordIndex;
    }
    final expected = session.controller.preparedWordCount;
    if (chunks.isEmpty ||
        nextWord != expected ||
        expected <= 0 ||
        !session.controller.isPreparationComplete ||
        maxPosition < 500) {
      throw StateError(
        'No complete native traversal in $name: $nextWord/$expected',
      );
    }
    receipt[name] = {
      'playRequests': 1,
      'playFutureCompleted': playFinished,
      'elapsedMs': watch.elapsedMilliseconds - began,
      'maxNativePositionMs': maxPosition,
      'sourceEndWord': nextWord,
      'chunks': [
        for (final c in chunks)
          {
            'chunkId': c.chunkId,
            'startWord': c.startWordIndex,
            'endWord': c.endWordIndex,
            'completed': c.completed,
            'turns': c.sceneTurns.map((t) => t.toMap()).toList(),
          },
      ],
    };
    stdout.writeln('RADOC_REGEN_SOURCE_END phase=$name word=$nextWord');
  }

  Future<File> save(_Session s, String name) async {
    final file = await s.controller
        .exportDocumentToPath('${runRoot.path}/$name.radoc', audioBook: true)
        .timeout(const Duration(minutes: 2));
    if (file == null || !await RadocAudioPackage.isPackage(file)) {
      throw StateError(
        'Native audio book save failed: ${s.controller.statusMessage}',
      );
    }
    return file;
  }

  try {
    if (!args[0].startsWith('fish_drama3')) {
      throw ArgumentError('Fish engine required');
    }
    final session = createSession('selective-scenes');
    final c = session.controller;
    mark('fixture');
    await c.initialize().timeout(const Duration(minutes: 3));
    await c.completeInitialIntake().timeout(const Duration(minutes: 3));
    checkFailure(c);
    await c.setMultiVoiceEnabled(true);
    final narratorId = Platform.environment['READALOUD_SMOKE_VOICE_ID'];
    if (narratorId != null) await c.selectVoiceById(narratorId);
    await c.importPastedText(_fixture).timeout(const Duration(seconds: 30));
    await until(
      () => c.isPreparationComplete && c.hasCompleteDocumentSnapshot,
      'Fixture preparation',
      c,
      seconds: 45,
    );
    final source = c.document;
    final firstSegment = source.speechDocument.segments.first;
    final direction = SpeechAnnotation(
      annotationId: 's6-explicit-whisper',
      segmentId: firstSegment.segmentId,
      kind: SpeechAnnotationKind.deliveryIntent,
      startWord: 0,
      endWord: firstSegment.wordCount,
      confidence: 1,
      source: SpeechAnnotationSource.userOverride,
      deliveryIntent: DeliveryIntent.whispered,
    );
    final annotations = const BaseSpeechAnnotationInferenceService().infer(
      speechDocument: source.speechDocument,
      displayDocument: source.displayDocument,
      explicitIntents: [direction],
    );
    await c.loadDocument(
      ReaderDocument.fromNormalized(
        title: source.title,
        type: source.type,
        normalizedImportResult: source.normalizedImportResult,
        baseSpeechAnnotations: annotations,
        dialogueAttributions: source.dialogueAttributions,
        characterCastRegistry: source.characterCastRegistry,
        documentVoiceAttribution: source.documentVoiceAttribution,
        basePronunciationArtifacts: source.basePronunciationArtifacts,
      ),
    );
    final anna = c.characterCastRegistry.characterEntries.singleWhere(
      (entry) => entry.displayLabel == 'Anna',
    );
    final choices = c.voices
        .where((v) => v.id.startsWith('library_fish'))
        .toList();
    if (choices.length < 2) {
      throw StateError('Need two real Fish reference voices');
    }
    final beforeVoice =
        Platform.environment['READALOUD_REGEN_VOICE_BEFORE'] ??
        choices.first.id;
    final afterVoice =
        Platform.environment['READALOUD_REGEN_VOICE_AFTER'] ?? choices.last.id;
    if (beforeVoice == afterVoice ||
        !choices.any((v) => v.id == beforeVoice) ||
        !choices.any((v) => v.id == afterVoice)) {
      throw StateError(
        'Character choices must be distinct available Fish voices',
      );
    }
    await c.assignVoiceToCast(anna.castId, beforeVoice);
    receipt['fixture'] = {
      'text': _fixture,
      'words': c.document.wordCount,
      'castId': anna.castId,
      'voiceBefore': beforeVoice,
      'voiceAfter': afterVoice,
      'canonicalDirection': direction.toJson(),
    };
    await playToEnd(session, 'initial');
    if (exports.isNotEmpty) {
      throw StateError('Initial ordinary reading unexpectedly exported');
    }
    mark('initial-save');
    final original = await save(session, 'initial');
    final initial = await _inspectBook(original.path);
    receipt['initialBook'] = initial;
    if (initial['totalWords'] != c.document.wordCount) {
      throw StateError('Saved source extent differs from the complete fixture');
    }
    final initialScenes = (initial['scenes'] as List)
        .cast<Map<String, Object?>>();
    if (initialScenes.length < 3) {
      throw StateError('Fixture produced fewer than three native scenes');
    }
    final affected = initialScenes
        .where(
          (s) => (s['turns'] as List).any(
            (t) => (t as Map)['castId'] == anna.castId,
          ),
        )
        .toList();
    if (affected.length != 1 || affected.single['startWord'] != 0) {
      throw StateError('Anna must occur only in the first native scene');
    }
    _requireVoice(affected.single, anna.castId, beforeVoice);
    final missingScene = initialScenes[1];
    final missingPath = '${runRoot.path}/missing-middle.radoc';
    await _makeMissingSceneBook(
      original.path,
      missingPath,
      missingScene['sceneId']! as String,
    );
    final copied = await original.copy('${runRoot.path}/copied-initial.radoc');
    mark('copy-reopen');
    await c.importFilePaths([copied.path]).timeout(const Duration(minutes: 2));
    if (!c.hasPublishedAudio) {
      throw StateError('Physical copy lost published audio');
    }
    await c
        .assignVoiceToCast(anna.castId, afterVoice)
        .timeout(const Duration(seconds: 30));
    final exportStart = exports.length;
    await playToEnd(session, 'changed');
    _requireOnlySceneExports(exports.sublist(exportStart), affected.single);
    mark('changed-save');
    final changedFile = await save(session, 'changed');
    final changed = await _inspectBook(changedFile.path);
    receipt['changedBook'] = changed;
    _compareBooks(
      initial,
      changed,
      affected.single['sceneId']! as String,
      anna.castId,
      afterVoice,
    );
    final changedCopy = await changedFile.copy(
      '${runRoot.path}/copied-changed.radoc',
    );
    final count = exports.length, callbacks = synthesisCallbacks;
    mark('saved-reopen');
    await c
        .importFilePaths([changedCopy.path])
        .timeout(const Duration(minutes: 2));
    await playToEnd(session, 'reused');
    if (exports.length != count || synthesisCallbacks != callbacks) {
      throw StateError('Saved edited book repeated export/inference');
    }
    receipt['savedReopenReuse'] = {
      'additionalExports': 0,
      'additionalSynthesisCallbacks': 0,
    };
    await session.close();
    // Fresh store: neither the initial render nor changed-boundary output can
    // fill the intentional missing scene behind the controller's back.
    // This second simulated launch must not inherit the first launch's changed
    // Character choice through the in-memory preferences backend.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final missing = createSession('missing-scenes', inputPath: missingPath);
    mark('missing-import');
    await missing.controller.initialize().timeout(const Duration(seconds: 30));
    // Normal screen launch intake owns this import; never race a second import
    // or empty-input synthesis startup against it.
    await until(
      () =>
          missing.controller.hasPublishedAudio &&
          !missing.controller.isImporting,
      'Missing-scene launch intake',
      missing.controller,
      seconds: 120,
    );
    final missingStart = exports.length;
    await playToEnd(missing, 'missing');
    _requireOnlySceneExports(exports.sublist(missingStart), missingScene);
    mark('missing-save');
    final repaired = await save(missing, 'repaired-middle');
    final repairedEvidence = await _inspectBook(repaired.path);
    receipt['repairedBook'] = repairedEvidence;
    _compareBooks(
      initial,
      repairedEvidence,
      missingScene['sceneId']! as String,
    );
    final ready = metrics
        .where((m) => m['metric'] == 'exportChunkReady')
        .toList();
    receipt['exportChunkReady'] = ready;
    if (ready.isEmpty || receipt['metricObservationOverflow'] == true) {
      throw StateError('Production exportChunkReady evidence absent');
    }
    for (final event in ready) {
      final value = event['value'];
      if (value is! Map ||
          value['cacheHit'] is! bool ||
          value['startWord'] is! int ||
          value['endWord'] is! int ||
          value['rawArtifactIdentity'] is! String) {
        throw StateError('Incomplete production exportChunkReady evidence');
      }
    }
    for (final expected in {
      'changed': affected.single,
      'missing': missingScene,
    }.entries) {
      final observed = ready.where((event) => event['phase'] == expected.key);
      if (observed.length != 1) {
        throw StateError('Expected one real export chunk in ${expected.key}');
      }
      final value = observed.single['value']! as Map;
      if (value['startWord'] != expected.value['startWord'] ||
          value['endWord'] != expected.value['endWord']) {
        throw StateError('Export chunk escaped affected source span');
      }
    }
    if (ready.length != 2) {
      throw StateError('Unexpected export chunk outside regeneration phases');
    }
    receipt['passed'] = true;
  } catch (error, stack) {
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
  } finally {
    mark('shutdown');
    heartbeat.cancel();
    final cleanupErrors = <String>[];
    for (final session in sessions) {
      try {
        await session.close();
      } catch (error) {
        cleanupErrors.add('$error');
      }
    }
    PlaybackInstrumentationService.instance.observer = null;
    receipt.addAll({
      'synthesisCallbacks': synthesisCallbacks,
      'maxUiHeartbeatDelayMs': maxUiDelayMs,
      'elapsedMs': watch.elapsedMilliseconds,
      'resourceShutdownComplete': cleanupErrors.isEmpty,
      'shutdownErrors': cleanupErrors,
    });
    if (cleanupErrors.isNotEmpty) receipt['passed'] = false;
    await metricLog.close();
    await phaseLog.close();
    final staged = File('${output.path}.pending');
    await staged.writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt),
      flush: true,
    );
    await staged.rename(output.path);
    stdout.writeln(
      'RADOC_REGEN_COMPLETE passed=${receipt['passed']} receipt=${output.path}',
    );
  }
}

void _requireVoice(Map<String, Object?> scene, String cast, String voice) {
  final turns = (scene['turns'] as List).where(
    (t) => (t as Map)['castId'] == cast,
  );
  if (turns.isEmpty || turns.any((t) => (t as Map)['voice'] != voice)) {
    throw StateError(
      'Affected scene did not bind the selected Character voice',
    );
  }
}

void _requireOnlySceneExports(
  List<Map<String, Object?>> events,
  Map<String, Object?> scene,
) {
  if (events.length != 1 || events.single['completed'] != true) {
    throw StateError(
      'Expected exactly one completed real scene export: $events',
    );
  }
  final spans = events.single['spans']! as List;
  if (spans.length != 1 ||
      (spans.single as Map)['startWord'] != scene['startWord'] ||
      (spans.single as Map)['endWord'] != scene['endWord']) {
    throw StateError('Export escaped the one affected native scene: $events');
  }
}

void _compareBooks(
  Map<String, Object?> before,
  Map<String, Object?> after,
  String changedId, [
  String? cast,
  String? voice,
]) {
  final original = (before['scenes'] as List).cast<Map<String, Object?>>();
  final next = (after['scenes'] as List).cast<Map<String, Object?>>();
  if (before['sourceId'] != after['sourceId'] ||
      before['totalWords'] != after['totalWords'] ||
      original.length != next.length) {
    throw StateError('Save changed source extent or native scene count');
  }
  for (final scene in original) {
    final updated = next.singleWhere((s) => s['sceneId'] == scene['sceneId']);
    if (scene['startWord'] != updated['startWord'] ||
        scene['endWord'] != updated['endWord'] ||
        scene['sourceTextSha256'] != updated['sourceTextSha256'] ||
        jsonEncode(scene['canonicalDirections']) !=
            jsonEncode(updated['canonicalDirections'])) {
      throw StateError('Scene source coverage or canonical direction changed');
    }
    if (scene['sceneId'] == changedId) {
      if (cast != null && voice != null) {
        _requireVoice(updated, cast, voice);
        if (scene['rawSha256'] == updated['rawSha256'] ||
            scene['rawArtifactIdentity'] == updated['rawArtifactIdentity']) {
          throw StateError(
            'Distinct Character conditioning did not change affected raw output',
          );
        }
      }
    } else if (scene['rawSha256'] != updated['rawSha256'] ||
        scene['rawArtifactIdentity'] != updated['rawArtifactIdentity']) {
      throw StateError(
        'Unaffected scene raw identity/hash changed: ${scene['sceneId']}',
      );
    }
  }
}

// Package owner bounds work and bulk I/O in its existing worker. Actual file
// hashes are worker-owned too; manifest checksums alone are not raw-byte proof.
Future<Map<String, Object?>> _inspectBook(String path) async {
  final package = RadocAudioPackage();
  try {
    final book = await package.open(File(path));
    final manifest = book.manifest;
    if (!manifest.renderingComplete) {
      throw StateError('Saved book has incomplete source coverage');
    }
    final scenes = <Map<String, Object?>>[];
    for (final scene in manifest.scenes) {
      if (scene.rawAudioMember == null) {
        throw StateError('Missing reusable raw audio');
      }
      final file = await package.materializeMember(book, scene.rawAudioMember!);
      final filePath = file.path;
      final digest = await Isolate.run(
        () async =>
            (await sha256.bind(File(filePath).openRead()).first).toString(),
      );
      final raw = scene.dependencies['raw'] as Map?;
      scenes.add({
        'sceneId': scene.sceneId,
        'startWord': scene.startWord,
        'endWord': scene.endWord,
        'rawSha256': digest,
        'rawArtifactIdentity': scene.provenance['rawArtifactIdentity'],
        'sourceTextSha256': sha256
            .convert(utf8.encode(scene.provenance['text']! as String))
            .toString(),
        'audioSha256': manifest.members
            .singleWhere((m) => m.name == scene.audioMember)
            .sha256,
        'dependencyDigest': scene.dependencyDigest,
        'canonicalDirections': raw?['canonicalDirections'],
        'turns': scene.provenance['sceneTurns'],
        'sampleRate': scene.sampleRate,
      });
      if (scene.sampleRate != 44100 ||
          scene.provenance['rawArtifactIdentity'] is! String) {
        throw StateError('Missing native-rate Fish raw provenance');
      }
    }
    if (!scenes.any(
      (s) => (s['canonicalDirections'] as List? ?? []).any(
        (direction) =>
            (direction as Map)['delivery'] == 'whispered' &&
            direction['source'] == 'userOverride',
      ),
    )) {
      throw StateError('Explicit canonical direction was lost');
    }
    return {
      'path': path,
      'sourceId': manifest.sourceId,
      'totalWords': manifest.totalWords,
      'scenes': scenes,
    };
  } finally {
    await package.dispose();
  }
}

Future<void> _makeMissingSceneBook(
  String source,
  String output,
  String sceneId,
) async {
  final package = RadocAudioPackage();
  try {
    final book = await package.open(File(source));
    final m = book.manifest;
    final partial = RadocAudioManifest(
      documentId: m.documentId,
      sourceId: m.sourceId,
      preparationComplete: m.preparationComplete,
      totalWords: m.totalWords,
      preparedRanges: m.preparedRanges,
      analysisMembers: m.analysisMembers,
      scenes: m.scenes.where((s) => s.sceneId != sceneId),
      intent: m.intent,
    );
    final files = <String, File>{};
    for (final name in partial.referencedMembers) {
      files[name] = await package.materializeMember(book, name);
    }
    await package.export(
      destination: File(output),
      manifest: partial,
      members: files,
    );
  } finally {
    await package.dispose();
  }
}
