import 'dart:async';
import 'dart:collection';
import 'speech_worker_pipeline.dart';

/// Main-isolate scheduler. One nonpreemptive native operation, at most one
/// waiting operation per playback/export runtime. Native handles remain owned
/// by the resident processor. Export leases cannot close that processor.
class SynthesisAdmissionOwner {
  SynthesisAdmissionOwner(this.processor, {required this.exportMayRun});
  final SpeechWorkerChunkProcessor processor;
  final bool Function() exportMayRun;
  final Queue<_Admission> _pending = Queue();
  bool _running = false;
  bool _closed = false;
  Completer<void>? _drained;
  SpeechWorkerChunkProcessor lease({required bool export}) =>
      _Lease(this, export);
  Future<T> exclusive<T>(Future<T> Function() action) => _submit(action, false);
  Future<T> _submit<T>(Future<T> Function() action, bool export) {
    if (_closed) return Future.error(StateError('Synthesis owner closed.'));
    if (_pending.length >= 3) {
      return Future.error(StateError('Synthesis admission full.'));
    }
    final result = Completer<T>();
    _pending.add(
      _Admission(export, () async {
        try {
          result.complete(await action());
        } catch (error, stack) {
          result.completeError(error, stack);
        }
      }),
    );
    signal();
    return result.future;
  }

  void signal() {
    if (_running) return;
    final candidates = _pending.where((job) => !job.export);
    final next = candidates.isNotEmpty
        ? candidates.first
        : (_pending.isNotEmpty && (exportMayRun() || _closed)
              ? _pending.first
              : null);
    if (next == null) return;
    _pending.remove(next);
    _running = true;
    unawaited(
      next.run().whenComplete(() {
        _running = false;
        if (_pending.isEmpty) {
          _drained?.complete();
          _drained = null;
        }
        signal();
      }),
    );
  }

  Future<void> drain() {
    if (!_running && _pending.isEmpty) return Future.value();
    return (_drained ??= Completer<void>()).future;
  }

  Future<void> shutdown() async {
    _closed = true;
    signal();
    await drain();
    await processor.dispose();
  }
}

class _Admission {
  _Admission(this.export, this.run);
  final bool export;
  final Future<void> Function() run;
}

class _Lease implements SpeechWorkerChunkProcessor {
  _Lease(this.owner, this.export);
  final SynthesisAdmissionOwner owner;
  final bool export;
  Future<void>? _active;
  bool _closed = false;
  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
  ) {
    if (_closed) return Future.error(StateError('Synthesis lease closed.'));
    return _active = owner._submit(
      () => owner.processor.process(request, emit),
      export,
    );
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    try {
      await _active;
    } catch (_) {}
  }
}
