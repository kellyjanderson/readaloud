/// Main-isolate presentation of producer-owned work. No timers infer outcomes.
enum OperationState {
  queued,
  running,
  waiting,
  idleDemand,
  finalizing,
  succeeded,
  failed,
  cancelled;

  bool get isTerminal =>
      this == succeeded || this == failed || this == cancelled;
}

enum OperationOwnerKind { document, readingStage, model }

enum OperationRecoveryAction { cancel, retry, resume, clear }

class ReaderOperation {
  ReaderOperation({
    required this.operationId,
    required this.ownerKind,
    required this.ownerEpoch,
    required this.stage,
    required this.state,
    required this.completedUnits,
    required this.unit,
    required this.updatedAt,
    this.totalUnits,
    this.completedKnown = true,
    this.attempt = 0,
    this.discoveredUnits,
    this.scope = '',
    this.message,
    this.error,
    this.retryOf,
    this.readerBlocking = true,
    Iterable<OperationRecoveryAction> recoveryActions = const [],
  }) : recoveryActions = List.unmodifiable(recoveryActions);

  final String operationId;
  final OperationOwnerKind ownerKind;
  final int ownerEpoch;
  final String stage;
  final String scope;
  final OperationState state;
  final int completedUnits;
  final int? totalUnits;
  final bool completedKnown;

  /// Monotonic within a stable lane and owner epoch, independent of history.
  final int attempt;
  final int? discoveredUnits;
  final String unit;
  final DateTime updatedAt;
  final String? message;
  final String? error;
  final String? retryOf;
  final bool readerBlocking;
  final List<OperationRecoveryAction> recoveryActions;

  String get lane => '${ownerKind.name}:$stage:$scope';
  String get key => '$operationId:$stage:$scope';
  bool get hasValidCounter =>
      completedKnown &&
      completedUnits >= 0 &&
      (totalUnits == null ||
          (totalUnits! > 0 && completedUnits <= totalUnits!));
  double? get fraction => hasValidCounter && totalUnits != null
      ? completedUnits / totalUnits!
      : null;
  OperationState get visibleState =>
      state == OperationState.running && fraction == 1
      ? OperationState.finalizing
      : state;

  ReaderOperation withState(
    OperationState value, {
    String? retryOf,
    bool? readerBlocking,
    Iterable<OperationRecoveryAction>? recoveryActions,
    DateTime? updatedAt,
  }) => ReaderOperation(
    operationId: operationId,
    ownerKind: ownerKind,
    ownerEpoch: ownerEpoch,
    stage: stage,
    scope: scope,
    state: value,
    completedUnits: completedUnits,
    totalUnits: totalUnits,
    completedKnown: completedKnown,
    attempt: attempt,
    discoveredUnits: discoveredUnits,
    unit: unit,
    updatedAt: updatedAt ?? DateTime.now(),
    message: message,
    error: error,
    retryOf: retryOf ?? this.retryOf,
    readerBlocking: readerBlocking ?? this.readerBlocking,
    recoveryActions: recoveryActions ?? this.recoveryActions,
  );
}

/// Bounded latest-state projection, not a task scheduler or a second event bus.
/// Callers explicitly admit each new attempt; updates may only reach its lane.
class ReaderOperationProjection {
  ReaderOperationProjection({this.recentLimit = 24});
  final int recentLimit;
  final _latest = <String, ReaderOperation>{};
  final _history = <String, ReaderOperation>{};
  final _ownerEpochs = <OperationOwnerKind, int>{};
  final _invalidThrough = <OperationOwnerKind, int>{};
  int get retainedLaneCount => _latest.length;
  ReaderOperation? currentInLane(String lane) => _latest[lane];

  bool begin(ReaderOperation value) {
    if (value.ownerEpoch <= (_invalidThrough[value.ownerKind] ?? -1) ||
        value.ownerEpoch < (_ownerEpochs[value.ownerKind] ?? -1)) {
      return false;
    }
    if (value.ownerEpoch > (_ownerEpochs[value.ownerKind] ?? -1)) {
      // A new owner epoch invalidates all lanes from the retired owner, even
      // when their visible history has already expired. Within a document the
      // producers use stable stage/pass lanes, never one scope per range.
      for (final previous
          in _latest.values
              .where((p) => p.ownerKind == value.ownerKind)
              .toList()) {
        _history[previous.key] = previous.withState(
          previous.state.isTerminal ? previous.state : OperationState.cancelled,
          readerBlocking: false,
        );
        _latest.remove(previous.lane);
      }
      _ownerEpochs[value.ownerKind] = value.ownerEpoch;
    }
    final previous = _latest[value.lane];
    if (previous != null && value.ownerEpoch < previous.ownerEpoch) {
      return false;
    }
    if (previous != null &&
        previous.key != value.key &&
        value.ownerEpoch == previous.ownerEpoch &&
        value.attempt <= previous.attempt) {
      return false;
    }
    if (previous?.key != value.key && _history.containsKey(value.key)) {
      return false;
    }
    if (previous?.key == value.key) return update(value);
    if (previous != null) {
      _history[previous.key] = previous.withState(
        previous.state.isTerminal ? previous.state : OperationState.cancelled,
        readerBlocking: false,
      );
    }
    _latest[value.lane] = value;
    _history[value.key] = value;
    _trim();
    return true;
  }

  bool update(ReaderOperation value) {
    final previous = _latest[value.lane];
    if (previous == null ||
        previous.key != value.key ||
        previous.ownerEpoch != value.ownerEpoch ||
        previous.state.isTerminal ||
        value.updatedAt.isBefore(previous.updatedAt)) {
      return false;
    }
    _latest[value.lane] = value;
    _history[value.key] = value;
    _trim();
    return true;
  }

  /// Dismiss presentation only. Keep the failed result and terminal latch so
  /// late producer reports cannot revive it or dismiss a replacement attempt.
  bool clearFailure(ReaderOperation expected) {
    final current = _latest[expected.lane];
    if (current == null ||
        current.key != expected.key ||
        current.ownerEpoch != expected.ownerEpoch ||
        current.state != OperationState.failed ||
        !current.readerBlocking ||
        !current.recoveryActions.contains(OperationRecoveryAction.clear)) {
      return false;
    }
    final cleared = current.withState(current.state, readerBlocking: false);
    _latest[current.lane] = cleared;
    _history[current.key] = cleared;
    _trim();
    return true;
  }

  void cancelOwner(OperationOwnerKind owner, {String? exceptStage}) {
    for (final value in _latest.values.toList()) {
      if (value.ownerKind == owner &&
          value.stage != exceptStage &&
          !value.state.isTerminal) {
        update(value.withState(OperationState.cancelled));
      }
    }
  }

  void invalidateOwner(OperationOwnerKind owner, int throughEpoch) {
    cancelOwner(owner);
    _invalidThrough[owner] = throughEpoch;
    for (final value in _latest.values.where((p) => p.ownerKind == owner)) {
      _history[value.key] = value.withState(value.state, readerBlocking: false);
    }
    _latest.removeWhere((_, value) => value.ownerKind == owner);
    _trim();
  }

  void retireOwner(OperationOwnerKind owner) =>
      invalidateOwner(owner, _ownerEpochs[owner] ?? -1);

  void _trim() {
    final terminal =
        _history.values
            .where(
              (v) =>
                  v.state.isTerminal &&
                  !(v.state == OperationState.failed &&
                      _latest[v.lane]?.key == v.key),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final old in terminal.skip(recentLimit)) {
      _history.remove(old.key);
      // Keep the latest terminal latch even after its presentation expires.
    }
  }

  List<ReaderOperation> get operations {
    final values = _history.values.toList()
      ..sort((a, b) {
        final active = (a.state.isTerminal ? 1 : 0).compareTo(
          b.state.isTerminal ? 1 : 0,
        );
        return active != 0 ? active : b.updatedAt.compareTo(a.updatedAt);
      });
    return List.unmodifiable(values);
  }
}
