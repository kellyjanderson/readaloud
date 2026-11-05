import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/document_analysis_record.dart';
import 'package:read_aloud/src/services/document_analysis_repository.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/modernbooknlp_analysis.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';
import 'package:read_aloud/src/services/work_character_store.dart';

ModernBookNlpRequest request(
  String source, {
  String text = 'Ada smiled.',
  int generation = 1,
}) => ModernBookNlpRequest(
  requestId: '$source-$generation',
  ownerId: 'owner-$generation',
  workId: source,
  sourceRevision: source,
  analysisRevision: generation,
  sequence: 0,
  text: text,
);
Map<String, dynamic> output(ModernBookNlpRequest r) => {
  ...r.toJson(),
  'ok': true,
  'providerId': 'modernbooknlp-joint',
  'providerVersion': modernBookNlpRevision,
  'modelIdentity': modernBookNlpModelIdentity,
  'adapterVersion': modernBookNlpAdapterVersion,
  'tokenCount': 3,
  'entities': [],
  'quotes': [],
  'processId': 999,
  'linguisticArtifacts': {
    'schema': 1,
    'pipeline': 'entity,quote,coref',
    'coordinateSystem': 'python-codepoint',
    'files': {
      'tokens': 'token rows',
      'entities': 'all categories',
      'quotes': 'quote rows',
      'book': '{"characters": []}',
    },
  },
};
Future<void> settled(ModernBookNlpAnalysis owner) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (owner.busy && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(owner.busy, false);
  expect(owner.error, isNull);
}

class Provider extends ModernBookNlpProvider {
  Provider() : super(pythonPath: '', helperPath: '', runtimePath: '');
  int calls = 0;
  Completer<Map<String, dynamic>>? held;
  @override
  Future<void> prepare({
    bool offline = false,
    void Function(Map<String, dynamic>)? onProgress,
  }) async {}
  @override
  Future<Map<String, dynamic>> analyze(
    ModernBookNlpRequest r, {
    void Function(Map<String, dynamic>)? onProgress,
  }) async {
    calls++;
    return held == null ? output(r) : held!.future;
  }
}

void main() {
  late Directory dir;
  late DocumentAnalysisRepository store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('radoc-analysis-test-');
    store = DocumentAnalysisRepository(dir.path);
  });
  tearDown(() => dir.delete(recursive: true));
  test(
    'exact scope reuse rebinds session IDs; text/source/dependencies invalidate',
    () async {
      final a = request('a');
      await store.save(a, output(a), isCurrent: () => true);
      final saved = (await store.read(request('a', generation: 2)))!;
      final reused = saved.forRequest(request('a', generation: 2));
      expect(reused['ownerId'], 'owner-2');
      expect(reused.containsKey('processId'), false);
      expect(reused['linguisticArtifacts'], output(a)['linguisticArtifacts']);
      expect(await store.read(request('b')), isNull);
      expect(await store.read(request('a', text: 'Ada laughed.')), isNull);
      final old = DocumentAnalysisRecord.fromJson({
        ...saved.toJson(),
        'adapterVersion': 'old',
      });
      expect(old.reusable, false);
      expect(() => old.forRequest(a), throwsFormatException);
      final stale = {...output(a), 'ownerId': 'obsolete'};
      await expectLater(
        store.save(a, stale, isCurrent: () => true),
        throwsFormatException,
      );
    },
  );
  test(
    'cancelled publication and malformed input leave writer reusable',
    () async {
      final a = request('a');
      await expectLater(
        store.save(a, output(a), isCurrent: () => false),
        throwsA(isA<ModernBookNlpCancelled>()),
      );
      expect(await File(store.pathFor(a)).exists(), false);
      expect(
        (await dir.list(recursive: true).toList()).whereType<File>(),
        isEmpty,
      );
      await store.save(a, output(a), isCurrent: () => true);
      await File(store.pathFor(a)).writeAsString('{"payload": 4}');
      await expectLater(store.read(a), throwsFormatException);
      await store.save(a, output(a), isCurrent: () => true);
      final envelope =
          jsonDecode(await File(store.pathFor(a)).readAsString()) as Map;
      envelope['sha256'] = 'damaged';
      await File(store.pathFor(a)).writeAsString(jsonEncode(envelope));
      await expectLater(store.read(a), throwsFormatException);
    },
  );
  test(
    'A B A and a fresh owner reuse saved results before creating any provider',
    () async {
      final provider = Provider();
      final owner = ModernBookNlpAnalysis(() async => provider)
        ..repository = store;
      addTearDown(owner.shutdown);
      owner.offer(request('a'));
      owner.enable();
      await settled(owner);
      owner.invalidateWindow();
      owner.offer(request('b'));
      await settled(owner);
      owner.invalidateWindow();
      owner.offer(request('a', generation: 3));
      await settled(owner);
      expect(provider.calls, 2);
      expect(owner.restoredFromBook, true);
      final restart = ModernBookNlpAnalysis(
        () async => throw StateError('must not load'),
      )..repository = store;
      addTearDown(restart.shutdown);
      restart.offer(request('a', generation: 7));
      restart.enable();
      await settled(restart);
      expect(restart.restoredFromBook, true);
      expect(restart.result!['analysisRevision'], 7);
    },
  );
  test('late obsolete result cannot be saved or published', () async {
    final provider = Provider()..held = Completer<Map<String, dynamic>>();
    final owner = ModernBookNlpAnalysis(() async => provider)
      ..repository = store;
    addTearDown(owner.shutdown);
    final a = request('a');
    owner.offer(a);
    owner.enable();
    while (provider.calls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    owner.invalidateWindow();
    provider.held!.complete(output(a));
    await settled(owner);
    expect(owner.result, isNull);
    expect(await store.read(a), isNull);
  });
  test(
    'portable v4 retains linguistic artifacts, voice intent and legacy decoding',
    () async {
      const codec = ReaderDocumentSerializationService();
      final doc = DocumentImportService().importPastedText('Ada smiled.');
      final text = doc.speechDocument.segments
          .map((s) => s.normalizedText)
          .join('\n');
      final a = request('a', text: text);
      final record = await store.save(a, output(a), isCurrent: () => true);
      final characters = WorkCharacterStore()
        ..mergeEvidence('a', doc.characterCastRegistry)
        ..select('a', 'cast_narrator', 'mature-voice');
      final path = '${dir.path}/book.radoc';
      await codec.writeToFile(
        document: doc,
        outputPath: path,
        analysisRecords: [record],
        characters: characters.registry(
          'a',
          documentId: doc.characterCastRegistry.documentId,
        ),
      );
      final reopened = codec.deserializeFromJsonString(
        await File(path).readAsString(),
      );
      expect(reopened.analysisRecords.single.outputJson, record.outputJson);
      final choices = WorkCharacterStore()
        ..restoreDocument('portable', reopened.characterCastRegistry);
      expect(
        choices.character('portable', 'cast_narrator')!.selectedVoice.voiceId,
        'mature-voice',
      );
      final fresh = ModernBookNlpAnalysis(
        () async => throw StateError('no models in this profile'),
      );
      addTearDown(fresh.shutdown);
      fresh.restoreRecords(reopened.analysisRecords);
      fresh.offer(request('a', text: text, generation: 22));
      fresh.enable();
      await settled(fresh);
      expect(fresh.restoredFromBook, true);
      final envelope =
          jsonDecode(codec.serializeToJsonString(doc)) as Map<String, dynamic>;
      for (final version in ['radoc-v1', 'radoc-v2', 'radoc-v3']) {
        envelope['formatVersion'] = version;
        envelope.remove('analysisRecords');
        expect(
          codec.deserializeFromJsonString(jsonEncode(envelope)).analysisRecords,
          isEmpty,
        );
      }
      final bad = DocumentAnalysisRecord.capture(
        request('x', text: 'Unrelated book.'),
        output(request('x', text: 'Unrelated book.')),
      );
      expect(
        () => codec.deserializeFromJsonString(
          codec.serializeToJsonString(doc, analysisRecords: [bad]),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'damaged cache is recomputed; malformed evidence cannot be admitted',
    () async {
      final a = request('a');
      await store.save(a, output(a), isCurrent: () => true);
      await File(store.pathFor(a)).writeAsString('broken');
      final p = Provider();
      final owner = ModernBookNlpAnalysis(() async => p)..repository = store;
      addTearDown(owner.shutdown);
      owner.offer(a);
      owner.enable();
      await settled(owner);
      expect(p.calls, 1);
      expect(await store.read(a), isNotNull);
      final record = (await store.read(a))!;
      expect(
        () =>
            DocumentAnalysisRecord.fromJson({...record.toJson(), 'output': 3}),
        throwsFormatException,
      );
      expect(
        () => DocumentAnalysisRecord.fromJson({
          ...record.toJson(),
          'textSha256': 'wrong',
        }),
        throwsFormatException,
      );
      expect(
        () => DocumentAnalysisRecord.fromJson({
          ...record.toJson(),
          'output': {
            ...jsonDecode(record.outputJson) as Map<String, dynamic>,
            'ownerId': 'injected',
          },
        }),
        throwsFormatException,
      );
      final invalid = {
        ...output(a),
        'entities': [
          {
            'entityId': '1',
            'mentions': [
              {'startUtf16': 0, 'endUtf16': 999, 'text': 'Ada'},
            ],
          },
        ],
      };
      expect(
        () => DocumentAnalysisRecord.capture(a, invalid),
        throwsFormatException,
      );
    },
  );
}
