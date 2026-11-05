// Run only in the independently signed characterStorageTest sandbox.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:read_aloud/src/models/reader_appearance_mode.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/work_character_store.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 1) throw ArgumentError('One receipt path required');
  final status = ValueNotifier<String>('Checking per-document storage');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, text, _) => Text(text),
          ),
        ),
      ),
    ),
  );
  final receipt = <String, Object?>{'passed': false};
  try {
    final support = await getApplicationSupportDirectory();
    if (!support.path.contains('characterStorageTest')) {
      throw StateError(
        'Refusing to change preferences outside the storage-test sandbox',
      );
    }
    final root = Directory(p.join(support.path, 'works'));
    if (await root.exists()) {
      throw StateError('Use a fresh storage-test sandbox');
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = WorkCharacterStore()
      ..select('test-rosalina', 'test-character', 'voice-a')
      ..select('test-city', 'test-character', 'voice-b');
    await prefs.setString(
      'reader.workCharacters.v1',
      jsonEncode(legacy.toJson()),
    );
    await prefs.setString(
      'reader.sourceVoiceDocumentIds',
      jsonEncode({'source-a': 'test-rosalina', 'source-b': 'test-city'}),
    );
    await prefs.setString('reader.ttsEngineId', 'fish_drama3');
    final service = ReaderPreferencesService();
    final loaded = await service.load();
    final owner = loaded.characterSnapshot!.restore();
    if (owner
                .character('test-rosalina', 'test-character')!
                .selectedVoice
                .voiceId !=
            'voice-a' ||
        prefs.containsKey('reader.workCharacters.v1')) {
      throw StateError('Migration failed');
    }
    status.value = 'Migration passed; checking independent reset';
    owner.select('test-city', 'test-character', null);
    await service.save(
      fontFamily: 'serif',
      fontScale: 1,
      appearanceMode: ReaderAppearanceMode.system,
      multiVoiceEnabled: true,
      voiceSpeeds: {},
      storedDocumentCastVoiceAssignments: {},
      characterSnapshot: owner.snapshot(),
      sourceVoiceDocumentIds: loaded.sourceVoiceDocumentIds,
      ttsEngineId: 'fish_drama3',
    );
    File file(String id) => File(
      p.join(
        root.path,
        sha256.convert(utf8.encode(id)).toString(),
        'characters.json',
      ),
    );
    final cityBefore = await file('test-city').readAsString();
    await file('test-rosalina').delete();
    final reopened = await ReaderPreferencesService().load();
    if (reopened.characterSnapshot!
            .restore()
            .entries('test-rosalina')
            .isNotEmpty ||
        reopened.characterSnapshot!
                .restore()
                .character('test-city', 'test-character')!
                .selectedVoice
                .revision !=
            2 ||
        await file('test-city').readAsString() != cityBefore ||
        reopened.ttsEngineId != 'fish_drama3') {
      throw StateError('Reset isolation failed');
    }
    receipt.addAll({
      'passed': true,
      'applicationSupport': support.path,
      'legacyKeysRemoved': !prefs.containsKey('reader.sourceVoiceDocumentIds'),
      'separateWorkFiles': true,
      'resetSurvivedReopen': true,
      'otherWorkUnchanged': true,
      'enginePreserved': true,
    });
    status.value = 'Storage checks passed';
  } catch (error, stack) {
    receipt.addAll({'error': '$error', 'stack': '$stack'});
    status.value = 'Storage check failed: $error';
  }
  final output = File(args.single);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert(receipt),
    flush: true,
  );
  // Supervisor requests normal Quit and verifies process exit after the receipt.
}
