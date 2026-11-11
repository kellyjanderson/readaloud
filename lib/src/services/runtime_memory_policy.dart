import 'dart:math' as math;

enum RuntimeMemoryPressure { normal, warning, critical, unknown }

/// One native sample of the app and every descendant, including attribution.
/// Physical footprint already accounts for native/Metal and resident audio:
/// allocator counters must never be added to this total a second time.
final class RuntimeMemorySnapshot {
  RuntimeMemorySnapshot({
    required this.totalFootprintBytes,
    required this.physicalMemoryBytes,
    required this.availableMemoryBytes,
    required this.pressure,
    required this.complete,
    required this.sampledAt,
    List<int> processIds = const [],
  }) : processIds = List.unmodifiable(processIds);

  factory RuntimeMemorySnapshot.fromMap(Map<Object?, Object?> map) {
    int positive(String key, {bool zero = false}) {
      final value = map[key];
      if (value is! int || value < (zero ? 0 : 1)) {
        throw FormatException('Invalid native memory $key');
      }
      return value;
    }

    final pressure = switch (map['pressure']) {
      'normal' => RuntimeMemoryPressure.normal,
      'warning' => RuntimeMemoryPressure.warning,
      'critical' => RuntimeMemoryPressure.critical,
      _ => RuntimeMemoryPressure.unknown,
    };
    final pids = map['processIds'];
    if (pids is! List ||
        pids.isEmpty ||
        pids.any((pid) => pid is! int || pid <= 0) ||
        pids.toSet().length != pids.length) {
      throw const FormatException('Invalid native memory process tree');
    }
    return RuntimeMemorySnapshot(
      totalFootprintBytes: positive('totalFootprintBytes'),
      physicalMemoryBytes: positive('physicalMemoryBytes'),
      availableMemoryBytes: positive('availableMemoryBytes', zero: true),
      pressure: pressure,
      complete: map['complete'] == true,
      sampledAt: DateTime.fromMicrosecondsSinceEpoch(
        positive('sampledUnixMicros'),
      ),
      processIds: List<int>.unmodifiable(pids.cast<int>()),
    );
  }

  final int totalFootprintBytes, physicalMemoryBytes, availableMemoryBytes;
  final RuntimeMemoryPressure pressure;
  final bool complete;
  final DateTime sampledAt;
  final List<int> processIds;

  Map<String, Object> toMap() => Map.unmodifiable({
    'totalFootprintBytes': totalFootprintBytes,
    'physicalMemoryBytes': physicalMemoryBytes,
    'availableMemoryBytes': availableMemoryBytes,
    'pressure': pressure.name,
    'complete': complete,
    'sampledUnixMicros': sampledAt.microsecondsSinceEpoch,
    'processIds': processIds,
  });
}

/// A reviewed additional admission budget derived from measured observations
/// and a documented margin for an exact runtime/device. It is distinct from an
/// observed peak and does not guarantee every between-sample maximum. Catalog
/// sizing estimates cannot construct or stand in for qualification.
final class QualifiedMemoryEnvelope {
  const QualifiedMemoryEnvelope({
    required this.runtimeIdentity,
    required this.deviceIdentity,
    required this.additionalPeakBytes,
    required this.evidence,
  });
  final String runtimeIdentity, deviceIdentity, evidence;
  final int additionalPeakBytes;
}

final class RuntimeMemoryDecision {
  const RuntimeMemoryDecision(this.allowed, this.reason, this.budgetBytes);
  final bool allowed;
  final String reason;
  final int budgetBytes;
}

/// App-specific policy over platform accounting; no scheduler or allocator.
/// The 1 GB ceiling guard and max(2 GB, 5% RAM) OS reserve are conservative
/// admission margins, not measured guarantees against between-sample peaks.
final class RuntimeMemoryPolicy {
  const RuntimeMemoryPolicy();
  static const ceilingBytes = 100000000000;
  static const ceilingGuardBytes = 1000000000;
  static const maxSampleAge = Duration(seconds: 5);

  int _budget(RuntimeMemorySnapshot sample) => math.max(
    0,
    math.min(
      ceilingBytes - ceilingGuardBytes - sample.totalFootprintBytes,
      sample.availableMemoryBytes -
          math.max(2000000000, sample.physicalMemoryBytes ~/ 20),
    ),
  );

  RuntimeMemoryDecision monitor(RuntimeMemorySnapshot sample, DateTime now) {
    final budget = _budget(sample);
    if (!sample.complete) {
      return RuntimeMemoryDecision(
        false,
        'Complete process-tree memory is unavailable.',
        budget,
      );
    }
    final age = now.difference(sample.sampledAt);
    if (age.isNegative || age > maxSampleAge) {
      return RuntimeMemoryDecision(
        false,
        'Process-tree memory sample is stale.',
        budget,
      );
    }
    if (sample.pressure != RuntimeMemoryPressure.normal) {
      return RuntimeMemoryDecision(
        false,
        'macOS memory pressure is ${sample.pressure.name}. Close other applications or select a smaller model.',
        budget,
      );
    }
    if (sample.totalFootprintBytes >= ceilingBytes - ceilingGuardBytes) {
      return RuntimeMemoryDecision(
        false,
        'Speech runtime reached the 100 GB memory ceiling. Select a smaller model.',
        budget,
      );
    }
    if (budget <= 0) {
      return RuntimeMemoryDecision(
        false,
        'Insufficient measured device headroom. Close other applications or select a smaller model.',
        budget,
      );
    }
    return RuntimeMemoryDecision(
      true,
      'Measured process-tree guardrails satisfied.',
      budget,
    );
  }

  RuntimeMemoryDecision admit({
    required RuntimeMemorySnapshot sample,
    required DateTime now,
    required String runtimeIdentity,
    required String deviceIdentity,
    QualifiedMemoryEnvelope? envelope,
    bool explicitQualification = false,
    int? sizingEstimateBytes,
  }) {
    final guard = monitor(sample, now);
    if (!guard.allowed) return guard;
    final qualified =
        envelope != null &&
        envelope.runtimeIdentity == runtimeIdentity &&
        envelope.deviceIdentity == deviceIdentity &&
        envelope.additionalPeakBytes > 0 &&
        envelope.evidence.isNotEmpty;
    if (!qualified && !explicitQualification) {
      return RuntimeMemoryDecision(
        false,
        'Memory envelope requires qualification for this runtime and device.',
        guard.budgetBytes,
      );
    }
    final required = qualified
        ? envelope.additionalPeakBytes
        : sizingEstimateBytes;
    if (required == null || required <= 0) {
      return RuntimeMemoryDecision(
        false,
        'A bounded sizing estimate is required for explicit memory qualification.',
        guard.budgetBytes,
      );
    }
    if (required > guard.budgetBytes) {
      return RuntimeMemoryDecision(
        false,
        'Selected model exceeds measured device headroom or the 100 GB total-runtime ceiling. Select a smaller model.',
        guard.budgetBytes,
      );
    }
    return RuntimeMemoryDecision(
      true,
      qualified
          ? 'Qualified memory envelope fits measured headroom.'
          : 'Explicit monitored qualification only; sizing estimate is not a measured envelope.',
      guard.budgetBytes,
    );
  }

  /// Caller supplies quality order from accepted policy, never parameter count.
  /// A missing envelope leaves that candidate unavailable; no implicit download.
  String? highestQualified({
    required Iterable<String> qualityOrder,
    required Map<String, QualifiedMemoryEnvelope> envelopes,
    required String deviceIdentity,
    required RuntimeMemorySnapshot sample,
    required DateTime now,
  }) {
    for (final identity in qualityOrder) {
      if (admit(
        sample: sample,
        now: now,
        runtimeIdentity: identity,
        deviceIdentity: deviceIdentity,
        envelope: envelopes[identity],
      ).allowed) {
        return identity;
      }
    }
    return null;
  }
}
