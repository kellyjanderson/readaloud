import 'runtime_memory_policy.dart';

/// Main-isolate accounting only; no timers, queues or process lifetime owner.
/// Supervisors register before admitting work and remove only after reap. A
/// token identifies a particular child lifetime, so late telemetry/removal for
/// a retired PID cannot mutate a newer registration. Native enumeration remains
/// authoritative for coverage; an unknown descendant is never omitted.
final class RuntimeMemoryRegistry {
  RuntimeMemoryRegistry({Duration Function()? monotonicNow}) {
    final watch = Stopwatch()..start();
    _now = monotonicNow ?? (() => watch.elapsed);
  }
  static final shared = RuntimeMemoryRegistry();
  late final Duration Function() _now;
  final Map<int, _ChildMemory> _children = {};

  Object register(int pid) {
    if (_children.containsKey(pid)) {
      throw StateError('Memory PID already owned');
    }
    final token = Object();
    _children[pid] = _ChildMemory(token);
    return token;
  }

  void update(int pid, Object token, int bytes, {DateTime? sampledAt}) {
    final child = _children[pid];
    if (child == null || !identical(child.token, token)) return;
    if (bytes <= 0) throw const FormatException('Invalid child footprint');
    final sourceAge = sampledAt == null
        ? Duration.zero
        : DateTime.now().difference(sampledAt);
    if (sourceAge.isNegative) {
      throw const FormatException('Future child memory sample');
    }
    child.bytes = bytes;
    // Buffered stdout cannot renew an old sample. Subsequent age is monotonic.
    child.sampledAt = _now() - sourceAge;
  }

  void remove(int pid, Object token) {
    if (identical(_children[pid]?.token, token)) _children.remove(pid);
  }

  RuntimeMemorySnapshot reconcile(Map<Object?, Object?> native) {
    final pids = (native['processIds'] as List).cast<int>().toSet();
    final records = (native['processes'] as List).cast<Map>();
    final measured = <int, int>{};
    for (final record in records) {
      final pid = record['pid'], bytes = record['footprintBytes'];
      if (pid is! int ||
          bytes is! int ||
          bytes <= 0 ||
          !pids.contains(pid) ||
          measured.containsKey(pid)) {
        throw const FormatException('Invalid native memory process record');
      }
      measured[pid] = bytes;
    }
    var complete =
        native['enumerationComplete'] == true &&
        pids.containsAll(_children.keys);
    for (final pid in pids) {
      if (measured.containsKey(pid)) continue;
      final child = _children[pid];
      if (child == null ||
          child.bytes == null ||
          child.sampledAt == null ||
          _now() - child.sampledAt! > RuntimeMemoryPolicy.maxSampleAge) {
        complete = false;
      } else {
        measured[pid] = child.bytes!;
      }
    }
    return RuntimeMemorySnapshot.fromMap({
      ...native,
      'totalFootprintBytes': measured.values.fold<int>(0, (a, b) => a + b),
      'complete': complete,
    });
  }
}

final class _ChildMemory {
  _ChildMemory(this.token);
  final Object token;
  int? bytes;
  Duration? sampledAt;
}
