import 'dart:typed_data';
import 'character_cast_registry.dart';
import 'reader_document.dart';
import 'document_import_exception.dart';
import 'reader_operation.dart';

/// Provisional discovery precedes the refined range with the same sequence.
/// The supervisor rejects old operations and discoveries after range commit.
class CharacterDiscoveryPublication {
  const CharacterDiscoveryPublication({
    required this.request,
    required this.sequence,
    required this.registry,
  });
  final DocumentPreparationRequest request;
  final int sequence;
  final CharacterCastRegistry registry;
}

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
    this.sourcePath,
    this.sourceRevision,
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
  final String? sourcePath;
  final String? sourceRevision;

  String get operationId => "$ownerId:$revision";
  String get effectiveSourceRevision => sourceRevision ?? operationId;

  /// Publications echo identity, never the book-sized intake payload.
  DocumentPreparationRequest get identityOnly => DocumentPreparationRequest(
    ownerId: ownerId,
    revision: revision,
    kind: kind,
    fileName: fileName,
    sourcePath: sourcePath,
    sourceRevision: sourceRevision,
    watchSession: watchSession,
  );
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

/// Every counter describes committed work in one operation, never elapsed time.
enum PreparationStage {
  acquisition,
  parsing,
  normalization,
  mapping,
  analysis,
  pronunciation,
  planning,
  resources,
  synthesis,
  persistence,
}

enum PreparationWorkState {
  working,
  waiting,
  stalled,
  failed,
  cancelled,
  complete,
}

class PreparationProgress {
  const PreparationProgress({
    required this.stage,
    required this.state,
    required this.completed,
    required this.unit,
    this.total,
    this.discovered,
    this.waitingReason,
    this.error,
    this.workRevision,
    this.scope,
    this.operationId,
    this.ownerEpoch,
    this.updatedAt,
    this.operationState,
    this.retryOf,
    this.attempt = 0,
  });
  final PreparationStage stage;
  final PreparationWorkState state;
  final int completed;
  final int? total;
  final int? discovered;
  final String unit;
  final String? waitingReason;
  final String? error;
  final String? workRevision;
  final String? scope;
  final String? operationId;
  final int? ownerEpoch;
  final DateTime? updatedAt;
  final OperationState? operationState;
  final String? retryOf;
  final int attempt;
  double? get fraction =>
      completed < 0 || total == null || total! <= 0 || completed > total!
      ? null
      : completed / total!;

  bool get isTerminal =>
      state == PreparationWorkState.complete ||
      state == PreparationWorkState.failed ||
      state == PreparationWorkState.cancelled;

  PreparationProgress owned({
    required String operationId,
    required int ownerEpoch,
    String? scope,
    String? retryOf,
    int? attempt,
  }) => PreparationProgress(
    stage: stage,
    state: state,
    completed: completed,
    unit: unit,
    total: total,
    discovered: discovered,
    waitingReason: waitingReason,
    error: error,
    workRevision: workRevision,
    scope: scope ?? this.scope,
    operationId: operationId,
    ownerEpoch: ownerEpoch,
    updatedAt: updatedAt ?? DateTime.now(),
    operationState: operationState,
    retryOf: retryOf ?? this.retryOf,
    attempt: attempt ?? this.attempt,
  );

  ReaderOperation toOperation({
    OperationOwnerKind ownerKind = OperationOwnerKind.document,
  }) => ReaderOperation(
    operationId: operationId ?? workRevision ?? 'legacy:${stage.name}',
    ownerKind: ownerKind,
    ownerEpoch: ownerEpoch ?? 0,
    attempt: attempt,
    stage: stage.name,
    scope: scope ?? '',
    state:
        operationState ??
        switch (state) {
          PreparationWorkState.working => OperationState.running,
          PreparationWorkState.waiting => OperationState.waiting,
          PreparationWorkState.stalled => OperationState.waiting,
          PreparationWorkState.failed => OperationState.failed,
          PreparationWorkState.cancelled => OperationState.cancelled,
          PreparationWorkState.complete => OperationState.succeeded,
        },
    completedUnits: completed,
    totalUnits: total,
    discoveredUnits: discovered,
    unit: unit,
    updatedAt: updatedAt ?? DateTime.now(),
    error: error,
    message: waitingReason,
    retryOf: retryOf,
    recoveryActions: isTerminal
        ? [
            if (state == PreparationWorkState.failed)
              OperationRecoveryAction.retry,
          ]
        : [OperationRecoveryAction.cancel],
  );

  PreparationProgress withState(
    PreparationWorkState state, {
    String? waitingReason,
    OperationState? operationState,
  }) => PreparationProgress(
    stage: stage,
    state: state,
    completed: completed,
    unit: unit,
    total: total,
    discovered: discovered,
    waitingReason: waitingReason,
    error: error,
    workRevision: workRevision,
    scope: scope,
    operationId: operationId,
    ownerEpoch: ownerEpoch,
    updatedAt: DateTime.now(),
    operationState: operationState,
    retryOf: retryOf,
    attempt: attempt,
  );
}

/// Main-isolate progress capability for a single producer/dependency version.
/// New work for the same stage invalidates both success and failure from the
/// previous ticket; changing documents invalidates every outstanding ticket.
class ReadingStageTicket {
  const ReadingStageTicket({
    required this.ownerId,
    required this.producerId,
    required this.documentRevision,
    required this.sourceRevision,
    required this.watchSession,
    required this.stage,
    required this.generation,
    required this.scope,
  });
  final String ownerId;
  final String producerId;
  final int documentRevision;
  final String sourceRevision;
  final int watchSession;
  final PreparationStage stage;
  final int generation;
  final String scope;
}

enum DocumentIdentityIntegrityBasis {
  completeSourceBytes,
  committedAcquiredByteCoverage,
}

/// Proof from the exact bytes consumed by one acquisition owner. Never inferred
/// from extracted text coordinates or a later reread of a mutable source path.
class SourceAcquisitionReceipt {
  const SourceAcquisitionReceipt({
    required this.ownerId,
    required this.documentRevision,
    required this.sourceRevision,
    required this.watchSession,
    required this.byteCount,
    required this.sha256,
    required this.integrityBasis,
  });
  final String ownerId;
  final int documentRevision;
  final String sourceRevision;
  final int? watchSession;
  final int byteCount;
  final String sha256;
  final DocumentIdentityIntegrityBasis integrityBasis;
}

/// The persistence/source owner emits this only after verifying complete
/// acquired-byte coverage. A partial-prefix digest cannot authorize migration.
class DocumentIdentityMigration {
  const DocumentIdentityMigration({
    required this.ownerId,
    required this.documentRevision,
    required this.sourceRevision,
    required this.watchSession,
    required this.provisionalDocumentId,
    required this.canonicalDocumentId,
    required this.integrityBasis,
  });
  final String ownerId;
  final int documentRevision;
  final String sourceRevision;
  final int watchSession;
  final String provisionalDocumentId;
  final String canonicalDocumentId;
  final DocumentIdentityIntegrityBasis integrityBasis;
}

/// Offsets belong to the source session, while the fragment retains local IDs.
/// The fingerprint on a fragment describes that fragment only; it is never a
/// claim that an incompletely acquired source has been verified in full.
class PreparedDocumentRange {
  const PreparedDocumentRange({
    required this.sourceStart,
    required this.sourceEnd,
    required this.wordStart,
    required this.wordEnd,
    required this.segmentStart,
    required this.segmentEnd,
    this.sourceUnit = 'utf16',
    this.sourceLocator,
  });
  final int sourceStart;
  final int sourceEnd;
  final String sourceUnit;
  final String? sourceLocator;
  final int wordStart;
  final int wordEnd;
  final int segmentStart;
  final int segmentEnd;
}

class DocumentPreparationPublication {
  DocumentPreparationPublication({
    required this.request,
    required this.sequence,
    required this.range,
    required this.fragment,
    required Set<PreparationStage> coverage,
    required List<PreparationProgress> progress,
    required this.isLast,
    this.serializedFragment,
  }) : coverage = Set.unmodifiable(coverage),
       progress = List.unmodifiable(progress);
  final DocumentPreparationRequest request;
  final int sequence;
  final PreparedDocumentRange range;
  final ReaderDocument fragment;
  final Set<PreparationStage> coverage;
  final List<PreparationProgress> progress;
  final bool isLast;
  final String? serializedFragment;
  bool get isPreparationReady => coverage.containsAll(const {
    PreparationStage.normalization,
    PreparationStage.mapping,
    PreparationStage.analysis,
    PreparationStage.pronunciation,
  });
  bool get isSpeechPlanReady =>
      isPreparationReady && coverage.contains(PreparationStage.planning);
  bool get isResourceReady => coverage.contains(PreparationStage.resources);
}
