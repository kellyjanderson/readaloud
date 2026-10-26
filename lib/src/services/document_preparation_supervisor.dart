import 'dart:async';
import 'dart:io';
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
  Object? _lastDrainError;
  Object? get lastDrainError => _lastDrainError;

  int get activeCount => _active == null ? 0 : 1;
  int get pendingCount => _pending == null ? 0 : 1;

  Future<DocumentPreparationResult> prepare(
    DocumentPreparationRequest request, {
    Future<Uint8List> Function()? acquireBytes,
  }) => _admit(request, acquireBytes: acquireBytes);

  Future<DocumentPreparationResult> prepareRanges(
    DocumentPreparationRequest request, {
    Future<Uint8List> Function()? acquireBytes,
    required Future<void> Function(DocumentPreparationPublication)
    onPublication,
    void Function(PreparationProgress)? onProgress,
    Future<void> Function()? acquireSource,
    Future<void> Function()? onDrained,
  }) {
    if (testImporter != null) {
      return prepare(request, acquireBytes: acquireBytes);
    }
    return _admit(
      request,
      acquireBytes: acquireBytes,
      onPublication: onPublication,
      onProgress: onProgress,
      acquireSource: acquireSource,
      onDrained: onDrained,
    );
  }

  Future<DocumentPreparationResult> _admit(
    DocumentPreparationRequest request, {
    Future<Uint8List> Function()? acquireBytes,
    Future<void> Function(DocumentPreparationPublication)? onPublication,
    void Function(PreparationProgress)? onProgress,
    Future<void> Function()? acquireSource,
    Future<void> Function()? onDrained,
  }) {
    final job = _PreparationJob(
      request,
      acquireBytes,
      onPublication,
      onProgress,
      acquireSource,
      onDrained,
    );
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
    var timer = Timer(timeout, () => job.cancel(timedOut: true));
    StreamIterator<PdfTextExtractionPage>? pdfPages;
    try {
      var request = job.request;
      if (job.acquireSource != null) await job.acquireSource!();
      if (job.result.isCompleted) return;
      job.onProgress?.call(
        const PreparationProgress(
          stage: PreparationStage.acquisition,
          state: PreparationWorkState.working,
          completed: 0,
          unit: 'bytes',
        ),
      );
      if (job.acquireBytes != null &&
          !(job.onPublication != null &&
              request.sourcePath != null &&
              _isSupportedRangeFormat(request.fileName))) {
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
          sourcePath: request.sourcePath,
          sourceRevision: request.sourceRevision,
        );
      }

      PdfTextExtractionResult? pdf;
      final progressivePdf =
          job.onPublication != null &&
          testImporter == null &&
          request.kind == DocumentPreparationKind.bytes &&
          request.fileName!.toLowerCase().endsWith('.pdf') &&
          _pdfTextExtractor is PdfrxPdfTextExtractor;
      if (progressivePdf) {
        pdfPages = StreamIterator(
          _pdfTextExtractor.streamPages(
            fileName: request.fileName!,
            sourcePath: request.sourcePath,
            bytes: request.bytes,
          ),
        );
      }
      if (!progressivePdf &&
          testImporter == null &&
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
      var sequence = 0;
      SendPort? credit;
      final subscription = port.listen((message) {
        if (message is SendPort) {
          credit = message;
          return;
        }
        if (message is _PdfPageDemand && pdfPages != null) {
          () async {
            try {
              final available = await pdfPages!.moveNext();
              if (!job.result.isCompleted) {
                message.reply.send(available ? pdfPages.current : null);
              }
            } catch (error) {
              if (!job.result.isCompleted) {
                job.finish(DocumentPreparationOutcome.failed, error: '$error');
                job.abort?.call();
              }
            }
          }();
          return;
        }

        if (message is DocumentPreparationPublication) {
          if (job.result.isCompleted ||
              !_sameRequest(message.request, request) ||
              message.sequence != sequence + 1) {
            return;
          }
          sequence = message.sequence;
          timer.cancel(); // Consumer demand may be paused indefinitely.
          // Exactly one unacknowledged fragment. The consumer controls ahead
          // work by completing its callback; stale callbacks cannot grant credit.
          Future<void>.sync(() => job.onPublication?.call(message)).then(
            (_) {
              if (!job.result.isCompleted) {
                timer = Timer(timeout, () => job.cancel(timedOut: true));
                credit?.send(sequence);
              }
            },
            onError: (Object error, StackTrace stack) {
              job.finish(DocumentPreparationOutcome.failed, error: '$error');
              job.abort?.call();
            },
          );
          return;
        }

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
          DocumentPreparationWorkerInput(
            request,
            pdf,
            port.sendPort,
            incremental: job.onPublication != null,
            nativePdf: progressivePdf,
          ),
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
      try {
        await pdfPages?.cancel();
      } catch (error) {
        _lastDrainError = error;
      }
      try {
        await job.onDrained?.call();
      } catch (error) {
        _lastDrainError = error;
      }
      job.drained.complete();
      _active = null;
      final next = _pending;
      _pending = null;
      if (next != null && !_closed) _launch(next);
    }
  }
}

class _PreparationJob {
  _PreparationJob(
    this.request,
    this.acquireBytes,
    this.onPublication,
    this.onProgress,
    this.acquireSource,
    this.onDrained,
  );
  final Future<void> Function()? acquireSource;
  final Future<void> Function()? onDrained;
  final Future<void> Function(DocumentPreparationPublication)? onPublication;
  final void Function(PreparationProgress)? onProgress;
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
  const DocumentPreparationWorkerInput(
    this.request,
    this.pdf,
    this.reply, {
    this.incremental = false,
    this.nativePdf = false,
  });
  final bool incremental;
  final bool nativePdf;
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
    if (input.incremental &&
        (_canStreamText(input.request) || input.nativePdf)) {
      await _publishTextRanges(input, importer);
      return;
    }
    final document = freezePreparedDocument(
      await _import(input.request, importer),
    );
    if (input.incremental) {
      final publication = _publication(
        input.request,
        document,
        1,
        0,
        0,
        0,
        document.speakableText.length,
        true,
      );
      final credits = ReceivePort();
      input.reply.send(credits.sendPort);
      input.reply.send(publication);
      await credits.first;
      credits.close();
    }
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
        request: input.incremental
            ? input.request.identityOnly
            : input.request,
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

bool _sameRequest(DocumentPreparationRequest a, DocumentPreparationRequest b) =>
    a.ownerId == b.ownerId &&
    a.revision == b.revision &&
    a.kind == b.kind &&
    a.watchSession == b.watchSession &&
    a.effectiveSourceRevision == b.effectiveSourceRevision;

bool _isSupportedRangeFormat(String? name) => const {
  'txt',
  'text',
  'md',
  'markdown',
  'html',
  'htm',
  'epub',
  'docx',
  'rtf',
  'pdf',
}.contains(name?.split('.').last.toLowerCase());
bool _canStreamText(DocumentPreparationRequest request) =>
    request.kind == DocumentPreparationKind.pastedText ||
    request.kind == DocumentPreparationKind.sharedText ||
    (request.kind == DocumentPreparationKind.bytes &&
        !request.fileName!.toLowerCase().endsWith('.pdf') &&
        _isSupportedRangeFormat(request.fileName));

/// Pure Dart owner: at most 8 Ki UTF-16 source units plus one input IO chunk and
/// one immutable publication. Waiting for consumer credit also pauses openRead.
/// Kill on replacement/timeout closes the isolate's file handles; native PDF
/// cancellation retains the separate supervisor drain rule above.
Future<void> _publishTextRanges(
  DocumentPreparationWorkerInput input,
  DocumentImportService importer,
) async {
  final request = input.request;
  final credits = ReceivePort();
  final creditIterator = StreamIterator<dynamic>(credits);
  input.reply.send(credits.sendPort);
  var sequence = 0;
  var sourceStart = 0;
  var wordStart = 0;
  var segmentStart = 0;
  ReaderDocument? last;
  var effectiveInput = input;
  String? completeSourceFingerprint;
  if (!input.nativePdf) {
    final text = request.text;
    Uint8List? completeBytes = request.bytes;
    if (text != null && text.length <= 8192) {
      completeSourceFingerprint = importer.completeTextFingerprint(
        text,
        shared: request.kind == DocumentPreparationKind.sharedText,
      );
    } else if (text == null) {
      if (completeBytes == null && request.sourcePath != null) {
        final builder = BytesBuilder(copy: false);
        await for (final bytes in File(request.sourcePath!).openRead(0, 8193)) {
          builder.add(bytes);
        }
        if (builder.length <= 8192) completeBytes = builder.takeBytes();
      }
      if (completeBytes != null && completeBytes.length <= 8192) {
        completeSourceFingerprint = importer.completeBytesFingerprint(
          request.fileName!,
          completeBytes,
        );
        effectiveInput = DocumentPreparationWorkerInput(
          DocumentPreparationRequest(
            ownerId: request.ownerId,
            revision: request.revision,
            kind: request.kind,
            fileName: request.fileName,
            bytes: completeBytes,
            sourceRevision: request.sourceRevision,
            watchSession: request.watchSession,
          ),
          input.pdf,
          input.reply,
          incremental: true,
        );
      }
    }
  }
  try {
    await for (final context in _contextUnits(
      _importUnits(effectiveInput, importer),
    )) {
      final unit = context.unit;
      final text = unit.text;
      final document = freezePreparedDocument(
        importer.importTextFragment(
          text: text,
          title:
              request.fileName ??
              (request.kind == DocumentPreparationKind.sharedText
                  ? 'Shared Text'
                  : 'Pasted Text'),
          sessionId: request.operationId,
          sourceStart: sourceStart,
          unit: unit,
          followingUnit: context.following,
          completeSourceFingerprint: completeSourceFingerprint,
        ),
      );
      final publication = _publication(
        request,
        document,
        ++sequence,
        sourceStart,
        wordStart,
        segmentStart,
        sourceStart + text.length,
        false,
        sourceLocator: unit.locator,
      );
      input.reply.send(publication);
      if (!await creditIterator.moveNext() ||
          creditIterator.current != sequence) {
        throw StateError('Invalid preparation publication credit.');
      }
      sourceStart += text.length;
      wordStart += document.wordCount;
      segmentStart += document.speechDocument.segments.length;
      last = document;
    }
    if (last == null) {
      throw StateError('No readable text was found in the source.');
    }
    // EOF is terminal progress, not a second publication of the last fragment.
    input.reply.send(
      DocumentPreparationResult(
        request: request.identityOnly,
        outcome: DocumentPreparationOutcome.ready,
        document: last,
        workerName: Isolate.current.debugName,
      ),
    );
  } finally {
    await creditIterator.cancel();
    credits.close();
  }
}

DocumentPreparationPublication _publication(
  DocumentPreparationRequest request,
  ReaderDocument document,
  int sequence,
  int sourceStart,
  int wordStart,
  int segmentStart,
  int sourceEnd,
  bool isLast, {
  String? sourceLocator,
}) {
  const coverage = {
    PreparationStage.acquisition,
    PreparationStage.parsing,
    PreparationStage.normalization,
    PreparationStage.mapping,
    PreparationStage.analysis,
    PreparationStage.pronunciation,
  };
  return DocumentPreparationPublication(
    request: request.identityOnly,
    sequence: sequence,
    range: PreparedDocumentRange(
      sourceStart: sourceStart,
      sourceEnd: sourceEnd,
      sourceLocator: sourceLocator,
      wordStart: wordStart,
      wordEnd: wordStart + document.wordCount,
      segmentStart: segmentStart,
      segmentEnd: segmentStart + document.speechDocument.segments.length,
    ),
    fragment: document,
    coverage: coverage,
    isLast: isLast,
    progress: [
      for (final stage in coverage)
        PreparationProgress(
          stage: stage,
          state: isLast
              ? PreparationWorkState.complete
              : PreparationWorkState.working,
          completed: stage == PreparationStage.acquisition
              ? sourceEnd
              : wordStart + document.wordCount,
          unit: stage == PreparationStage.acquisition ? 'utf16' : 'words',
        ),
      for (final stage in const [
        PreparationStage.planning,
        PreparationStage.resources,
        PreparationStage.synthesis,
        PreparationStage.persistence,
      ])
        PreparationProgress(
          stage: stage,
          state: PreparationWorkState.waiting,
          completed: 0,
          unit: 'ranges',
          waitingReason: 'Owned by downstream consumer',
        ),
    ],
  );
}

Stream<String> _sourceText(DocumentPreparationRequest request) async* {
  final text = request.text!;
  for (var offset = 0; offset < text.length; offset += 8192) {
    yield text.substring(offset, (offset + 8192).clamp(0, text.length));
  }
}

class _PdfPageDemand {
  const _PdfPageDemand(this.reply);
  final SendPort reply;
}

Stream<DocumentImportUnit> _importUnits(
  DocumentPreparationWorkerInput input,
  DocumentImportService importer,
) async* {
  final request = input.request;
  if (input.nativePdf) {
    final replies = ReceivePort();
    final iterator = StreamIterator<dynamic>(replies);
    try {
      while (true) {
        input.reply.send(_PdfPageDemand(replies.sendPort));
        if (!await iterator.moveNext() || iterator.current == null) break;
        final page = iterator.current as PdfTextExtractionPage;
        final formatted = await formatPdfExtraction(
          PdfTextExtractionResult(pages: [page]),
        );
        await for (final text in boundedProseUnits(
          Stream.value(formatted.pages.single.fullText),
        )) {
          yield DocumentImportUnit(
            text: text,
            locator: 'page:${page.pageIndex}',
            type: ReaderDocumentType.pdf,
          );
        }
      }
    } finally {
      await iterator.cancel();
      replies.close();
    }
  } else if (request.kind == DocumentPreparationKind.bytes) {
    yield* importer.streamUnits(
      fileName: request.fileName!,
      sourcePath: request.bytes == null ? request.sourcePath : null,
      bytes: request.bytes,
    );
  } else {
    await for (final text in boundedProseUnits(_sourceText(request))) {
      yield DocumentImportUnit(text: text);
    }
  }
}

class _ContextImportUnit {
  const _ContextImportUnit(this.unit, this.following);
  final DocumentImportUnit unit;
  final DocumentImportUnit? following;
}

/// Only an attribution-sensitive boundary asks for a following unit. The
/// additional unit and its 12-segment halo are explicit bounded lookahead;
/// ordinary PDF pages do not wait on acquisition of their successor.
Stream<_ContextImportUnit> _contextUnits(
  Stream<DocumentImportUnit> source,
) async* {
  final iterator = StreamIterator(source);
  DocumentImportUnit? pending;
  try {
    while (pending != null || await iterator.moveNext()) {
      final unit = pending ?? iterator.current;
      pending = null;
      final text = unit.text.trimRight();
      final quoteCount = RegExp('["“”]').allMatches(text).length;
      final needsFollowing =
          quoteCount.isOdd || RegExp(r'["”]\s*$').hasMatch(text);
      if (needsFollowing && await iterator.moveNext()) {
        pending = iterator.current;
      }
      yield _ContextImportUnit(unit, pending);
    }
  } finally {
    await iterator.cancel();
  }
}
