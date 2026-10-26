import 'dart:typed_data';

import 'reader_document.dart';
import 'document_import_exception.dart';

enum DocumentPreparationKind { bytes, pastedText, sharedText, sample }

enum DocumentPreparationOutcome { ready, failed, cancelled, timedOut }

/// Identity is assigned before intake awaits, and echoed by every terminal event.
class DocumentPreparationRequest {
  DocumentPreparationRequest({
    required this.ownerId,
    required this.revision,
    required this.kind,
    this.fileName,
    Uint8List? bytes,
    this.text,
    this.watchSession,
  }) : bytes = bytes == null
           ? null
           : Uint8List.fromList(bytes).asUnmodifiableView();

  final String ownerId;
  final int revision;
  final DocumentPreparationKind kind;
  final String? fileName;
  final Uint8List? bytes;
  final String? text;
  final int? watchSession;
}

class DocumentPreparationResult {
  const DocumentPreparationResult({
    required this.request,
    required this.outcome,
    this.document,
    this.serializedDocument,
    this.error,
    this.workerName,
    this.importFailure,
  });

  final DocumentPreparationRequest request;
  final DocumentPreparationOutcome outcome;
  final ReaderDocument? document;
  final String? serializedDocument;
  final String? error;
  final String? workerName;
  final DocumentImportException? importFailure;
}
