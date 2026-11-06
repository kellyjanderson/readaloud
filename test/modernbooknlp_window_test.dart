import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/document_analysis_record.dart';
import 'package:read_aloud/src/services/modernbooknlp_analysis.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';
import 'package:read_aloud/src/services/modernbooknlp_window.dart';
import 'package:read_aloud/src/services/modernbooknlp_character_adapter.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'VS38 oversized segments keep contiguous Unicode source and refuse partial turns',
    () {
      final doc = DocumentImportService().importPastedText(
        'Before paragraph.\n\n"${List.filled(4000, '🌙 word').join(' ')}"\n\nAfter paragraph.',
      );
      final window = ModernBookNlpWindow.at(doc, wordIndex: 3000)!;
      expect(window.text.length, lessThanOrEqualTo(16384));
      expect(window.slices, hasLength(1));
      final slice = window.slices.single;
      expect(slice.start, greaterThan(0));
      expect(
        window.text,
        slice.segment.normalizedText.substring(slice.start, slice.end),
      );
      expect(
        window.text.codeUnitAt(0),
        isNot(inInclusiveRange(0xdc00, 0xdfff)),
      );
      expect(window.turns, isEmpty);
      expect(window.coversPosition(doc, 3000), true);
      expect(window.coversPosition(doc, 7000), false);
      final later = ModernBookNlpWindow.at(doc, wordIndex: 7000)!;
      expect(later.coversPosition(doc, 7000), true);
      expect(later.identity, isNot(window.identity));
    },
  );
  test(
    'VS34 actual public evidence retains paragraphs, aliases and exact dialogue bindings',
    () {
      final doc = DocumentImportService().importPastedText(
        File('test/fixtures/rc2_prose/text/rain.txt').readAsStringSync(),
      );
      final saved = DocumentAnalysisRecord.fromJson(
        jsonDecode(
          File(
            'test/fixtures/modernbooknlp/rain-record.json',
          ).readAsStringSync(),
        ),
      );
      final window = ModernBookNlpWindow.at(doc, wordIndex: 0)!;
      expect(window.text, saved.text);
      final request = ModernBookNlpRequest(
        requestId: 'r',
        ownerId: 'o',
        workId: 'w',
        sourceRevision: saved.sourceRevision,
        analysisRevision: 1,
        sequence: 1,
        text: window.text,
        windowPolicy: 'paragraph-context-v2',
      );
      final delta = modernBookNlpCharacterDelta(
        request: request,
        result: saved.forRequest(request),
        registry: doc.characterCastRegistry,
        turns: window.turns,
        sourceSlices: window.slices,
      );
      expect(delta.dialogues.every((d) => d.sourceMatched), true);
      expect(
        delta.dialogues.map((d) => d.dialogueSpanId).toSet(),
        hasLength(11),
      );
      expect(
        delta.registry.characterEntries.where((e) => e.displayLabel == 'Bea'),
        isEmpty,
      );
      expect(
        delta.registry.characterEntries.any((e) => e.displayLabel == 'Ada'),
        true,
      ); // Singleton.
      final copied = const ReaderDocumentSerializationService()
          .deserializeFromJsonString(
            const ReaderDocumentSerializationService().serializeToJsonString(
              doc,
              analysisRecords: [saved],
              characters: delta.registry,
            ),
          );
      expect(copied.analysisRecords.single.key, saved.key);
      expect(
        copied.characterCastRegistry.characterEntries
            .where((e) => e.displayLabel == 'Beatrice')
            .single
            .characterState
            .linguisticEvidence,
        isNotEmpty,
      );
    },
  );

  test(
    'VS35 bounded positional windows and portable A/B/A reuse never start a provider',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'nlp-window-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final doc = DocumentImportService().importPastedText(
        [
          for (var i = 0; i < 200; i++)
            'Section $i. The river moved slowly beneath the bridge while the rain covered the village. The lamp still glowed in the window.',
        ].join('\n\n'),
      );
      final first = ModernBookNlpWindow.at(doc, wordIndex: 0)!;
      final last = ModernBookNlpWindow.at(doc, wordIndex: doc.wordCount - 1)!;
      expect(first.text.length, lessThanOrEqualTo(16384));
      expect(last.text.length, lessThanOrEqualTo(16384));
      expect(first.identity, isNot(last.identity));
      expect(
        last.targetSegmentIds,
        contains(doc.speechDocument.segments.last.segmentId),
      );
      DocumentAnalysisRecord record(ModernBookNlpWindow window, int sequence) {
        final request = ModernBookNlpRequest(
          requestId: 'r$sequence',
          ownerId: 'o',
          workId: 'w',
          sourceRevision: 'source',
          analysisRevision: 1,
          sequence: sequence,
          text: window.text,
          windowPolicy: 'paragraph-context-v2',
        );
        return DocumentAnalysisRecord.capture(request, {
          ...request.toJson(),
          'ok': true,
          'providerId': 'modernbooknlp-joint',
          'providerVersion': modernBookNlpRevision,
          'modelIdentity': modernBookNlpModelIdentity,
          'adapterVersion': modernBookNlpAdapterVersion,
          'tokenCount': 0,
          'entities': [],
          'quotes': [],
          'linguisticArtifacts': {
            'schema': 1,
            'pipeline': 'entity,quote,coref',
            'coordinateSystem': 'python-codepoint',
            'files': {
              'tokens':
                  'token_ID_within_document\tword\tbyte_onset\tbyte_offset\n',
              'entities': 'COREF\tstart_token\tend_token\tprop\tcat\ttext\n',
              'quotes': 'quote_start\tquote_end\tchar_id\n',
              'book': '{"characters":[]}',
            },
          },
        });
      }

      final file = File('${directory.path}/book.radoc');
      await file.writeAsString(
        const ReaderDocumentSerializationService().serializeToJsonString(
          doc,
          analysisRecords: [record(first, 1), record(last, 2)],
        ),
      );
      var starts = 0;
      final analysis = ModernBookNlpAnalysis(() async {
        starts++;
        throw StateError('Saved coverage must precede provider creation');
      });
      final controller = ReaderController(
        characterAnalysis: analysis,
        importer: DocumentImportService(),
        ttsEngine: _Engine(),
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        await controller.shutdownPreparation();
        controller.dispose();
      });
      await controller.initialize();
      await controller.importFilePaths([file.path]);
      expect(controller.document.analysisRecords, hasLength(2));
      Future<void> completed(int count) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while ((analysis.busy || analysis.completedWindows < count) &&
            analysis.error == null &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(analysis.error, isNull);
        expect(analysis.completedWindows, count);
        expect(analysis.restoredFromBook, true);
      }

      analysis.enable();
      await completed(1);
      await controller.jumpBySeconds(100000);
      await completed(2);
      expect(analysis.result!['sequence'], greaterThan(0));
      await controller.jumpBySeconds(-100000);
      await completed(3);
      expect(starts, 0);
    },
  );
}

class _Engine implements TtsEngine {
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
