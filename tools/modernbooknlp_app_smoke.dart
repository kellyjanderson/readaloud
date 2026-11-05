// Isolated native probe: real reading UI/provider, silent speech test double.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/screens/read_aloud_screen.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/services/reader_document_repository.dart';
import 'package:read_aloud/src/models/voice_profile.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  if (!support.path.contains('residentNlpTest') || args.length != 1) {
    throw StateError(
      'Use isolated residentNlpTest sandbox and receipt argument',
    );
  }
  final controller = ReaderController(
    documentRepository: ReaderDocumentRepository(
      '${support.path}/resident-probe-${DateTime.now().microsecondsSinceEpoch}',
    ),
    ttsEngine: _SilentEngine(),
    enablePlatformIntakeChannels: false,
  );
  runApp(MaterialApp(home: ReadAloudScreen(controller: controller)));
  final receipt = <String, Object?>{'passed': false};
  Future<void> waitFor(bool Function() ready) async {
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (!ready()) {
      if (DateTime.now().isAfter(end)) {
        throw TimeoutException('Native provider condition');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  try {
    await WidgetsBinding.instance.endOfFrame;
    await waitFor(() => !controller.isInitializing);
    await controller.importPastedText(
      'Ada opened the gate. "Come inside," Ada said. Bruno smiled. "Thank you," Bruno replied.',
    );
    final before = controller.document.dialogueAttributions;
    controller.characterAnalysis.enable();
    var frames = 0;
    void frame(Duration _) {
      frames++;
      if (controller.characterAnalysis.busy) {
        WidgetsBinding.instance.addPostFrameCallback(frame);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(frame);
    final ticks = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => WidgetsBinding.instance.scheduleFrame(),
    );
    await waitFor(
      () =>
          controller.characterAnalysis.result != null ||
          controller.characterAnalysis.error != null,
    );
    ticks.cancel();
    if (controller.characterAnalysis.error != null) {
      throw StateError(controller.characterAnalysis.error!);
    }
    final first = controller.characterAnalysis.result!;
    if (!identical(before, controller.document.dialogueAttributions)) {
      throw StateError('Diagnostic analysis changed attribution');
    }
    await controller.importPastedText('"I will return tomorrow," Miriam said.');
    await waitFor(
      () =>
          controller.characterAnalysis.completedWindows == 2 ||
          controller.characterAnalysis.error != null,
    );
    if (controller.characterAnalysis.error != null) {
      throw StateError(controller.characterAnalysis.error!);
    }
    final second = controller.characterAnalysis.result!;
    if (second['processId'] != first['processId'] ||
        second['reusedModel'] != true) {
      throw StateError('Model was not retained across reading windows');
    }
    await controller.characterAnalysis.stop();
    // A completed window now restores without restarting the model. Demand a
    // genuinely new window to exercise child recreation after Stop.
    await controller.importPastedText('"The path is clear," Juniper said.');
    controller.characterAnalysis.enable();
    await waitFor(
      () =>
          controller.characterAnalysis.completedWindows == 3 ||
          controller.characterAnalysis.error != null,
    );
    if (controller.characterAnalysis.error != null) {
      throw StateError(controller.characterAnalysis.error!);
    }
    receipt.addAll({
      'passed': true,
      'first': first,
      'framesDuringSetup': frames,
      'appSupport': support.path,
      'second': second,
      'afterRetry': controller.characterAnalysis.result,
      'attributionUnchanged': true,
    });
    // Keep the resident child alive for native normal-Quit lifecycle verification.
  } catch (error, stack) {
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
  }
  await File(args.single).writeAsString(
    const JsonEncoder.withIndent('  ').convert(receipt),
    flush: true,
  );
}

class _SilentEngine implements TtsEngine {
  @override
  Future<void> initialize() async {}
  @override
  Future<List<VoiceProfile>> loadVoices() async => [
    const VoiceProfile(
      id: 'test',
      label: 'Test',
      locale: 'en-US',
      rawValue: {},
    ),
  ];
  @override
  Future<void> selectVoice(VoiceProfile voice) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> speak(TtsSpeakRequest request) async {}
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
