import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/document_preparation.dart';
import '../models/document_import_exception.dart';
import '../models/reader_document.dart';
import 'document_import_service.dart';
import 'prepared_document_snapshot.dart';
import 'reader_document_serialization_service.dart';

/// Main-isolate owner of one active operation and one latest pending request.
/// Native PDF extraction drains in its adapter; only pure Dart work is killed.
class DocumentPreparationSupervisor {
  DocumentPreparationSupervisor({
    this.timeout = const Duration(minutes: 2),
    PdfTextExtractor? pdfTextExtractor,
    this.testImporter,
    this.workerEntryPoint = documentPreparationWorker,
  }) : _pdfTextExtractor =
           pdfTextExtractor ??
           const PdfrxPdfTextExtractor(deferFormatting: true);

  final Duration timeout;
  final PdfTextExtractor _pdfTextExtractor;

  /// Compatibility seam for controllable importer tests; never sent to workers.
  final DocumentImportService? testImporter;
  final void Function(DocumentPreparationWorkerInput) workerEntryPoint;
  _PreparationJob? _active;
  _PreparationJob? _pending;
  bool _closed = false;
  Future<void>? _shutdown;

  int get activeCount => _active == null ? 0 : 1;
  int get pendingCount => _pending == null ? 0 : 1;

  Future<DocumentPreparationResult> prepare(
    DocumentPreparationRequest request, {
    Future<Uint8List> Function()? acquireBytes,
  }) {
    final job = _PreparationJob(request, acquireBytes);
    if (_closed) {
      job.finish(DocumentPreparationOutcome.cancelled);
    } else if (_active == null) {
      _launch(job);
    } else {
      _pending?.finish(DocumentPreparationOutcome.cancelled);
      _pending = job;
      // Suppress active publication immediately, but drain its native bridge.
      _active!.cancel();
    }
    return job.result.future;
  }

  void cancel() {
    _pending?.finish(DocumentPreparationOutcome.cancelled);
    _pending = null;
    _active?.cancel();
  }

  Future<void> shutdown() => _shutdown ??= _close();

  Future<void> _close() async {
    _closed = true;
    cancel();
    await _active?.drained.future;
  }

  void _launch(_PreparationJob job) {
    _active = job;
    unawaited(_execute(job));
  }

  Future<void> _execute(_PreparationJob job) async {
    final timer = Timer(timeout, () => job.cancel(timedOut: true));
    try {
      var request = job.request;
      if (job.acquireBytes != null) {
        final bytes = await job.acquireBytes!();
        if (job.result.isCompleted) return;
        request = DocumentPreparationRequest(
          ownerId: request.ownerId,
          revision: request.revision,
          kind: request.kind,
          fileName: request.fileName,
          bytes: bytes.asUnmodifiableView(),
          text: request.text,
          watchSession: request.watchSession,
        );
      }

      PdfTextExtractionResult? pdf;
      if (testImporter == null &&
          request.kind == DocumentPreparationKind.bytes &&
          request.fileName!.toLowerCase().endsWith('.pdf')) {
        // pdfrx owns its native worker and disposal. Timeout is terminal to the
        // caller, but this slot remains occupied until extraction has drained.
        pdf = await _pdfTextExtractor.extract(
          fileName: request.fileName!,
          bytes: request.bytes!,
        );
      }
      if (job.result.isCompleted) return;
      if (testImporter != null) {
        final document = await _import(request, testImporter!);
        if (!job.result.isCompleted) {
          job.result.complete(
            DocumentPreparationResult(
              request: request,
              outcome: DocumentPreparationOutcome.ready,
              document: freezePreparedDocument(document),
              workerName: 'test-adapter',
            ),
          );
        }
        return;
      }
      final port = ReceivePort();
      job.port = port;
      final response = Completer<Object?>();
      final exited = Completer<void>();
      final subscription = port.listen((message) {
        if (message == null && !exited.isCompleted) exited.complete();
        if (!response.isCompleted) response.complete(message);
      });
      job.abort = () {
        job.isolate?.kill(priority: Isolate.immediate);
        if (!response.isCompleted) response.complete(null);
      };
      try {
        job.isolate = await Isolate.spawn(
          workerEntryPoint,
          DocumentPreparationWorkerInput(request, pdf, port.sendPort),
          onError: port.sendPort,
          onExit: port.sendPort,
          debugName: 'document-preparation-${request.revision}',
        );
        if (job.result.isCompleted) job.abort!();
        final message = await response.future;
        if (job.result.isCompleted) return;
        if (message is DocumentPreparationResult &&
            message.request.ownerId == request.ownerId &&
            message.request.revision == request.revision &&
            message.request.kind == request.kind &&
            message.request.watchSession == request.watchSession) {
          job.result.complete(message);
        } else {
          job.finish(
            DocumentPreparationOutcome.failed,
            error:
                'Preparation worker exited or returned an invalid result: $message',
          );
        }
      } finally {
        job.isolate?.kill(priority: Isolate.immediate);
        if (job.isolate != null) await exited.future;
        await subscription.cancel();
        port.close();
        job.abort = null;
      }
    } catch (error) {
      job.finish(DocumentPreparationOutcome.failed, error: '$error');
    } finally {
      timer.cancel();
      job.drained.complete();
      _active = null;
      final next = _pending;
      _pending = null;
      if (next != null && !_closed) _launch(next);
    }
  }
}

class _PreparationJob {
  _PreparationJob(this.request, this.acquireBytes);
  final Future<Uint8List> Function()? acquireBytes;
  final DocumentPreparationRequest request;
  final result = Completer<DocumentPreparationResult>();
  final drained = Completer<void>();
  Isolate? isolate;
  ReceivePort? port;
  void Function()? abort;

  void finish(DocumentPreparationOutcome outcome, {String? error}) {
    if (!result.isCompleted) {
      result.complete(
        DocumentPreparationResult(
          request: request,
          outcome: outcome,
          error: error,
        ),
      );
    }
  }

  void cancel({bool timedOut = false}) {
    finish(
      timedOut
          ? DocumentPreparationOutcome.timedOut
          : DocumentPreparationOutcome.cancelled,
    );
    abort?.call();
  }
}

class DocumentPreparationWorkerInput {
  const DocumentPreparationWorkerInput(this.request, this.pdf, this.reply);
  final DocumentPreparationRequest request;
  final PdfTextExtractionResult? pdf;
  final SendPort reply;
}

/// Entry point receives data only: no controller, callbacks or native handles.
void documentPreparationWorker(DocumentPreparationWorkerInput input) async {
  try {
    final importer = DocumentImportService(
      pdfTextExtractor: _ExtractedPdf(input.pdf),
    );
    final document = freezePreparedDocument(
      await _import(input.request, importer),
    );
    final serialized = const ReaderDocumentSerializationService()
        .serializeToJsonString(document);
    Isolate.exit(
      input.reply,
      DocumentPreparationResult(
        request: input.request,
        outcome: DocumentPreparationOutcome.ready,
        document: document,
        serializedDocument: serialized,
        workerName: Isolate.current.debugName,
      ),
    );
  } catch (error) {
    Isolate.exit(
      input.reply,
      DocumentPreparationResult(
        request: input.request,
        outcome: DocumentPreparationOutcome.failed,
        error: '$error',
        importFailure: error is DocumentImportException
            ? DocumentImportException(
                code: error.code,
                message: error.message,
                fileName: error.fileName,
              )
            : null,
      ),
    );
  }
}

Future<ReaderDocument> _import(
  DocumentPreparationRequest request,
  DocumentImportService importer,
) async => switch (request.kind) {
  DocumentPreparationKind.bytes => importer.importBytes(
    fileName: request.fileName!,
    bytes: request.bytes!,
  ),
  DocumentPreparationKind.pastedText => importer.importPastedText(
    request.text!,
  ),
  DocumentPreparationKind.sharedText => importer.importSharedText(
    request.text!,
  ),
  DocumentPreparationKind.sample => ReaderDocument.sample(),
};

class _ExtractedPdf implements PdfTextExtractor {
  const _ExtractedPdf(this.result);
  final PdfTextExtractionResult? result;
  @override
  Future<PdfTextExtractionResult> extract({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (result == null) {
      throw StateError('PDF extraction bridge was not supplied.');
    }
    return formatPdfExtraction(result!);
  }
}
