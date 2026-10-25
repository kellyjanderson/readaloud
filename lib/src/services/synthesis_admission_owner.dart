import 'dart:async';
import 'dart:collection';
import 'speech_worker_pipeline.dart';

class SynthesisAdmissionCancelled implements Exception {
  const SynthesisAdmissionCancelled();
  @override
  String toString() => 'Synthesis admission cancelled.';
}

/// A non-owning lease may invalidate queued work without waiting for playback
/// lead to permit export. An already active native call still drains.
abstract interface class CancellableSynthesisLease
    implements SpeechWorkerChunkProcessor {
  void cancelPending();
}

/// Main-isolate scheduler. One nonpreemptive native operation, at most one
/// waiting operation per lease. Native handles remain owned by the resident
/// processor. Export leases cannot close that processor.
class SynthesisAdmissionOwner {
  SynthesisAdmissionOwner(
    this.processor, {
    required this.exportMayRun,
    bool Function()? playbackMayRun,
    this.beforeProcess,
  }) : playbackMayRun = playbackMayRun ?? _alwaysAllowPlayback;
  final SpeechWorkerChunkProcessor processor;
  final bool Function() exportMayRun;

  /// Fresh playable-lead credit, checked when reserving the actual processor
  /// slot. Previously queued requests do not carry an irrevocable permission.
  final bool Function() playbackMayRun;
  static bool _alwaysAllowPlayback() => true;

  /// Optional controlled-latency/profiling seam. Default runtime work has no
  /// hook; cancellation is checked again before actual native processing.
  final Future<void> Function()? beforeProcess;
  final Queue<_Admission> _pending = Queue();
  final Set<_Lease> _leases = {};
  bool _running = false;
  bool _closed = false;
  Completer<void>? _drained;
  Future<void>? _shutdown;

  CancellableSynthesisLease lease({required bool export}) {
    if (_closed) throw StateError('Synthesis owner closed.');
    final lease = _Lease(this, export);
    _leases.add(lease);
    return lease;
  }

  Future<T> exclusive<T>(Future<T> Function() action) => _submit(action, false);

  Future<T> _submit<T>(
    Future<T> Function() action,
    bool export, {
    _Lease? lease,
    bool Function()? isCurrent,
    void Function()? onCancelled,
  }) {
    if (_closed) return Future.error(StateError('Synthesis owner closed.'));
    if (_pending.length >= 3 ||
        (lease != null && _pending.any((job) => identical(job.lease, lease)))) {
      return Future.error(StateError('Synthesis admission full.'));
    }
    final current = isCurrent ?? () => true;
    final result = Completer<T>();
    var terminalStarted = false;
    void cancel() {
      if (terminalStarted || result.isCompleted) return;
      terminalStarted = true;
      try {
        onCancelled?.call();
        result.completeError(const SynthesisAdmissionCancelled());
      } catch (error, stack) {
        // An external event callback cannot strand the admission or its drain.
        result.completeError(error, stack);
      }
    }

    _pending.add(
      _Admission(
        export: export,
        lease: lease,
        isCurrent: current,
        cancel: cancel,
        run: () async {
          if (!current()) {
            cancel();
            return;
          }
          try {
            final value = await action();
            if (!current()) {
              cancel();
            } else {
              result.complete(value);
            }
          } catch (error, stack) {
            // Actual processor/cleanup failure remains an error even if the
            // request was concurrently cancelled; cancellation must not hide it.
            if (!current()) {
              try {
                onCancelled?.call();
              } catch (_) {
                // Keep the original native/cleanup error as the owned failure.
              }
            }
            result.completeError(error, stack);
          }
        },
      ),
    );
    signal();
    return result.future;
  }

  void _cancelQueued(bool Function(_Admission job) matches) {
    final cancelled = _pending.where(matches).toList(growable: false);
    for (final job in cancelled) {
      _pending.remove(job);
      job.cancel();
    }
    _settleDrain();
  }

  void signal() {
    // Invalidation must run before checking either the active slot or the
    // export gate. Otherwise a cancelled export may wait forever for lead.
    _cancelQueued((job) => !job.isCurrent());
    if (_closed) {
      _cancelQueued((_) => true);
      return;
    }
    if (_running) return;
    final controls = _pending.where((job) => job.lease == null);
    final playback = _pending.where((job) => !job.export && job.lease != null);
    final exports = _pending.where((job) => job.export);
    // Controls/resources never wait behind audio high-water credit. A gated
    // playback request also cannot hide an independently permitted export.
    final next = controls.isNotEmpty
        ? controls.first
        : playback.isNotEmpty && playbackMayRun()
        ? playback.first
        : exports.isNotEmpty && exportMayRun()
        ? exports.first
        : null;
    if (next == null) return;
    _pending.remove(next);
    _running = true;
    unawaited(
      next.run().whenComplete(() {
        _running = false;
        _settleDrain();
        signal();
      }),
    );
  }

  void _settleDrain() {
    if (_running || _pending.isNotEmpty) return;
    _drained?.complete();
    _drained = null;
  }

  Future<void> drain() {
    if (!_running && _pending.isEmpty) return Future.value();
    return (_drained ??= Completer<void>()).future;
  }

  Future<void> shutdown() => _shutdown ??= _close();
  Future<void> _close() async {
    _closed = true;
    for (final lease in _leases.toList(growable: false)) {
      lease._closed = true;
      lease.cancelPending();
    }
    _cancelQueued((_) => true);
    await drain();
    await processor.dispose();
  }
}

class _Admission {
  _Admission({
    required this.export,
    required this.lease,
    required this.isCurrent,
    required this.run,
    required this.cancel,
  });
  final bool export;
  final _Lease? lease;
  final bool Function() isCurrent;
  final Future<void> Function() run;
  final void Function() cancel;
}

class _Lease implements CancellableSynthesisLease {
  _Lease(this.owner, this.export);
  final SynthesisAdmissionOwner owner;
  final bool export;
  final Set<Future<void>> _jobs = {};
  int _epoch = 0;
  bool _closed = false;
  Future<void>? _shutdown;

  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
  ) {
    if (_closed) return Future.error(StateError('Synthesis lease closed.'));
    final epoch = _epoch;
    bool current() => !_closed && epoch == _epoch;
    var cancelledEventSent = false;
    void emitCancelled() {
      if (cancelledEventSent) return;
      cancelledEventSent = true;
      emit(
        SpeechWorkerEvent(
          type: SpeechWorkerEventType.cancelled,
          sessionId: request.sessionId,
          generationId: request.generationId,
          chunkId: request.chunkId,
          emittedAt: DateTime.now().toUtc(),
          stage: 'cancelled',
        ),
      );
    }

    final future = owner._submit(
      () async {
        final beforeProcess = owner.beforeProcess;
        if (beforeProcess != null) await beforeProcess();
        if (!current()) return;
        await owner.processor.process(request, (event) {
          if (current()) emit(event);
        });
      },
      export,
      lease: this,
      isCurrent: current,
      onCancelled: emitCancelled,
    );
    _jobs.add(future);
    unawaited(
      future.then<void>(
        (_) {
          _jobs.remove(future);
        },
        onError: (Object error, StackTrace stack) {
          _jobs.remove(future);
        },
      ),
    );
    return future;
  }

  @override
  void cancelPending() {
    ++_epoch;
    owner._cancelQueued((job) => identical(job.lease, this));
    owner.signal();
  }

  @override
  Future<void> dispose() => _shutdown ??= _close();
  Future<void> _close() async {
    _closed = true;
    cancelPending();
    Object? failure;
    StackTrace? failureStack;
    for (final job in _jobs.toList(growable: false)) {
      try {
        await job;
      } on SynthesisAdmissionCancelled {
        // Expected cancellation is already a terminal event/future.
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    owner._leases.remove(this);
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }
}
