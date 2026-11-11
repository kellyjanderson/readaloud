import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/reader_operation.dart';
import 'package:read_aloud/src/services/tts_engine.dart';

ReaderOperation operation(
  String id,
  OperationState state, {
  int epoch = 1,
  int completed = 2,
  int? total = 4,
  String scope = 'fast',
  String? retryOf,
  int attempt = 0,
}) => ReaderOperation(
  operationId: id,
  ownerKind: OperationOwnerKind.document,
  ownerEpoch: epoch,
  stage: 'analysis',
  scope: scope,
  state: state,
  completedUnits: completed,
  totalUnits: total,
  unit: 'words',
  updatedAt: DateTime(2026, 11, 11, 0, epoch),
  retryOf: retryOf,
  attempt: attempt,
);

void main() {
  test('terminal delivery latches duplicates and same-id resurrection', () {
    for (final state in [
      OperationState.succeeded,
      OperationState.failed,
      OperationState.cancelled,
    ]) {
      final projection = ReaderOperationProjection();
      expect(projection.begin(operation('a', OperationState.running)), isTrue);
      expect(projection.update(operation('a', state)), isTrue);
      expect(projection.update(operation('a', state)), isFalse);
      expect(projection.begin(operation('a', OperationState.running)), isFalse);
      expect(projection.operations.single.state, state);
    }
  });

  test('retry has its own identity and rejects old successes and failures', () {
    final projection = ReaderOperationProjection();
    projection.begin(operation('a', OperationState.failed));
    projection.begin(
      operation('b', OperationState.running, epoch: 2, retryOf: 'a'),
    );
    expect(projection.operations.first.retryOf, 'a');
    for (final state in [
      OperationState.failed,
      OperationState.succeeded,
      OperationState.cancelled,
    ]) {
      expect(projection.update(operation('a', state)), isFalse);
      expect(projection.begin(operation('a', state)), isFalse);
    }
    expect(projection.operations.first.operationId, 'b');
  });

  test(
    'history is bounded and active scopes survive independent completion',
    () {
      final projection = ReaderOperationProjection(recentLimit: 3);
      projection.begin(
        operation('deep', OperationState.running, scope: 'deep'),
      );
      for (var i = 1; i <= 9; i++) {
        projection.begin(
          operation('fast-$i', OperationState.succeeded, attempt: i),
        );
      }
      expect(projection.operations.length, 4);
      expect(projection.operations.first.operationId, 'deep');
      expect(projection.operations.first.state, OperationState.running);
    },
  );

  test(
    'retired epochs bound lane metadata and reject evicted late reports',
    () {
      final projection = ReaderOperationProjection(recentLimit: 3);
      for (var epoch = 1; epoch <= 100; epoch++) {
        projection.begin(
          operation(
            'attempt-$epoch',
            OperationState.running,
            epoch: epoch,
            scope: 'scope-$epoch',
          ),
        );
        projection.invalidateOwner(OperationOwnerKind.document, epoch);
        expect(projection.retainedLaneCount, 0);
        expect(projection.operations.length, lessThanOrEqualTo(3));
        expect(projection.operations.every((p) => !p.readerBlocking), isTrue);
      }
      expect(
        projection.begin(
          operation('attempt-1', OperationState.failed, scope: 'scope-1'),
        ),
        isFalse,
      );
      expect(
        projection.update(
          operation('attempt-1', OperationState.succeeded, scope: 'scope-1'),
        ),
        isFalse,
      );
    },
  );

  test('current failure survives unrelated terminal history expiry', () {
    final projection = ReaderOperationProjection(recentLimit: 2);
    projection.begin(
      operation('problem', OperationState.failed, scope: 'deep'),
    );
    for (var i = 0; i < 10; i++) {
      projection.begin(
        operation('fast-$i', OperationState.succeeded, attempt: i),
      );
    }
    expect(
      projection.operations.any((p) => p.operationId == 'problem'),
      isTrue,
    );
    expect(projection.operations.length, 3);
    expect(
      projection.begin(operation('fast-0', OperationState.running, attempt: 0)),
      isFalse,
    );
  });

  test('real counters allow changing totals; full counts mean finalizing', () {
    final projection = ReaderOperationProjection();
    projection.begin(operation('a', OperationState.running));
    expect(projection.operations.single.fraction, .5);
    projection.update(operation('a', OperationState.running, total: 8));
    expect(projection.operations.single.fraction, .25);
    projection.update(
      operation('a', OperationState.running, completed: 8, total: 8),
    );
    expect(
      projection.operations.single.visibleState,
      OperationState.finalizing,
    );
    expect(projection.operations.single.state.isTerminal, isFalse);
    for (final counter in [
      operation('a', OperationState.running, total: null),
      operation('a', OperationState.running, completed: -1),
      operation('a', OperationState.running, total: 0),
      operation('a', OperationState.running, completed: 8, total: 3),
    ]) {
      expect(counter.fraction, isNull);
    }
    expect(
      const PreparationProgress(
        stage: PreparationStage.parsing,
        state: PreparationWorkState.working,
        completed: -1,
        total: 2,
        unit: 'words',
      ).fraction,
      isNull,
    );
    expect(
      const TtsResourceProgress(
        stage: 'download',
        message: 'download',
        completed: 8,
        total: 3,
      ).fraction,
      isNull,
    );
    const missing = TtsResourceProgress(
      stage: 'download',
      message: 'download',
      total: 8,
    );
    expect(missing.fraction, isNull);
    expect(missing.toOperation().fraction, isNull);
  });
}
