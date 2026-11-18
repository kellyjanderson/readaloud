// Diagnostic target only. Uses production import, planning, resource, Fish and
// assembly owners; no synthetic audio and no user-facing acceptance claim.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 4) {
    throw ArgumentError('NEW_OUTPUT OLD_SOURCE_OR_DASH SOURCE SOURCE_COMMIT');
  }
  final output = Directory(args[0]);
  if (await output.exists()) throw StateError('Output already exists');
  await output.create(recursive: true);
  final sink = File('${output.path}/events.jsonl').openWrite();
  final clock = Stopwatch()..start();
  var phase = 'initialize';
  var open = true;
  void record(String kind, Map<String, Object?> data) {
    if (!open) return;
    final row = <String, Object?>{
      'kind': kind,
      'phase': phase,
      'elapsedMs': clock.elapsedMilliseconds,
      ...data,
    };
    sink.writeln(jsonEncode(row));
    stdout.writeln('READALOUD_S11_EXPORT ${jsonEncode(row)}');
  }

  final controller = ReaderController(
    deferInitialSynthesis: true,
    enablePlatformIntakeChannels: false,
  );
  Map<String, Object?> state() => {
    'engine': controller.selectedTtsEngineId,
    'voice': controller.selectedVoice?.id,
    'documentId': controller.document.displayDocument.documentId,
    'words': controller.document.wordCount,
    'completeSnapshot': controller.hasCompleteDocumentSnapshot,
    'resourcesReady': controller.isResourcesReady,
    'bindings': controller.resourceBindings.map((b) => b.toMap()).toList(),
    'status': controller.statusMessage,
  };
  final metrics = PlaybackInstrumentationService.instance;
  metrics.observer = (metric) => record('metric', metric.toMap());
  // The normal app's native delegate owns Quit/child shutdown. A plain status
  // surface avoids a second screen owner independently restoring this profile.
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('S11 Fish export diagnostic')),
    ),
  );
  final receipt = <String, Object?>{
    'schema': 'readaloud-s11-export-diagnostic-v1',
    'sourceCommit': args[3],
    'diagnosticOnly': true,
    'diagnosticCompleted': false,
    'exportSucceeded': false,
    'pid': pid,
    'source': args[2],
    'oldSource': args[1],
  };
  try {
    record('provenance', receipt);
    await controller.initialize();
    if (controller.selectedTtsEngineId != 'fish_drama3_8bit') {
      throw StateError('Diagnostic requires exact Fish 8-bit selection');
    }
    if (args[1] != '-') {
      phase = 'old-source';
      await controller.importFilePaths([args[1]]);
      record('oldImported', state());
    }
    phase = 'initialize-fish';
    await controller.completeInitialIntake();
    if (controller.startupError != null) {
      throw StateError(controller.startupError!);
    }
    if (controller.selectedVoice?.id != 'library_fishadrian') {
      await controller.selectVoiceById('library_fishadrian');
    }
    phase = 'opening-source';
    await controller.importFilePaths([args[2]]);
    // Import returns the first display range; EOF/checkpoint publication is a
    // distinct owner. Match the UI's complete-snapshot Save Audio admission.
    final snapshotDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (!controller.hasCompleteDocumentSnapshot &&
        DateTime.now().isBefore(snapshotDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (!controller.hasCompleteDocumentSnapshot) {
      throw StateError('Opening fixture is not a complete snapshot');
    }
    record('beforeExport', state());
    phase = 'export';
    final result = await controller.exportAudioToPath(
      '${output.path}/fish8-opening-export.wav',
    );
    receipt['exportSucceeded'] = result != null;
    receipt['diagnosticCompleted'] = true;
    receipt['terminalState'] = state();
    if (result != null) {
      receipt['outputPath'] = result.outputPath;
      receipt['sidecarPath'] = result.sidecarPath;
      receipt['chunkCount'] = result.chunkCount;
      receipt['durationMicros'] = result.duration.inMicroseconds;
    }
    record('exportTerminal', receipt);
  } catch (error, stack) {
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
    record('failure', {'error': '$error', 'stack': '$stack', ...state()});
  } finally {
    phase = 'drain';
    try {
      await controller.cancelSpeechResourcePreparation();
      await controller.shutdownPreparation();
      receipt['preparationOwnerDrained'] = true;
    } catch (error, stack) {
      receipt['cleanupError'] = '$error';
      receipt['cleanupStack'] = '$stack';
    }
    record('drained', state());
    controller.dispose();
    metrics.observer = null;
    await sink.flush();
    open = false;
    await sink.close();
    await File('${output.path}/receipt.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt),
      flush: true,
    );
    // The runner requests normal Quit and verifies this app and its child PIDs.
    // No exit(), forced termination or implicit lifecycle pass is used here.
  }
}
