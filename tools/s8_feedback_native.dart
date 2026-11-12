// UI-only native probe. Build/sign/clone to an isolated feedbackTest bundle
// before using run_s8_feedback_native.rb. No inference, audio, network, or native
// input is simulated. Gate acknowledgements only release this fixture producer;
// the coordinator records the actual keyboard/layout/accessibility observations.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/reader_operation.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/reader_document_repository.dart';
import 'package:read_aloud/src/services/modernbooknlp_analysis.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/rendered_scene_repository.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/services/work_character_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_main_responsiveness_probe.dart';

// Top-level worker adapters capture only these small immutable arguments. In
// particular, no isolate closure shares _Probe.run's controller/publish context.
Future<int> _writePrivateFile(String path, String content) =>
    Isolate.run(() async {
      final file = await File(path).writeAsString(content, flush: true);
      return file.length();
    });

Future<void> _createPrivateDirectory(String path) => Isolate.run(() async {
  await Directory(path).create(recursive: true);
});

Future<int> _privateFileSize(String path) =>
    Isolate.run(() => File(path).length());

Future<void> _writePrivateJson(String path, String payload) =>
    Isolate.run(() async {
      final staging = File('$path.pending');
      await staging.writeAsString(payload, flush: true);
      await staging.rename(path);
    });

Future<int> _validatePrivateFiles(String root, List<String> fixtures) =>
    Isolate.run(() async {
      var bytes = 0;
      for (var i = 0; i < fixtures.length; i++) {
        final actual = await File('$root/counted-$i.txt').readAsString();
        if (actual != fixtures[i]) throw StateError('Local fixture mismatch');
        bytes += utf8.encode(actual).length;
      }
      return bytes;
    });

class _NoInferenceEngine implements TtsEngine {
  int speechRequests = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<List<VoiceProfile>> loadVoices() async => const [
    VoiceProfile(
      id: 'af_bella',
      label: 'UI probe',
      locale: 'en-US',
      rawValue: {},
    ),
  ];
  @override
  Future<void> speak(TtsSpeakRequest request) async {
    speechRequests++;
    throw StateError('UI-only probe has no synthesis capability');
  }

  @override
  Future<void> selectVoice(VoiceProfile voice) async {}
  @override
  Future<void> setSpeechRate(double multiplier) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ProbeController extends ReaderController {
  _ProbeController(_NoInferenceEngine engine, String root)
    : super(
        ttsEngine: engine,
        // Even an accidental Settings engine change can only select this inert
        // engine. Never fall through to the default MLX/Kokoro factory.
        engineFactory: (_, _) => engine,
        characterAnalysis: ModernBookNlpAnalysis(
          () async => throw StateError('UI-only probe has no neural provider'),
        ),
        enablePlatformIntakeChannels: false,
        documentRepository: ReaderDocumentRepository('$root/prepared'),
        preferencesService: ReaderPreferencesService(
          workRepository: WorkCharacterRepository('$root/works'),
        ),
        renderedSceneRepository: RenderedSceneRepository(
          Directory('$root/scenes'),
        ),
      );
  Future<void>? _initialization;
  Future<void> _activityWrite = Future<void>.value();
  @override
  Future<void> initialize() => _initialization ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
  @override
  Future<void> setActivityExpanded(bool value) {
    final work = super.setActivityExpanded(value);
    _activityWrite = work;
    return work;
  }

  Future<void> drainUiPreferences() => _activityWrite;
}

class _LocalAccessibilitySettings extends StatelessWidget {
  const _LocalAccessibilitySettings(this.controller);
  final ReaderController controller;
  @override
  Widget build(BuildContext context) => MediaQuery(
    // runApp supplies View above this widget. This changes only this subtree,
    // never macOS accessibility preferences or user SharedPreferences.
    data: MediaQueryData.fromView(
      View.of(context),
    ).copyWith(textScaler: TextScaler.linear(2), disableAnimations: true),
    child: ReadAloudApp(controller: controller),
  );
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Map<String, Object?> _operation(ReaderOperation p) => {
  'operationId': p.operationId,
  'key': p.key,
  'owner': p.ownerKind.name,
  'stage': p.stage,
  'scope': p.scope,
  'state': p.state.name,
  'visibleState': p.visibleState.name,
  'completed': p.completedUnits,
  'total': p.totalUnits,
  'unit': p.unit,
  'readerBlocking': p.readerBlocking,
  'retryOf': p.retryOf,
  'error': p.error,
};

bool _hasKey(String key) {
  var found = false;
  void visit(Element element) {
    if (element.widget.key == ValueKey<String>(key)) found = true;
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

class _Probe {
  _Probe(this.root, this.controller, this.workSeconds);
  final String root;
  final _ProbeController controller;
  final int workSeconds;
  final Stopwatch clock = Stopwatch()..start();
  String phase = 'initialization';
  final List<Map<String, Object?>> snapshots = [];
  final List<Map<String, Object?>> activityChanges = [];
  bool? _lastActivity;
  ReadingStageTicket? _controlledTicket;

  void retireControlledWork(Object error) {
    final ticket = _controlledTicket;
    if (ticket == null) return;
    final current = controller.feedbackOperations
        .where((p) => p.scope == ticket.scope)
        .firstOrNull;
    if (current == null || current.state.isTerminal) return;
    controller.publishReadingStage(
      ticket,
      PreparationProgress(
        stage: ticket.stage,
        state: error is TimeoutException
            ? PreparationWorkState.cancelled
            : PreparationWorkState.failed,
        completed: current.completedUnits,
        total: current.totalUnits,
        unit: current.unit,
        error: error is TimeoutException ? null : '$error',
      ),
    );
  }

  Duration get remaining {
    final milliseconds = workSeconds * 1000 - clock.elapsedMilliseconds;
    if (milliseconds <= 0) throw TimeoutException('UI probe work deadline');
    return Duration(milliseconds: milliseconds);
  }

  void activityChanged() {
    if (_lastActivity == controller.activityExpanded) return;
    _lastActivity = controller.activityExpanded;
    activityChanges.add({
      'elapsedMs': clock.elapsedMilliseconds,
      'phase': phase,
      'expanded': controller.activityExpanded,
    });
  }

  Future<void> writeJson(String name, Object data) async {
    final path = '$root/$name';
    final payload = const JsonEncoder.withIndent('  ').convert(data);
    await _writePrivateJson(path, payload);
  }

  Future<void> gate(String name, String instructions) async {
    phase = name;
    await WidgetsBinding.instance.endOfFrame;
    final snapshot = <String, Object?>{
      'phase': phase,
      'elapsedMs': clock.elapsedMilliseconds,
      'instructions': instructions,
      'acknowledgement': '$root/$name.continue',
      'activityExpanded': controller.activityExpanded,
      'operations': controller.feedbackOperations.map(_operation).toList(),
    };
    snapshots.add(snapshot);
    await writeJson('$name.ready.json', snapshot);
    stdout.writeln('S8_GATE $name $root/$name.continue');
    // One pending stat at a time. No file watcher or unbounded event queue.
    while (!await File('$root/$name.continue').exists()) {
      final left = remaining;
      await Future<void>.delayed(
        left < const Duration(milliseconds: 100)
            ? left
            : const Duration(milliseconds: 100),
      );
    }
    remaining; // An acknowledgement after the deadline cannot pass the gate.
  }

  Future<void> waitFor(bool Function() ready) async {
    while (!ready()) {
      remaining;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> run(_NoInferenceEngine engine) async {
    await controller.initialize().timeout(remaining);
    _require(controller.startupError == null, 'Inert-engine startup failed');
    final source = '$root/short-source.txt';
    await _writePrivateFile(
      source,
      'The lamps along the quay flickered in the wind. '
      'Mara closed the gate and listened. Nothing moved beyond the wall.\n',
    );
    await controller.importFilePaths([source]).timeout(remaining);
    await waitFor(() => controller.isPreparationComplete);
    _require(controller.hasCompleteDocumentSnapshot, 'Missing real checkpoint');
    _require(controller.preparedWordCount > 0, 'Short source was not prepared');
    _require(
      controller.feedbackOperations.every((p) => p.state.isTerminal),
      'Source EOF left an active operation',
    );
    _require(
      !controller.feedbackOperations.any(
        (p) => ['planning', 'resources', 'synthesis'].contains(p.stage),
      ),
      'Inactive downstream work created placeholder rows',
    );
    await controller.clearStatus();
    await gate(
      'ready',
      'Observe Ready to read and no active spinner. Use native keyboard to '
          'expand Activity, then collapse it; resize narrow and inspect 2x text. '
          'This subtree requests reduced motion. Native observations remain '
          'separate from these controller assertions.',
    );

    // This ticket owns exactly two small local files. Main isolate owns only
    // immutable counters; each awaited worker owns its file handle and exits
    // before the next worker starts. No queued writes, stale mutation or timer
    // inferred completion. The controller ticket guards document replacement.
    final ticket = controller.beginReadingStage(
      PreparationStage.persistence,
      producerId: 's8-controlled-local-file-writer',
      scope: 'Controlled local files (UI fixture)',
    );
    _controlledTicket = ticket;
    var completed = 0;
    int? total;
    void publish(PreparationWorkState state, {String? message}) {
      controller.publishReadingStage(
        ticket,
        PreparationProgress(
          stage: PreparationStage.persistence,
          state: state,
          completed: completed,
          total: total,
          unit: 'bytes',
          waitingReason: message,
        ),
      );
    }

    publish(PreparationWorkState.working, message: 'Discovering local fixture');
    await gate(
      'unknown',
      'Observe real 0 bytes with unknown total; no percent.',
    );
    final fixtures = <String>[
      List.filled(256, 'first local file\n').join(),
      List.filled(256, 'second local file\n').join(),
    ];
    total = fixtures.fold<int>(0, (n, text) => n + utf8.encode(text).length);
    for (var i = 0; i < fixtures.length; i++) {
      final path = '$root/counted-$i.txt';
      final content = fixtures[i];
      completed += await _writePrivateFile(path, content);
      publish(PreparationWorkState.working, message: '${i + 1} files flushed');
      if (i == 0) {
        await gate('known', 'Observe the measured partial byte count and bar.');
      }
    }
    final counted = controller.feedbackOperations.singleWhere(
      (p) => p.scope == ticket.scope,
    );
    _require(
      counted.completedUnits == total,
      'Count differs from flushed bytes',
    );
    _require(
      counted.state == OperationState.running &&
          counted.visibleState == OperationState.finalizing,
      'Counted bytes were incorrectly treated as terminal success',
    );
    await gate(
      'finalizing',
      'Observe counted bytes still finalizing, not Ready. Open Activity with '
          'the keyboard, inspect active-first order, narrow layout and Copy. '
          'Validation remains explicitly pending until this gate is released.',
    );
    final verifiedBytes = await _validatePrivateFiles(root, fixtures);
    _require(verifiedBytes == total, 'File validation byte mismatch');
    publish(PreparationWorkState.complete, message: '2 local files validated');
    _controlledTicket = null;
    await gate(
      'terminal',
      'Observe terminal success and Ready after validation.',
    );

    // A real package Save, forced for a prepared text-only partial audio book,
    // encounters this owned directory where an output file must be committed.
    // No speech/model request is needed for this production persistence path.
    final invalidDestination = '$root/failure.radoc';
    await _createPrivateDirectory(invalidDestination);
    final failedSave = await controller
        .exportDocumentToPath(invalidDestination, audioBook: true)
        .timeout(remaining);
    _require(
      failedSave == null,
      'Invalid Save destination unexpectedly worked',
    );
    final failure = controller.feedbackOperations.singleWhere(
      (p) => p.scope == 'Save audio book' && p.state == OperationState.failed,
    );
    _require(
      failure.error?.isNotEmpty == true,
      'Save produced no durable error',
    );
    _require(
      controller.statusOwnedByInlineFailure,
      'Save lost inline ownership',
    );
    await WidgetsBinding.instance.endOfFrame;
    _require(
      !_hasKey('status-toast'),
      'Save duplicated its inline error toast',
    );
    _require(
      _hasKey('clear-operation-failure'),
      'Save has no Clear error action',
    );
    await gate(
      'copy-error',
      'Observe persistent Save error and no duplicate toast. Use native Copy '
          'on this known fixture error BEFORE acknowledging; the next step reads '
          'the clipboard once and requires the exact fixture error text.',
    );
    // This is intentionally the ONLY clipboard read, after explicit coordinator
    // release of the known-error Copy gate. Never inspect prior user clipboard.
    final copied = await Clipboard.getData(Clipboard.kTextPlain);
    _require(
      copied?.text?.contains(failure.error!) == true,
      'Copy did not contain this fixture Save error',
    );
    await gate(
      'clear-error',
      'Activate the actual Clear error button via native input, then acknowledge. '
          'Activity must retain the failed operation and its error.',
    );
    final cleared = controller.feedbackOperations.singleWhere(
      (p) => p.key == failure.key,
    );
    _require(
      cleared.state == OperationState.failed &&
          cleared.error == failure.error &&
          !cleared.readerBlocking,
      'Native Clear did not retain the nonblocking failed record',
    );
    await WidgetsBinding.instance.endOfFrame;
    _require(
      !_hasKey('clear-operation-failure'),
      'Clear action remains active',
    );
    await gate(
      'cleared',
      'Observe Ready and open Activity to inspect the retained failed record. '
          'Enable Activity before acknowledgement to check saved preference.',
    );
    _require(controller.activityExpanded, 'Activity was not enabled via UI');
    await controller.drainUiPreferences().timeout(remaining);
    final prefs = await SharedPreferences.getInstance();
    _require(
      prefs.getBool('reader.activityExpanded') == true,
      'UI Activity change was not saved in the mock preference store',
    );
    final destination = '$root/retry.radoc';
    final saved = await controller
        .exportDocumentToPath(destination, audioBook: true)
        .timeout(remaining);
    _require(saved != null, 'Real Save retry failed');
    final retry = controller.feedbackOperations.singleWhere(
      (p) =>
          p.scope == 'Save audio book' && p.state == OperationState.succeeded,
    );
    _require(
      retry.operationId != failure.operationId &&
          retry.retryOf == failure.operationId,
      'Save retry lost its new identity or failed-attempt linkage',
    );
    _require(
      await _privateFileSize(destination) > 0,
      'Successful Save has no output bytes',
    );
    _require(engine.speechRequests == 0, 'UI probe attempted speech');
    await gate(
      'retry-success',
      'Observe successful Save retry and Ready. This is text-only package '
          'persistence, not emitted-audio or actual model-download evidence. '
          'Acknowledge to drain all owners and let the runner use normal Quit.',
    );
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 1 ||
      Platform.environment['READALOUD_S8_NORMAL_QUIT'] != '1') {
    stderr.writeln(
      'Use run_s8_feedback_native.rb with an isolated signed app.',
    );
    exit(2);
  }
  final root = Directory(args.single).absolute.path;
  if (await Directory(root).exists()) {
    stderr.writeln('Probe output already exists: $root');
    exit(2);
  }
  await _createPrivateDirectory(root);
  final seconds = int.parse(
    Platform.environment['READALOUD_S8_WORK_SECONDS'] ?? '480',
  );
  if (seconds < 30 || seconds > 600) exit(2);
  // No persistent application preferences are read or changed.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'reader.ttsEngineId': 'kokoro'});
  final engine = _NoInferenceEngine();
  final controller = _ProbeController(engine, root);
  final probe = _Probe(root, controller, seconds);
  final native = NativeMainResponsivenessProbe();
  // QA differential only. The heartbeat still measures UI scheduling when the
  // extra frame requests are disabled; normal widget animations remain owned
  // by Flutter and are not suppressed.
  final forceHeartbeatFrames =
      Platform.environment['READALOUD_S8_FORCE_HEARTBEAT_FRAMES'] == '1';
  var forcedFrameRequests = 0;
  final receipt = <String, Object?>{
    'passed': false,
    'scope':
        'UI-only real app/controller, real short preparation and Save; '
        'controlled private file producer; no network/model/audio acceptance',
    'localTextScale': 2,
    'localDisableAnimations': true,
    'workDeadlineSeconds': seconds,
    'crossRelaunchPreferenceClaim': false,
    'forceHeartbeatFrames': forceHeartbeatFrames,
  };
  Timer? heartbeat;
  final uiClock = Stopwatch()..start();
  var previousTick = 0, maxTickGap = 0, ticks = 0;
  controller.addListener(probe.activityChanged);
  probe.activityChanged();
  try {
    runApp(_LocalAccessibilitySettings(controller));
    native.start(() => probe.phase);
    heartbeat = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final now = uiClock.elapsedMilliseconds;
      final gap = now - previousTick;
      if (gap > maxTickGap) maxTickGap = gap;
      previousTick = now;
      ticks++;
      if (forceHeartbeatFrames) {
        WidgetsBinding.instance.scheduleFrame();
        forcedFrameRequests++;
      }
    });
    // All waits check the same work deadline. Keep this future joined rather
    // than abandoning a timeout wrapper while its producer still runs.
    await probe.run(engine);
    receipt['passed'] = true;
  } catch (error, stack) {
    probe.retireControlledWork(error);
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
    stderr.writeln('S8_FAILURE $error');
  } finally {
    probe.phase = 'cleanup';
    heartbeat?.cancel();
    controller.removeListener(probe.activityChanged);
    receipt['nativeMain'] = await native.close();
    receipt['uiTimerTicks'] = ticks;
    receipt['forcedFrameRequests'] = forcedFrameRequests;
    receipt['maximumUiTimerGapMs'] = maxTickGap;
    receipt['speechRequests'] = engine.speechRequests;
    receipt['snapshots'] = probe.snapshots;
    receipt['activityChanges'] = probe.activityChanges;
    receipt['elapsedMs'] = probe.clock.elapsedMilliseconds;
    try {
      await controller.drainUiPreferences().timeout(const Duration(seconds: 2));
      await controller.shutdownPreparation().timeout(
        const Duration(seconds: 20),
      );
      // Unmount first, so widget timers/subscriptions cannot reach disposal.
      runApp(const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame;
      controller.dispose();
      receipt['ownersDrained'] = true;
    } catch (error, stack) {
      receipt['passed'] = false;
      receipt['cleanupError'] = '$error';
      receipt['cleanupStack'] = '$stack';
    }
    final nativeResult = receipt['nativeMain'] as Map<String, Object?>;
    if (ticks == 0 || maxTickGap > 250 || nativeResult['passed'] != true) {
      receipt['passed'] = false;
      receipt['responsivenessFailure'] = true;
    }
    await probe.writeJson('receipt.json', receipt);
    stdout.writeln('S8_RECEIPT $root/receipt.json');
    // Deliberately remain alive. The runner calls normal Quit only after the
    // cleanup receipt is complete, then verifies this owned PID/group exited.
  }
}
