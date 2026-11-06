// Native persistence probe. Runs real CPU inference, with silent speech only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/screens/read_aloud_screen.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/modernbooknlp_analysis.dart';
import 'package:read_aloud/src/services/reader_document_repository.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/work_character_repository.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  if (!support.path.contains('residentNlpTest') ||
      (args.length != 1 && args.length != 2)) {
    throw StateError(
      'Use isolated residentNlpTest sandbox and fresh receipt path',
    );
  }
  final run = Directory(
    '${support.path}/persistence-${DateTime.now().microsecondsSinceEpoch}',
  );
  await run.create();
  ReaderController reader(String profile, {ModernBookNlpAnalysis? analysis}) =>
      ReaderController(
        ttsEngine: _SilentEngine(),
        enablePlatformIntakeChannels: false,
        documentRepository: ReaderDocumentRepository(
          '${run.path}/$profile/documents',
        ),
        preferencesService: _ProbePreferences(
          workRepository: WorkCharacterRepository('${run.path}/$profile/works'),
        ),
        characterAnalysis: analysis,
      );
  var restartAttempts = 0;
  final restartAnalysis = args.length == 2
      ? ModernBookNlpAnalysis(() async {
          restartAttempts++;
          throw StateError('Relaunch must reuse the portable evidence');
        })
      : null;
  var controller = reader('first', analysis: restartAnalysis);
  runApp(
    MaterialApp(
      home: ReadAloudScreen(key: UniqueKey(), controller: controller),
    ),
  );
  final receipt = <String, Object?>{'passed': false, 'run': run.path};
  Future<void> waitFor(bool Function() ready) async {
    final end = DateTime.now().add(const Duration(seconds: 120));
    while (!ready()) {
      if (DateTime.now().isAfter(end)) {
        throw TimeoutException('Native persistence condition');
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> analysisDone(int count) async {
    await waitFor(
      () =>
          controller.characterAnalysis.completedWindows >= count ||
          controller.characterAnalysis.error != null,
    );
    if (controller.characterAnalysis.error != null) {
      throw StateError(controller.characterAnalysis.error!);
    }
    await waitFor(() => !controller.characterAnalysis.busy);
  }

  const story =
      'Ada opened the gate. She smiled. "Come inside," Ada said. Bruno smiled. "Thank you," Bruno replied. Matilde waved.';
  try {
    await WidgetsBinding.instance.endOfFrame;
    await waitFor(() => !controller.isInitializing);
    if (args.length == 2) {
      await controller.importFilePaths([args[1]]);
      controller.characterAnalysis.enable();
      await analysisDone(1);
      if (!controller.characterAnalysis.restoredFromBook ||
          restartAttempts != 0 ||
          controller.document.characterCastRegistry
                  .forCastId('cast_narrator')
                  ?.selectedVoice
                  .voiceId !=
              'test') {
        throw StateError(
          'Relaunch did not restore evidence and selected voice',
        );
      }
      receipt.addAll({
        'passed': true,
        'relaunched': true,
        'freshProviderAttempts': restartAttempts,
        'voicePreserved': true,
        'portableReuse': controller.characterAnalysis.result,
      });
      await File(args.first).writeAsString(jsonEncode(receipt), flush: true);
      return;
    }
    await controller.importPastedText(story);
    final before = controller.document.dialogueAttributions;
    controller.characterAnalysis.enable();
    await analysisDone(1);
    final first = controller.characterAnalysis.result!;
    receipt['first'] = first;
    if (first['linguisticArtifacts'] == null) {
      throw StateError('Missing computed linguistic outputs');
    }
    if (!identical(before, controller.document.dialogueAttributions)) {
      throw StateError('Diagnostic result altered attribution');
    }
    final ada = controller.characterCastRegistry.characterEntries.singleWhere(
      (e) => e.displayLabel == 'Ada',
    );
    if (ada.characterState.linguisticEvidence.isEmpty ||
        ada.inferredGender != VoiceGender.female ||
        !controller.characterCastRegistry.characterEntries.any(
          (e) => e.displayLabel == 'Matilde',
        )) {
      throw StateError(
        'Typed evidence, singleton or pronoun integration failed',
      );
    }
    await controller.assignVoiceToCast(ada.castId, 'test');
    receipt['adaId'] = ada.castId;
    await controller.assignVoiceToCast('cast_narrator', 'test');
    await controller.importPastedText('"I will return tomorrow," Miriam said.');
    await analysisDone(2);
    receipt['second'] = controller.characterAnalysis.result;
    await controller.importPastedText(story);
    await analysisDone(3);
    if (!controller.characterAnalysis.restoredFromBook) {
      throw StateError('A B A did not reuse saved work');
    }
    receipt['switchReuse'] = controller.characterAnalysis.result;
    final portable = '${run.path}/portable.radoc';
    if (await controller.exportDocumentToPath(portable) == null) {
      throw StateError('Book export failed: ${controller.statusMessage}');
    }
    final exported = const ReaderDocumentSerializationService()
        .deserializeFromJsonString(await File(portable).readAsString());
    if (exported.analysisRecords.isEmpty) {
      throw StateError('Export lost analysis');
    }
    await controller.shutdownPreparation();
    runApp(const MaterialApp(home: SizedBox()));
    await WidgetsBinding.instance.endOfFrame;
    controller.dispose();
    var attempts = 0;
    final cached = ModernBookNlpAnalysis(() async {
      attempts++;
      throw StateError('Fresh profile must not need a model');
    });
    controller = reader('fresh', analysis: cached);
    runApp(
      MaterialApp(
        home: ReadAloudScreen(key: UniqueKey(), controller: controller),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    await waitFor(() => !controller.isInitializing);
    await controller.importFilePaths([portable]);
    controller.characterAnalysis.enable();
    await analysisDone(1);
    if (!cached.restoredFromBook || attempts != 0) {
      throw StateError('Portable reopen started a model');
    }
    final copy = '${run.path}/copied.radoc';
    if (await controller.exportDocumentToPath(copy) == null) {
      throw StateError('Re-export failed');
    }
    final roundtrip = const ReaderDocumentSerializationService()
        .deserializeFromJsonString(await File(copy).readAsString());
    final narrator = roundtrip.characterCastRegistry.entries.singleWhere(
      (e) => e.castId == 'cast_narrator',
    );
    if (narrator.selectedVoice.voiceId != 'test') {
      throw StateError('Portable explicit voice lost');
    }
    final restoredAda = roundtrip.characterCastRegistry.forCastId(ada.castId);
    if (restoredAda?.selectedVoice.voiceId != 'test' ||
        restoredAda!.characterState.linguisticEvidence.isEmpty ||
        restoredAda.inferredGender != VoiceGender.female) {
      throw StateError('Portable Character evidence/selection lost');
    }
    receipt.addAll({
      'passed': true,
      'portableRecords': roundtrip.analysisRecords.length,
      'freshProviderAttempts': attempts,
      'portableReuse': cached.result,
      'voicePreserved': true,
      'attributionUnchanged': true,
      'characterEvidencePreserved': true,
      'singletonPreserved': true,
    });
  } catch (error, stack) {
    receipt.addAll({'error': '$error', 'stack': '$stack'});
  }
  await File(args.first).writeAsString(
    const JsonEncoder.withIndent('  ').convert(receipt),
    flush: true,
  );
  // The external runner must send normal Quit and verify app/child exit.
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

// Each probe owns its launch document. Retain real per-work persistence while
// excluding shared QA-shell auto-resume preferences from an earlier test run.
class _ProbePreferences extends ReaderPreferencesService {
  _ProbePreferences({required super.workRepository});
  @override
  Future<ReaderPreferences> load() async {
    final stored = await super.load();
    return ReaderPreferences(
      fontFamily: stored.fontFamily,
      fontScale: stored.fontScale,
      appearanceMode: stored.appearanceMode,
      multiVoiceEnabled: stored.multiVoiceEnabled,
      voiceSpeeds: stored.voiceSpeeds,
      storedDocumentCastVoiceAssignments:
          stored.storedDocumentCastVoiceAssignments,
      characterSnapshot: stored.characterSnapshot,
      sourceVoiceDocumentIds: stored.sourceVoiceDocumentIds,
    );
  }
}
