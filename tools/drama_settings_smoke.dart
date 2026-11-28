import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';
// Optional native acceptance probe: real settings/startup model download,
// private fiction display and model replacement, without waiting for weights.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';

class _Controller extends ReaderController {
  _Controller() : super(enablePlatformIntakeChannels: false);
  Future<void>? _initialization;
  @override
  Future<void> initialize() => _initialization ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 2) exit(2);
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'reader.ttsEngineId': 'fish_drama3'});
  final controller = _Controller();
  final receipt = <String, Object?>{
    'passed': false,
    'dramaPlaybackTested': false,
  };
  runApp(ReadAloudApp(controller: controller));
  final startup = controller.initialize();
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (controller.speechResourceProgress?.stage != 'modelDownload') {
      if (controller.startupError != null) {
        throw StateError(controller.startupError!);
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('No app-owned download progress');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    receipt['downloadStartedAtLaunch'] = true;
    receipt['voices'] = controller.voices.map((v) => v.id).toList();
    await controller.importFilePaths([args[0]]);
    final preparationDeadline = DateTime.now().add(const Duration(seconds: 20));
    while (!controller.isPreparationComplete &&
        DateTime.now().isBefore(preparationDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    receipt['words'] = controller.preparedWordCount;
    final hold =
        int.tryParse(
          Platform.environment['READALOUD_SMOKE_HOLD_SECONDS'] ?? '0',
        ) ??
        0;
    if (hold > 0) await Future<void>.delayed(Duration(seconds: hold));
    if (controller.preparedWordCount < 5000 || controller.voices.length < 5) {
      throw StateError('Fiction or voice choices missing');
    }
    receipt['beforeSwitchError'] = controller.startupError;
    final watch = Stopwatch()..start();
    await controller
        .setTtsEngineId('kokoro')
        .timeout(const Duration(seconds: 20));
    await startup;
    receipt['switchMillis'] = watch.elapsedMilliseconds;
    receipt['runningEngine'] = controller.runningTtsEngineId;
    receipt['startupError'] = controller.startupError;
    if (controller.runningTtsEngineId != 'kokoro' ||
        controller.startupError != null) {
      throw StateError('Replacement did not become ready');
    }
    // Repeat via settings path: downloads must begin without pressing Play.
    final selection = controller.setTtsEngineId('fish_drama3_4bit');
    final secondDeadline = DateTime.now().add(const Duration(seconds: 60));
    while (controller.speechResourceProgress?.stage != 'modelDownload') {
      if (controller.startupError != null) {
        throw StateError(controller.startupError!);
      }
      if (DateTime.now().isAfter(secondDeadline)) {
        throw StateError('No selection download progress');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    receipt['downloadStartedOnSelection'] = true;
    await controller
        .setTtsEngineId('kokoro')
        .timeout(const Duration(seconds: 20));
    await selection;
    receipt['peakRuntimeBytes'] = MlxTtsPythonProcess.observedPeakRuntimeBytes;
    receipt['passed'] =
        receipt['beforeSwitchError'] == null &&
        controller.startupError == null &&
        MlxTtsPythonProcess.observedPeakRuntimeBytes > 0;
  } catch (error, stack) {
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
  } finally {
    await controller.pausePlayback();
    await controller.shutdownPreparation();
    controller.dispose();
    await File(
      args[1],
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(receipt));
    exit(receipt['passed'] == true ? 0 : 1);
  }
}
