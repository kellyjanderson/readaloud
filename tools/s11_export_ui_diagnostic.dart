// Ordinary app UI plus a bounded export-only observer. The screen exclusively
// owns initialization, restore/import, FilePicker export and normal UI actions.
// Build as a separate QA bundle; never replace the ordinary acceptance build.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 2) throw ArgumentError('NEW_OUTPUT SOURCE_COMMIT');
  if (Platform.environment['READALOUD_TTS_ENGINE'] != 'fish_drama3_8bit') {
    throw StateError('UI diagnostic requires explicit Fish 8-bit environment');
  }
  final output = Directory(args[0]);
  if (await output.exists()) throw StateError('Preserve existing diagnostics');
  await output.create(recursive: true);
  final sink = File('${output.path}/events.jsonl').openWrite();
  final clock = Stopwatch()..start();
  var records = 0;
  void record(String kind, Map<String, Object?> data) {
    if (records >= 100) return;
    records++;
    final row = <String, Object?>{
      'kind': kind,
      'elapsedMs': clock.elapsedMilliseconds,
      ...data,
    };
    sink.writeln(jsonEncode(row));
    stdout.writeln('READALOUD_S11_EXPORT_UI ${jsonEncode(row)}');
  }

  final controller = ReaderController(deferInitialSynthesis: true);
  Map<String, Object?> state() => {
    'engine': controller.selectedTtsEngineId,
    'voice': controller.selectedVoice?.id,
    'documentId': controller.document.displayDocument.documentId,
    'words': controller.document.wordCount,
    'completeSnapshot': controller.hasCompleteDocumentSnapshot,
    'resourcesReady': controller.isResourcesReady,
    'bindings': controller.resourceBindings.map((b) => b.toMap()).toList(),
    'status': controller.statusMessage,
    'exporting': controller.isExporting,
  };
  var exporting = false;
  controller.addListener(() {
    if (exporting == controller.isExporting) return;
    exporting = controller.isExporting;
    record(exporting ? 'exportStarted' : 'exportTerminal', state());
    // Only start/terminal transitions can flush, with at most one export active.
    unawaited(sink.flush());
  });
  PlaybackInstrumentationService.instance.observer = (metric) {
    if (metric.metric == 'audioExportFailed' ||
        metric.metric == 'exportChunkReady') {
      record('metric', metric.toMap());
    }
  };
  record('provenance', {
    'schema': 'readaloud-s11-export-ui-diagnostic-v1',
    'diagnosticOnly': true,
    'sourceCommit': args[1],
    'pid': pid,
    'scope': 'Ordinary UI export with observer; root owns CUA and normal Quit',
    'eventLimit': 100,
  });
  await sink.flush();
  runApp(ReadAloudApp(controller: controller));
}
