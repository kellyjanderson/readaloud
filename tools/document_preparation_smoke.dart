// Signed native preparation-only probe. No synthesis/model-loading capability.
// Build via tools/build_macos_release.sh tools/document_preparation_smoke.dart,
// clone to an isolated QA bundle, then invoke with SOURCE_TEXT RECEIPT_JSON.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/tts_engine.dart';

T? _visibleWidget<T extends Widget>() {
  T? result;
  void visit(Element element) {
    if (element.widget is T) result ??= element.widget as T;
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return result;
}

String _words(String text) =>
    RegExp(r'[a-z]+').allMatches(text.toLowerCase()).map((m) => m[0]).join(' ');

bool _tailDisplayed(String needle) {
  final fragments = <String>[];
  var end = false;
  void scan(Element element) {
    final widget = element.widget;
    if (widget is RichText) {
      fragments.add(_words(widget.text.toPlainText()));
    }
    if (widget is Text &&
        (widget.data?.startsWith('End of document') ?? false)) {
      final box = element.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final y = box.localToGlobal(Offset.zero).dy;
        final screen = MediaQuery.sizeOf(element);
        end = y < screen.height && y + box.size.height > 0;
      }
    }
    element.visitChildElements(scan);
  }

  void visit(Element element) {
    if (element.widget is SuperListView) {
      scan(element);
    } else {
      element.visitChildElements(visit);
    }
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return fragments.join(' ').contains(needle) && end;
}

class _ProbeController extends ReaderController {
  _ProbeController(TtsEngine engine)
    : super(ttsEngine: engine, enablePlatformIntakeChannels: false);
  Future<void>? _initialization;
  @override
  Future<void> initialize() => _initialization ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

class _NoInferenceEngine implements TtsEngine {
  int speechRequests = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<List<VoiceProfile>> loadVoices() async => const [
    VoiceProfile(id: 'af_bella', label: 'Probe', locale: 'en-US', rawValue: {}),
  ];
  @override
  Future<void> speak(TtsSpeakRequest request) async {
    speechRequests++;
    throw StateError('Preparation-only probe attempted speech');
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

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 2) exit(2);
  // This executable is only run in an isolated QA bundle/profile.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final engine = _NoInferenceEngine();
  final controller = _ProbeController(engine);
  final receipt = <String, Object?>{'passed': false, 'runs': <Object?>[]};
  Timer? heartbeat;
  var exitCode = 1;
  try {
    runApp(ReadAloudApp(controller: controller));
    await controller.initialize();
    await WidgetsBinding.instance.endOfFrame;
    final source = File(args[0]);
    // A fresh path gives cold repository identity; later imports reuse it.
    final staged = await source.copy(
      '${File(args[1]).parent.path}/source-${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    final sourceWords = _words(await source.readAsString()).split(' ');
    final tail = sourceWords.skip(sourceWords.length - 6).join(' ');
    final maximumMs = int.parse(
      Platform.environment['READALOUD_PREPARATION_MAX_MS'] ?? '5000',
    );
    final runs = int.parse(
      Platform.environment['READALOUD_PREPARATION_RUNS'] ?? '3',
    );
    for (var run = 0; run < runs; run++) {
      final clock = Stopwatch()..start();
      var previousTick = 0;
      var maximumTickGap = 0;
      var ticks = 0;
      heartbeat = Timer.periodic(const Duration(milliseconds: 20), (_) {
        final now = clock.elapsedMilliseconds;
        final gap = now - previousTick;
        if (gap > maximumTickGap) maximumTickGap = gap;
        previousTick = now;
        ticks++;
        WidgetsBinding.instance.scheduleFrame();
      });
      await controller
          .importFilePaths([staged.path])
          .timeout(const Duration(seconds: 5));
      final firstRangeMs = clock.elapsedMilliseconds;
      var tailDisplayed = false;
      while (clock.elapsedMilliseconds < maximumMs) {
        await WidgetsBinding.instance.endOfFrame;
        final view = _visibleWidget<SuperListView>();
        if (view != null && view.listController!.isAttached) {
          view.listController!.jumpToItem(
            index: view.childrenDelegate.estimatedChildCount! - 1,
            scrollController: view.controller!,
            alignment: 0.5,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await WidgetsBinding.instance.endOfFrame;
        tailDisplayed =
            controller.isPreparationComplete && _tailDisplayed(tail);
        if (tailDisplayed) break;
      }
      final elapsed = clock.elapsedMilliseconds;
      await WidgetsBinding.instance.endOfFrame;
      heartbeat.cancel();
      heartbeat = null;
      final activeStages = controller.preparationProgress.values.where(
        (p) =>
            p.state == PreparationWorkState.working ||
            p.state == PreparationWorkState.stalled,
      );
      (receipt['runs'] as List).add({
        'run': run,
        'preparationMs': elapsed,
        'ranges': controller.preparedRangeCount,
        'residentRanges': controller.preparedRanges.length,
        'words': controller.preparedWordCount,
        'firstRangeMs': firstRangeMs,
        'tailDisplayed': tailDisplayed,
        'complete': controller.isPreparationComplete,
        'maximumUiTimerGapMs': maximumTickGap,
        'uiTimerTicks': ticks,
      });
      if (!controller.isPreparationComplete ||
          activeStages.isNotEmpty ||
          engine.speechRequests != 0 ||
          !tailDisplayed ||
          firstRangeMs > 2000 ||
          controller.preparedRanges.length >
              ReaderController.preparedRangeCapacity ||
          elapsed > maximumMs ||
          ticks == 0 ||
          maximumTickGap > 250) {
        throw StateError('Preparation/response gate failed in run $run');
      }
    }
    receipt['speechRequests'] = engine.speechRequests;
    receipt['passed'] = true;
    exitCode = 0;
  } catch (error, stack) {
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
  } finally {
    heartbeat?.cancel();
    await controller.shutdownPreparation();
    controller.dispose();
    await File(
      args[1],
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(receipt));
  }
  exit(exitCode);
}
