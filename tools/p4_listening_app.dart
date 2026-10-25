// Persistent real reader seeded only with a private listening fixture.
// No automatic playback, outcome assertion, timer or auto-exit.
import 'package:flutter/widgets.dart';
import 'dart:io';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'p4_native_assignment_probe.dart' show P4ProbeController;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = P4ProbeController(KokoroTtsEngine());
  runApp(ReadAloudApp(controller: controller));
  await controller.initialize();
  await controller.importPastedText(
    'John said, "The quiet river is beautiful today." Maria replied, "We can walk home together."',
  );
  await controller.selectVoiceById('af_bella');
  controller.showStatusMessage(
    'Short listening fixture ready. Press Play when ready.',
  );
  // The normal Flutter application stays alive until its window is closed.
  stdout.writeln(
    'READALOUD_LISTEN_READY source=${args.firstOrNull ?? 'unspecified'}',
  );
}
