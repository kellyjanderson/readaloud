import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';
import 'package:read_aloud/src/services/modernbooknlp_window.dart';
import 'package:read_aloud/src/services/modernbooknlp_character_adapter.dart';
import 'package:read_aloud/src/services/document_analysis_record.dart';
import 'package:read_aloud/src/services/work_character_store.dart';

void main() {
  final labels = Platform.environment['READALOUD_LITERARY_LABELS'];
  test(
    'frozen literary labels through normal import and actual neural adapter',
    () async {
      final cases = jsonDecode(File(labels!).readAsStringSync()) as List;
      final provider = ModernBookNlpProvider(
        pythonPath:
            Platform.environment['READALOUD_MODERNBOOKNLP_PYTHON'] ??
            '${Directory.current.path}/.venv/bin/python',
        helperPath: '${Directory.current.path}/assets/modernbooknlp_worker.py',
        runtimePath: Platform.environment['READALOUD_MODERNBOOKNLP_ROOT']!,
      );
      addTearDown(provider.close);
      final receipt = <Object>[];
      for (final c in cases) {
        final text = c['text'] as String;
        expect(sha256.convert(utf8.encode(text)).toString(), c['sha256']);
        final doc = DocumentImportService().importPastedText(text);
        final window = ModernBookNlpWindow.at(doc, wordIndex: 0)!;
        final request = ModernBookNlpRequest(
          requestId: c['id'],
          ownerId: 'qualification',
          workId: c['id'],
          sourceRevision: c['sha256'],
          analysisRevision: 1,
          sequence: 1,
          text: window.text,
          windowPolicy: 'paragraph-context-v2',
        );
        final result = await provider.analyze(request);
        final delta = modernBookNlpCharacterDelta(
          request: request,
          result: result,
          registry: doc.characterCastRegistry,
          turns: window.turns,
          sourceSlices: window.slices,
        );
        final owner = WorkCharacterStore()
          ..begin(
            workId: request.workId,
            sourceRevision: request.sourceRevision,
            analysisRevision: 1,
          );
        expect(owner.apply(delta), true);
        final record = DocumentAnalysisRecord.capture(request, result);
        final expected = (c['labels'] as List)
            .map((q) => q['speaker'])
            .toList();
        final names = <String, String?>{};
        for (final d in delta.dialogues) {
          final character = d.castId == null
              ? null
              : owner.character(request.workId, d.castId!);
          // Unnamed entities retain stable identities, but are not invented proper names.
          names[d.dialogueSpanId] =
              character == null || character.observedAliases.isEmpty
              ? null
              : character.displayLabel;
        }
        final neural = [
          for (final o in doc.dialogueAttributions.outcomes)
            names[o.dialogueSpanId],
        ];
        final baseline = [
          for (final o in doc.dialogueAttributions.outcomes)
            doc.characterCastRegistry.characterEntries
                .where((e) => e.attributionIds.contains(o.attributionId))
                .firstOrNull
                ?.displayLabel,
        ];
        receipt.add({
          'id': c['id'],
          'sourceSha256': c['sha256'],
          'expected': expected,
          'baseline': baseline,
          'neural': neural,
          'boundTurns': names.length,
          'quotes': (result['quotes'] as List).length,
          'characters': [
            for (final e in owner.entries(request.workId))
              {
                'name': e.displayLabel,
                'aliases': e.observedAliases,
                'gender': e.inferredGender?.name,
                'evidence': e.characterState.linguisticEvidence.length,
              },
          ],
          'record': record.toJson(),
          'seconds': result['inferenceSeconds'],
          'peakRssBytes': result['peakRssBytes'],
        });
      }
      // Existing blind-audited labels, now beyond a long neutral prefix, force
      // positional windows and reset local model IDs without new answer tuning.
      final rain = cases.singleWhere((c) => c['id'] == 'rain');
      final longDoc = DocumentImportService().importPastedText(
        '${List.filled(200, 'The quiet road wound past the silent houses. Rain fell steadily on the empty fields.').join('\n\n')}\n\n${rain['text']}',
      );
      final crossOwner = WorkCharacterStore()
        ..begin(
          workId: 'cross-window',
          sourceRevision: 'cross-source',
          analysisRevision: 1,
        )
        ..mergeEvidence('cross-window', longDoc.characterCastRegistry);
      crossOwner.select(
        'cross-window',
        'cast_character_beatrice',
        'selected-voice',
      );
      final done = <String>{}, resolved = <String, String?>{};
      var sequence = 0;
      final windows = <Object>[];
      for (final outcome in longDoc.dialogueAttributions.outcomes) {
        final annotation = longDoc.baseSpeechAnnotations.annotations.firstWhere(
          (a) => a.dialogueSpanId == outcome.dialogueSpanId,
        );
        final window = ModernBookNlpWindow.at(
          longDoc,
          wordIndex: longDoc.startWordIndexForSegmentId(annotation.segmentId),
        )!;
        if (!done.add(window.identity)) continue;
        final request = ModernBookNlpRequest(
          requestId: 'cross-${++sequence}',
          ownerId: 'qualification',
          workId: 'cross-window',
          sourceRevision: 'cross-source',
          analysisRevision: 1,
          sequence: sequence,
          text: window.text,
          windowPolicy: 'paragraph-context-v2',
        );
        final result = await provider.analyze(request);
        final delta = modernBookNlpCharacterDelta(
          request: request,
          result: result,
          registry: crossOwner.registry(
            'cross-window',
            documentId: longDoc.displayDocument.documentId,
          ),
          turns: window.turns,
          sourceSlices: window.slices,
        );
        expect(crossOwner.apply(delta), true);
        for (final ref in delta.dialogues.where((r) => r.sourceMatched)) {
          resolved[ref.dialogueSpanId] = ref.castId == null
              ? null
              : crossOwner.character('cross-window', ref.castId!)?.displayLabel;
        }
        windows.add({
          'identity': window.identity,
          'units': window.text.length,
          'seconds': result['inferenceSeconds'],
          'entities': (result['entities'] as List).length,
        });
      }
      expect(done.length, greaterThan(1));
      expect(
        crossOwner
            .character('cross-window', 'cast_character_beatrice')!
            .selectedVoice
            .voiceId,
        'selected-voice',
      );
      receipt.add({
        'id': 'rain-cross-window',
        'windows': windows,
        'neural': [
          for (final o in longDoc.dialogueAttributions.outcomes)
            resolved[o.dialogueSpanId],
        ],
        'expected': [for (final q in rain['labels']) q['speaker']],
        'selectedVoicePreserved': true,
      });
      final output = Platform.environment['READALOUD_LITERARY_RECEIPT'];
      if (output != null) {
        File(output).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(receipt),
        );
      }
      for (final row in receipt.cast<Map<String, Object?>>()) {
        expect(
          row['neural'],
          row['expected'],
          reason: '${row['id']} actual app window',
        );
      }
      final pid = provider.processId;
      await provider.close();
      expect(
        (await Process.run('/bin/kill', ['-0', '$pid'])).exitCode,
        isNot(0),
      );
    },
    skip: labels == null
        ? 'Requires frozen private labels and installed offline CPU runtime'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
