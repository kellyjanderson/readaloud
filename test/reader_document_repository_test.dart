import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/document_preparation_supervisor.dart';
import 'package:read_aloud/src/services/reader_document_repository.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';

DocumentPreparationRequest request(
  int revision, {
  String source = 'source-v1',
  String text = 'John said, "Hello."',
}) => DocumentPreparationRequest(
  ownerId: 'reader',
  revision: revision,
  kind: DocumentPreparationKind.pastedText,
  text: text,
  sourceRevision: source,
  watchSession: 5,
);

DocumentPreparationPublication publication(
  DocumentPreparationRequest q, {
  int sequence = 1,
  int sourceStart = 0,
  int wordStart = 0,
  int segmentStart = 0,
}) {
  final document = DocumentImportService().importPastedText(q.text!);
  return DocumentPreparationPublication(
    request: q.identityOnly,
    sequence: sequence,
    range: PreparedDocumentRange(
      sourceStart: sourceStart,
      sourceEnd: sourceStart + q.text!.length,
      wordStart: wordStart,
      wordEnd: wordStart + document.wordCount,
      segmentStart: segmentStart,
      segmentEnd: segmentStart + document.speechDocument.segments.length,
    ),
    fragment: document,
    coverage: const {
      PreparationStage.normalization,
      PreparationStage.mapping,
      PreparationStage.analysis,
      PreparationStage.pronunciation,
    },
    progress: const [],
    isLast: false,
  );
}

void main() {
  late Directory directory;
  late ReaderDocumentRepository repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('radoc-repository-');
    repository = ReaderDocumentRepository(directory.path);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'round trip retains evidence, redirect, counted IDs and explicit intent',
    () {
      const codec = ReaderDocumentSerializationService();
      final doc = DocumentImportService().importPastedText(
        'John said, "Hello." He smiled.',
      );
      final map =
          jsonDecode(codec.serializeToJsonString(doc)) as Map<String, dynamic>;
      final annotations = map['baseSpeechAnnotations']['annotations'] as List;
      final segment = doc.speechDocument.segments.first.segmentId;
      annotations.addAll([
        {
          'annotationId': 'direction',
          'segmentId': segment,
          'kind': 'deliveryIntent',
          'startWord': 0,
          'endWord': 1,
          'confidence': 1.0,
          'source': 'userOverride',
          'deliveryIntent': 'whispered',
        },
        {
          'annotationId': 'inflection',
          'segmentId': segment,
          'kind': 'inflectionIntent',
          'startWord': 0,
          'endWord': 1,
          'confidence': 1.0,
          'source': 'explicitSourceMetadata',
          'inflectionIntent': 'rising',
        },
      ]);
      final cast = map['characterCastRegistry'] as Map;
      cast['castIdRedirects'] = {'old-john': 'cast_character_john'};
      final entry = (cast['entries'] as List).cast<Map>().firstWhere(
        (e) => e['roleKind'] == 'character',
      );
      entry['observedAliases'] = ['John', 'Mr John'];
      entry['identityProfile'] = {
        'genderIdentityLabel': 'trans_male',
        'genderConfidence': 0.9,
        'genderSource': 'explicit_identity',
        'pronounProfile': {
          'counts': {'he': 50},
        },
        'conflictFlag': true,
        'countedSegmentIds': ['r0_s_0', 'r8192_s_0'],
        'evidenceSpans': [
          {
            'segmentId': segment,
            'startUtf16': 0,
            'endUtf16': 4,
            'text': 'John',
            'source': 'explicit_identity',
            'genderIdentityLabel': 'trans_male',
          },
        ],
      };
      entry['inferredGender'] = 'male';
      entry['inferredGenderConfidence'] = 0.9;
      final restored = codec.deserializeFromJsonString(jsonEncode(map));
      final second = jsonDecode(codec.serializeToJsonString(restored)) as Map;
      expect(second['characterCastRegistry'], map['characterCastRegistry']);
      expect(
        second['baseSpeechAnnotations']['annotations'].last['inflectionIntent'],
        'rising',
      );
      expect(restored.displayHtml, doc.displayHtml);
      expect(restored.speakableText, doc.speakableText);
      expect(second['positionMap'], map['positionMap']);
      expect(
        second['basePronunciationArtifacts'],
        map['basePronunciationArtifacts'],
      );
      expect(
        () => restored.speechDocument.segments.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('v1 compatibility and future or mixed identity schema rejection', () {
    const codec = ReaderDocumentSerializationService();
    final m =
        jsonDecode(
              codec.serializeToJsonString(publication(request(1)).fragment),
            )
            as Map<String, dynamic>;
    m['formatVersion'] = 'radoc-v1';
    expect(
      codec.deserializeFromJsonString(jsonEncode(m)).wordCount,
      greaterThan(0),
    );
    m['formatVersion'] = 'radoc-v99';
    expect(
      () => codec.deserializeFromJsonString(jsonEncode(m)),
      throwsFormatException,
    );
    m['formatVersion'] = 'radoc-v2';
    m['speechDocument']['documentId'] = 'another-book';
    expect(
      () => codec.deserializeFromJsonString(jsonEncode(m)),
      throwsFormatException,
    );
  });

  test(
    'partial checkpoints remain partial; complete manifest rebinds request',
    () async {
      final q = request(1);
      final writer = await repository.begin(sourceKey: 'book', request: q);
      await writer.commit(publication(q));
      final partial = await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      );
      expect(partial!.isComplete, isFalse);
      expect((await partial.readRange(1, request: request(2))).isLast, isFalse);
      await writer.complete();
      final cache = await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      );
      final range = await cache!.readRange(1, request: request(2));
      expect(cache.isComplete, isTrue);
      expect(range.request.revision, 2);
      expect(range.request.text, isNull);
      expect(range.isLast, isTrue);
      expect(
        range.fragment.speakableText,
        publication(q).fragment.speakableText,
      );
      await expectLater(cache.readRange(2, request: q), throwsRangeError);
    },
  );

  test(
    'source and dependency versions invalidate; corruption is an error',
    () async {
      final writer = await repository.begin(
        sourceKey: 'book',
        request: request(1),
      );
      await writer.commit(publication(request(1)));
      await writer.complete();
      expect(
        await repository.open(sourceKey: 'book', sourceRevision: 'source-v2'),
        isNull,
      );
      expect(
        await repository.open(
          sourceKey: 'book',
          sourceRevision: 'source-v1',
          dependencies: 'new-analysis',
        ),
        isNull,
      );
      final cache = (await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      ))!;
      await File(
        '${cache.path}/1.json',
      ).writeAsString('{"payload":"truncated"}');
      await expectLater(
        cache.readRange(1, request: request(1)),
        throwsFormatException,
      );
      await File(
        '${directory.path}/${cache.path.split('/').reversed.skip(1).first}/manifest.json',
      ).writeAsString('{');
      expect(
        await repository.open(sourceKey: 'book', sourceRevision: 'source-v1'),
        isNull,
      );
    },
  );

  test(
    'replacement/cancel/noncontiguous writes cannot publish a manifest',
    () async {
      final old = await repository.begin(
        sourceKey: 'book',
        request: request(1),
      );
      final latest = await repository.begin(
        sourceKey: 'book',
        request: request(2),
      );
      await expectLater(old.commit(publication(request(1))), throwsStateError);
      await expectLater(
        latest.commit(publication(request(2), sequence: 2)),
        throwsFormatException,
      );
      await latest.commit(publication(request(2)));
      latest.cancel();
      await expectLater(latest.complete(), throwsStateError);
      expect(
        (await repository.open(
          sourceKey: 'book',
          sourceRevision: 'source-v1',
        ))!.isComplete,
        isFalse,
      );
    },
  );

  test(
    'busy writer rejects queued operations and replacement isolates old readers',
    () async {
      final old = await repository.begin(
        sourceKey: 'book',
        request: request(1),
      );
      final commit = old.commit(publication(request(1)));
      await expectLater(old.commit(publication(request(1))), throwsStateError);
      await commit;
      await old.complete();
      final previous = (await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      ))!;
      final latest = await repository.begin(
        sourceKey: 'book',
        request: request(2),
      );
      await latest.commit(publication(request(2)));
      expect(
        (await previous.readRange(1, request: request(3))).fragment.wordCount,
        greaterThan(0),
      );
    },
  );

  test(
    'automatic checkpoint then valid reopen skips acquisition and worker analysis',
    () async {
      final supervisor = DocumentPreparationSupervisor(repository: repository);
      addTearDown(supervisor.shutdown);
      final first = <DocumentPreparationPublication>[];
      final q = request(1, text: List.filled(1200, 'A sentence.').join(' '));
      final result = await supervisor.prepareRanges(
        q,
        cacheKey: 'book',
        onPublication: (p) async {
          first.add(p);
        },
      );
      expect(result.outcome, DocumentPreparationOutcome.ready);
      expect(first.length, greaterThan(1));
      final cache = (await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      ))!;
      expect(cache.isComplete, isTrue);
      // Later chunk corruption must not cause opening to validate the whole book.
      final laterFile = File('${cache.path}/${cache.rangeCount}.json');
      final saved = await laterFile.readAsString();
      await laterFile.writeAsString('corrupt');
      expect((await cache.readRange(1, request: request(2))).sequence, 1);
      await laterFile.writeAsString(saved);
      final second = <DocumentPreparationPublication>[];
      var acquired = false;
      final reopened = await supervisor.prepareRanges(
        request(2),
        cacheKey: 'book',
        acquireSource: () async {
          acquired = true;
          throw StateError('cache must skip source');
        },
        onPublication: (p) async {
          second.add(p);
        },
      );
      expect(reopened.outcome, DocumentPreparationOutcome.ready);
      expect(reopened.workerName, 'prepared-range-cache');
      expect(acquired, isFalse);
      expect(
        second.map((p) => p.range.sourceStart),
        first.map((p) => p.range.sourceStart),
      );
      expect(
        second.map((p) => p.fragment.speakableText),
        first.map((p) => p.fragment.speakableText),
      );
    },
  );

  test(
    'corrupt first chunk rebuilds safely; partial cache is never complete',
    () async {
      final q = request(1);
      final writer = await repository.begin(sourceKey: 'book', request: q);
      await writer.commit(publication(q));
      await writer.complete();
      final cache = (await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      ))!;
      await File('${cache.path}/1.json').writeAsString('corrupt');
      final supervisor = DocumentPreparationSupervisor(repository: repository);
      addTearDown(supervisor.shutdown);
      var acquired = false;
      final result = await supervisor.prepareRanges(
        request(2),
        cacheKey: 'book',
        acquireSource: () async {
          acquired = true;
        },
        onPublication: (_) async {},
      );
      expect(result.outcome, DocumentPreparationOutcome.ready);
      expect(acquired, isTrue);
      expect(result.workerName, isNot('prepared-range-cache'));
      expect(
        (await repository.open(
          sourceKey: 'book',
          sourceRevision: 'source-v1',
        ))!.isComplete,
        isTrue,
      );
    },
  );
  test('sequential raw-byte proof migrates only after committed EOF', () async {
    final text = List.filled(18000, 'A sentence.\n\n').join();
    final bytes = utf8.encode(text);
    final source = File('${directory.path}/source.txt');
    await source.writeAsBytes(bytes);
    final q = DocumentPreparationRequest(
      ownerId: 'reader',
      revision: 3,
      kind: DocumentPreparationKind.bytes,
      fileName: 'source.txt',
      sourcePath: source.path,
      sourceRevision: 'captured-rev',
      watchSession: 5,
    );
    final supervisor = DocumentPreparationSupervisor(repository: repository);
    addTearDown(supervisor.shutdown);
    final migrations = <DocumentIdentityMigration>[];
    var ranges = 0;
    final result = await supervisor.prepareRanges(
      q,
      cacheKey: 'file',
      onPublication: (p) async {
        ranges++;
        expect(migrations, isEmpty);
      },
      onIdentityMigration: (m) async {
        migrations.add(m);
      },
    );
    expect(result.outcome, DocumentPreparationOutcome.ready);
    expect(ranges, greaterThan(2));
    expect(
      migrations.single.integrityBasis,
      DocumentIdentityIntegrityBasis.committedAcquiredByteCoverage,
    );
    expect(
      migrations.single.canonicalDocumentId,
      'doc_acquired_${sha256.convert(bytes)}',
    );
    expect(await source.readAsBytes(), bytes);
    final cache = (await repository.open(
      sourceKey: 'file',
      sourceRevision: 'captured-rev',
    ))!;
    final rebound = cache.identityMigration(
      DocumentPreparationRequest(
        ownerId: 'reader',
        revision: 4,
        kind: q.kind,
        sourceRevision: q.sourceRevision,
        watchSession: 6,
      ),
    );
    expect(rebound!.documentRevision, 4);
    expect(rebound.watchSession, 6);
    expect(rebound.canonicalDocumentId, migrations.single.canonicalDocumentId);
  });

  test(
    'captured text proof preserves UTF8 across a split surrogate pair',
    () async {
      final text = '${'a ' * 4095}a😀 end. ${'A sentence. ' * 1000}';
      final q = request(1, text: text);
      final supervisor = DocumentPreparationSupervisor();
      addTearDown(supervisor.shutdown);
      final migrations = <DocumentIdentityMigration>[];
      final result = await supervisor.prepareRanges(
        q,
        onPublication: (_) async {},
        onIdentityMigration: (m) async {
          migrations.add(m);
        },
      );
      expect(result.outcome, DocumentPreparationOutcome.ready);
      expect(
        migrations.single.canonicalDocumentId,
        'doc_acquired_${sha256.convert(utf8.encode(text))}',
      );
      expect(
        migrations.single.integrityBasis,
        DocumentIdentityIntegrityBasis.completeSourceBytes,
      );
    },
  );

  test(
    'cancelled preparation suppresses canonical proof and complete cache',
    () async {
      final supervisor = DocumentPreparationSupervisor(repository: repository);
      addTearDown(supervisor.shutdown);
      final migrations = <DocumentIdentityMigration>[];
      final result = await supervisor.prepareRanges(
        request(1, text: 'A sentence. ' * 4000),
        cacheKey: 'book',
        onPublication: (_) async {
          supervisor.cancel();
        },
        onIdentityMigration: (m) async {
          migrations.add(m);
        },
      );
      expect(result.outcome, DocumentPreparationOutcome.cancelled);
      await supervisor.shutdown();
      expect(migrations, isEmpty);
      expect(
        (await repository.open(
          sourceKey: 'book',
          sourceRevision: 'source-v1',
        ))!.isComplete,
        isFalse,
      );
    },
  );

  test(
    'sequential importer observers match exact bytes and report EOF once',
    () async {
      final bytes = Uint8List.fromList(utf8.encode('<p>é&amp; text.</p>'));
      final acquired = <int>[];
      var eof = 0;
      final units = await DocumentImportService()
          .streamUnits(
            fileName: 'book.html',
            bytes: bytes,
            onAcquiredBytes: acquired.addAll,
            onAcquiredEof: () {
              eof++;
            },
          )
          .toList();
      expect(acquired, bytes);
      expect(eof, 1);
      expect(units.map((u) => u.text).join(), contains('é& text.'));
    },
  );
  test(
    'ZIP complete captured bytes prove identity; file-backed ZIP remains partial',
    () async {
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'word/document.xml',
            '<w:document xmlns:w="w"><w:body><w:p><w:r><w:t>${'A sentence. ' * 900}</w:t></w:r></w:p></w:body></w:document>',
          ),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final source = File('${directory.path}/book.docx');
      await source.writeAsBytes(bytes);
      final supervisor = DocumentPreparationSupervisor(repository: repository);
      addTearDown(supervisor.shutdown);
      DocumentPreparationRequest zipRequest(
        int revision, {
        required bool captured,
      }) => DocumentPreparationRequest(
        ownerId: 'reader',
        revision: revision,
        kind: DocumentPreparationKind.bytes,
        fileName: 'book.docx',
        bytes: captured ? bytes : null,
        sourcePath: captured ? null : source.path,
        sourceRevision: 'zip-rev',
        watchSession: 5,
      );
      final migrations = <DocumentIdentityMigration>[];
      final fileResult = await supervisor.prepareRanges(
        zipRequest(1, captured: false),
        cacheKey: 'zip-file',
        onPublication: (_) async {},
        onIdentityMigration: (m) async {
          migrations.add(m);
        },
      );
      expect(fileResult.outcome, DocumentPreparationOutcome.ready);
      expect(migrations, isEmpty);
      expect(
        (await repository.open(
          sourceKey: 'zip-file',
          sourceRevision: 'zip-rev',
        ))!.isComplete,
        isFalse,
      );
      final captured = await supervisor.prepareRanges(
        zipRequest(2, captured: true),
        cacheKey: 'zip-bytes',
        onPublication: (_) async {},
      );
      expect(captured.outcome, DocumentPreparationOutcome.ready);
      expect(
        (await repository.open(
          sourceKey: 'zip-bytes',
          sourceRevision: 'zip-rev',
        ))!.isComplete,
        isTrue,
      );
    },
  );

  test(
    'later corruption invalidates generation before failure; retry rebuilds source',
    () async {
      final supervisor = DocumentPreparationSupervisor(repository: repository);
      addTearDown(supervisor.shutdown);
      final text = List.generate(
        1000,
        (index) => 'Section $index has its own sentence.',
      ).join('\n\n');
      final source = File('${directory.path}/source.txt');
      await source.writeAsString(text);
      DocumentPreparationRequest sourceRequest(int revision) =>
          DocumentPreparationRequest(
            ownerId: 'reader',
            revision: revision,
            kind: DocumentPreparationKind.bytes,
            fileName: 'source.txt',
            sourcePath: source.path,
            sourceRevision: 'source-v1',
            watchSession: 5,
          );
      final original = <DocumentPreparationPublication>[];
      final prepared = await supervisor.prepareRanges(
        sourceRequest(1),
        cacheKey: 'book',
        onPublication: (p) async {
          original.add(p);
        },
      );
      expect(prepared.outcome, DocumentPreparationOutcome.ready);
      final cache = (await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      ))!;
      await File('${cache.path}/2.json').writeAsString('corrupt');
      var published = 0;
      final result = await supervisor.prepareRanges(
        sourceRequest(2),
        cacheKey: 'book',
        onPublication: (p) async {
          published++;
          expect(p.isLast, isFalse);
        },
      );
      expect(result.outcome, DocumentPreparationOutcome.failed);
      expect(result.error, contains('Unreadable cache range 2'));
      expect(published, 1);
      expect(
        await repository.open(sourceKey: 'book', sourceRevision: 'source-v1'),
        isNull,
      );
      expect(await File('${cache.path}/invalidated').exists(), isTrue);

      final rebuilt = <DocumentPreparationPublication>[];
      final retry = await supervisor.prepareRanges(
        sourceRequest(3),
        cacheKey: 'book',
        onPublication: (p) async {
          rebuilt.add(p);
        },
      );
      expect(retry.outcome, DocumentPreparationOutcome.ready);
      expect(retry.workerName, isNot('prepared-range-cache'));
      final replacement = (await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      ))!;
      expect(replacement.path, isNot(cache.path));
      expect(replacement.isComplete, isTrue);
      expect(rebuilt.map((p) => p.sequence), original.map((p) => p.sequence));
      expect(
        rebuilt.map((p) => p.range.sourceStart),
        original.map((p) => p.range.sourceStart),
      );
      expect(
        rebuilt.map((p) => p.range.sourceEnd),
        original.map((p) => p.range.sourceEnd),
      );
      String normalized(String value) =>
          value.replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(
        normalized(rebuilt.map((p) => p.fragment.speakableText).join(' ')),
        normalized(text),
      );
      expect(await source.readAsString(), text);
    },
  );

  test(
    'invalidating an older generation cannot revoke its replacement',
    () async {
      final first = await repository.begin(
        sourceKey: 'book',
        request: request(1),
      );
      await first.commit(publication(request(1)));
      await first.complete();
      final old = (await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      ))!;
      final latest = await repository.begin(
        sourceKey: 'book',
        request: request(2),
      );
      await latest.commit(publication(request(2)));
      await latest.complete();
      await old.invalidate();
      final replacement = (await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      ))!;
      expect(replacement.path, latest.path);
      expect(
        (await replacement.readRange(1, request: request(3))).isLast,
        isTrue,
      );
      await expectLater(
        old.readRange(1, request: request(3)),
        throwsFormatException,
      );
    },
  );

  test(
    'partial cache recovery restarts from source instead of resuming prefix',
    () async {
      final partial = await repository.begin(
        sourceKey: 'book',
        request: request(1),
      );
      await partial.commit(publication(request(1, text: 'Discarded prefix.')));
      partial.cancel();
      final supervisor = DocumentPreparationSupervisor(repository: repository);
      addTearDown(supervisor.shutdown);
      final fragments = <String>[];
      final result = await supervisor.prepareRanges(
        request(2),
        cacheKey: 'book',
        onPublication: (p) async {
          fragments.add(p.fragment.speakableText);
        },
      );
      expect(result.outcome, DocumentPreparationOutcome.ready);
      expect(
        fragments.join(' '),
        publication(request(2)).fragment.speakableText,
      );
      final complete = (await repository.open(
        sourceKey: 'book',
        sourceRevision: 'source-v1',
      ))!;
      expect(complete.isComplete, isTrue);
      expect(complete.path, isNot(partial.path));
    },
  );

  test(
    'cancelling cache replay releases slot despite an uncompleted consumer',
    () async {
      final supervisor = DocumentPreparationSupervisor(repository: repository);
      await supervisor.prepareRanges(
        request(1),
        cacheKey: 'book',
        onPublication: (_) async {},
      );
      final pending = Completer<void>();
      final result = await supervisor.prepareRanges(
        request(2),
        cacheKey: 'book',
        onPublication: (_) {
          supervisor.cancel();
          return pending.future;
        },
      );
      expect(result.outcome, DocumentPreparationOutcome.cancelled);
      await supervisor.shutdown().timeout(const Duration(seconds: 2));
      pending.complete();
    },
  );
  test(
    'cancellation drains a pending identity consumer without publishing success',
    () async {
      final supervisor = DocumentPreparationSupervisor(repository: repository);
      final pending = Completer<void>();
      final result = await supervisor.prepareRanges(
        request(1, text: 'A sentence. ' * 1200),
        cacheKey: 'book',
        onPublication: (_) async {},
        onIdentityMigration: (_) {
          supervisor.cancel();
          return pending.future;
        },
      );
      expect(result.outcome, DocumentPreparationOutcome.cancelled);
      await supervisor.shutdown().timeout(const Duration(seconds: 2));
      pending.complete();
    },
  );
}
