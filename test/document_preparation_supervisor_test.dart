import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/document_preparation_supervisor.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';

DocumentPreparationRequest request(int revision, {bool pdf = false}) =>
    DocumentPreparationRequest(
      ownerId: 'test',
      revision: revision,
      kind: pdf
          ? DocumentPreparationKind.bytes
          : DocumentPreparationKind.pastedText,
      text: 'John said, "Come with me."\n\n"Who is there?"',
      fileName: pdf ? 'fixture.pdf' : null,
      bytes: pdf ? Uint8List.fromList([1, 2, 3]) : null,
    );

void exitWithoutResult(DocumentPreparationWorkerInput input) => Isolate.exit();
void crashWorker(DocumentPreparationWorkerInput input) =>
    throw StateError('fixture crash');
void hangWorker(DocumentPreparationWorkerInput input) {
  ReceivePort().listen((_) {});
}

class PdfBarrier implements PdfTextExtractor {
  final started = Completer<void>();
  final release = Completer<PdfTextExtractionResult>();
  @override
  Future<PdfTextExtractionResult> extract({
    required String fileName,
    required Uint8List bytes,
  }) {
    started.complete();
    return release.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'queued byte request owns a snapshot independent of caller aliases',
    () async {
      final bridge = PdfBarrier();
      final supervisor = DocumentPreparationSupervisor(
        pdfTextExtractor: bridge,
      );
      addTearDown(supervisor.shutdown);
      final active = supervisor.prepare(request(1, pdf: true));
      await bridge.started.future;
      final bytes = Uint8List.fromList(utf8.encode('Original.'));
      final queued = DocumentPreparationRequest(
        ownerId: 'test',
        revision: 2,
        kind: DocumentPreparationKind.bytes,
        fileName: 'snapshot.txt',
        bytes: bytes,
      );
      final result = supervisor.prepare(queued);
      bytes.fillRange(0, bytes.length, 120);
      expect(() => queued.bytes![0] = 120, throwsUnsupportedError);
      bridge.release.complete(const PdfTextExtractionResult(pages: []));
      expect((await active).outcome, DocumentPreparationOutcome.cancelled);
      expect((await result).document!.speakableText, 'Original.');
    },
  );

  test(
    'byte acquisition is bounded and superseded pending reads never start',
    () async {
      final supervisor = DocumentPreparationSupervisor();
      addTearDown(supervisor.shutdown);
      final barrier = Completer<Uint8List>();
      var reads = 0;
      DocumentPreparationRequest bytesRequest(int revision) =>
          DocumentPreparationRequest(
            ownerId: 'test',
            revision: revision,
            kind: DocumentPreparationKind.bytes,
            fileName: 'fixture.txt',
          );
      final a = supervisor.prepare(
        bytesRequest(1),
        acquireBytes: () {
          reads++;
          return barrier.future;
        },
      );
      final b = supervisor.prepare(
        bytesRequest(2),
        acquireBytes: () async {
          reads++;
          return Uint8List.fromList(utf8.encode('Skipped.'));
        },
      );
      final c = supervisor.prepare(
        bytesRequest(3),
        acquireBytes: () async {
          reads++;
          return Uint8List.fromList(utf8.encode('Latest.'));
        },
      );
      expect(reads, 1);
      expect((await a).outcome, DocumentPreparationOutcome.cancelled);
      expect((await b).outcome, DocumentPreparationOutcome.cancelled);
      barrier.complete(Uint8List.fromList(utf8.encode('Old.')));
      expect((await c).document!.speakableText, 'Latest.');
      expect(reads, 2);
    },
  );

  test('long worker preparation leaves caller event loop available', () async {
    final supervisor = DocumentPreparationSupervisor();
    addTearDown(supervisor.shutdown);
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    final result = await supervisor.prepare(
      DocumentPreparationRequest(
        ownerId: 'test',
        revision: 1,
        kind: DocumentPreparationKind.pastedText,
        text: List.generate(
          1500,
          (i) => 'Paragraph $i describes the road ahead.',
        ).join('\n\n'),
      ),
    );
    timer.cancel();
    expect(
      result.outcome,
      DocumentPreparationOutcome.ready,
      reason: result.error,
    );
    expect(result.document!.wordCount, 9000);
    expect(ticks, greaterThan(2));
    expect(result.workerName, 'document-preparation-1');
  });

  for (final fixture in <String, String>{
    'text.txt': 'John said, "Come with me."\n\nAn unknown voice answered.',
    'text.md': '# Header\n\nJohn said, "Come with me."',
    'text.html':
        '<h1>Header</h1><p>John said, <em>"Come with me."</em></p><img src="missing.png">',
    'text.rtf': r'{\rtf1\ansi First paragraph.\par John said, "Come with me."}',
  }.entries) {
    test('worker fidelity for ${fixture.key}', () async {
      final supervisor = DocumentPreparationSupervisor();
      addTearDown(supervisor.shutdown);
      final bytes = Uint8List.fromList(utf8.encode(fixture.value));
      final expected = await DocumentImportService().importBytes(
        fileName: fixture.key,
        bytes: bytes,
      );
      final result = await supervisor.prepare(
        DocumentPreparationRequest(
          ownerId: 'formats',
          revision: 1,
          kind: DocumentPreparationKind.bytes,
          fileName: fixture.key,
          bytes: bytes,
        ),
      );
      expect(
        result.outcome,
        DocumentPreparationOutcome.ready,
        reason: result.error,
      );
      expect(
        result.serializedDocument,
        const ReaderDocumentSerializationService().serializeToJsonString(
          expected,
        ),
      );
    });
  }

  test(
    'real worker retains semantic artifact fidelity and freezes nested data',
    () async {
      final supervisor = DocumentPreparationSupervisor();
      addTearDown(supervisor.shutdown);
      final input = request(1);
      final result = await supervisor.prepare(input);
      expect(
        result.outcome,
        DocumentPreparationOutcome.ready,
        reason: result.error,
      );
      expect(result.workerName, 'document-preparation-1');
      final document = result.document!;
      final expected = DocumentImportService().importPastedText(input.text!);
      expect(
        result.serializedDocument,
        const ReaderDocumentSerializationService().serializeToJsonString(
          expected,
        ),
      );
      expect(document.speakableText, expected.speakableText);
      expect(
        document.wordSpans.map((s) => [s.start, s.end]),
        expected.wordSpans.map((s) => [s.start, s.end]),
      );
      expect(
        () => document.displayDocument.blocks.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => document.displayDocument.blocks.first.inlines.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => document.displayDocument.metadata['new'] = 'bad',
        throwsUnsupportedError,
      );
      expect(
        () => document.speechDocument.segments.first.wordSpans.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => document.positionMap.entries.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => document.basePronunciationArtifacts.artifacts.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => document.characterCastRegistry.narratorEntry.observedAliases
            .clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'one native active plus latest pending; cancelled native work drains',
    () async {
      final bridge = PdfBarrier();
      final supervisor = DocumentPreparationSupervisor(
        pdfTextExtractor: bridge,
      );
      addTearDown(supervisor.shutdown);
      final a = supervisor.prepare(request(1, pdf: true));
      await bridge.started.future;
      final b = supervisor.prepare(request(2));
      final c = supervisor.prepare(request(3));
      expect((await a).outcome, DocumentPreparationOutcome.cancelled);
      expect((await b).outcome, DocumentPreparationOutcome.cancelled);
      expect(supervisor.activeCount, 1);
      expect(supervisor.pendingCount, 1);
      bridge.release.complete(const PdfTextExtractionResult(pages: []));
      final last = await c;
      expect(
        last.outcome,
        DocumentPreparationOutcome.ready,
        reason: last.error,
      );
      expect(last.request.revision, 3);
      await supervisor.shutdown();
      expect(supervisor.activeCount, 0);
      expect(supervisor.pendingCount, 0);
      expect(
        (await supervisor.prepare(request(4))).outcome,
        DocumentPreparationOutcome.cancelled,
      );
    },
  );

  test('PDF bridge preserves PDF bytes and mapping through worker', () async {
    final bridge = PdfBarrier();
    final supervisor = DocumentPreparationSupervisor(pdfTextExtractor: bridge);
    addTearDown(supervisor.shutdown);
    final future = supervisor.prepare(request(1, pdf: true));
    bridge.release.complete(
      const PdfTextExtractionResult(
        pages: [
          PdfTextExtractionPage(pageIndex: 0, fullText: 'The first page.'),
          PdfTextExtractionPage(pageIndex: 1, fullText: 'The second page.'),
        ],
      ),
    );
    final result = await future;
    expect(
      result.outcome,
      DocumentPreparationOutcome.ready,
      reason: result.error,
    );
    expect(result.document!.pdfData, [1, 2, 3]);
    expect(() => result.document!.pdfData![0] = 4, throwsUnsupportedError);
    expect(jsonDecode(result.serializedDocument!)['pdfDataBase64'], 'AQID');
    expect(result.document!.positionMap.entries, isNotEmpty);
  });

  for (final entry in [exitWithoutResult, crashWorker]) {
    test('unexpected worker termination gives a terminal failure', () async {
      final supervisor = DocumentPreparationSupervisor(workerEntryPoint: entry);
      addTearDown(supervisor.shutdown);
      final result = await supervisor.prepare(request(1));
      expect(result.outcome, DocumentPreparationOutcome.failed);
    });
  }

  test(
    'worker timeout terminates intake and shutdown releases the slot',
    () async {
      final supervisor = DocumentPreparationSupervisor(
        workerEntryPoint: hangWorker,
        timeout: const Duration(milliseconds: 100),
      );
      final result = await supervisor.prepare(request(1));
      expect(result.outcome, DocumentPreparationOutcome.timedOut);
      await supervisor.shutdown();
      expect(supervisor.activeCount, 0);
    },
  );

  test('timeout reports promptly but shutdown awaits native drain', () async {
    final bridge = PdfBarrier();
    final supervisor = DocumentPreparationSupervisor(
      pdfTextExtractor: bridge,
      timeout: const Duration(milliseconds: 50),
    );
    final future = supervisor.prepare(request(1, pdf: true));
    await bridge.started.future;
    expect((await future).outcome, DocumentPreparationOutcome.timedOut);
    var drained = false;
    final shutdown = supervisor.shutdown().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    bridge.release.completeError(
      StateError('native failed after cancellation'),
    );
    await shutdown;
    expect(drained, isTrue);
  });
}
