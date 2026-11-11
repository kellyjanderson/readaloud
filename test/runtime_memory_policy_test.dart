import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/runtime_memory_policy.dart';
import 'package:read_aloud/src/services/runtime_memory_registry.dart';

void main() {
  const policy = RuntimeMemoryPolicy();
  final now = DateTime(2026, 11, 11);
  RuntimeMemorySnapshot sample({
    int total = 10000000000,
    int available = 100000000000,
    int physical = 128000000000,
    bool complete = true,
    RuntimeMemoryPressure pressure = RuntimeMemoryPressure.normal,
    DateTime? at,
  }) => RuntimeMemorySnapshot(
    totalFootprintBytes: total,
    physicalMemoryBytes: physical,
    availableMemoryBytes: available,
    pressure: pressure,
    complete: complete,
    sampledAt: at ?? now,
    processIds: const [1, 2, 3],
  );
  QualifiedMemoryEnvelope envelope(
    String id,
    int bytes, {
    String device = 'm5-128',
  }) => QualifiedMemoryEnvelope(
    runtimeIdentity: id,
    deviceIdentity: device,
    additionalPeakBytes: bytes,
    evidence: 'bounded-receipt',
  );

  test('ceiling covers app, attribution and TTS together with a guard', () {
    final result = policy.admit(
      sample: sample(total: 30000000000),
      now: now,
      runtimeIdentity: 'bf16@revision',
      deviceIdentity: 'm5-128',
      envelope: envelope('bf16@revision', 70000000000),
    );
    expect(result.allowed, false);
    expect(result.budgetBytes, 69000000000);
  });
  test('OS headroom and reserve constrain admission independently of RAM', () {
    final result = policy.admit(
      sample: sample(available: 40000000000),
      now: now,
      runtimeIdentity: '8bit',
      deviceIdentity: 'm5-128',
      envelope: envelope('8bit', 35000000000),
    );
    expect(result.allowed, false);
    expect(result.budgetBytes, 33600000000);
  });
  test(
    'unknown, mismatched and estimate-only envelopes cannot select a default',
    () {
      expect(
        policy.highestQualified(
          qualityOrder: ['bf16', '8bit'],
          envelopes: {
            'bf16': envelope('bf16', 80000000000, device: 'another-mac'),
          },
          deviceIdentity: 'm5-128',
          sample: sample(),
          now: now,
        ),
        isNull,
      );
      expect(
        policy
            .admit(
              sample: sample(),
              now: now,
              runtimeIdentity: 'bf16',
              deviceIdentity: 'm5-128',
              sizingEstimateBytes: 80000000000,
            )
            .allowed,
        false,
      );
    },
  );
  test(
    'quality order chooses only exact measured runtime/device envelopes',
    () {
      expect(
        policy.highestQualified(
          qualityOrder: ['bf16', '8bit', '4bit'],
          envelopes: {
            'bf16': envelope('bf16', 95000000000),
            '8bit': envelope('8bit', 48000000000),
            '4bit': envelope('4bit', 30000000000),
          },
          deviceIdentity: 'm5-128',
          sample: sample(),
          now: now,
        ),
        '8bit',
      );
    },
  );
  test(
    'explicit qualification retains choice but discloses estimate status',
    () {
      final result = policy.admit(
        sample: sample(),
        now: now,
        runtimeIdentity: 'bf16',
        deviceIdentity: 'm5-128',
        explicitQualification: true,
        sizingEstimateBytes: 80000000000,
      );
      expect(result.allowed, true);
      expect(result.reason, contains('not a measured envelope'));
      expect(
        policy
            .admit(
              sample: sample(physical: 24000000000, available: 20000000000),
              now: now,
              runtimeIdentity: '4bit',
              deviceIdentity: 'm3-24',
              explicitQualification: true,
              sizingEstimateBytes: 30000000000,
            )
            .allowed,
        false,
      );
    },
  );
  test('incomplete, stale, future and nonnormal pressure fail closed', () {
    final bad = [
      sample(complete: false),
      sample(at: now.subtract(const Duration(seconds: 6))),
      sample(at: now.add(const Duration(seconds: 1))),
      for (final pressure in RuntimeMemoryPressure.values.where(
        (p) => p != RuntimeMemoryPressure.normal,
      ))
        sample(pressure: pressure),
    ];
    for (final value in bad) {
      expect(policy.monitor(value, now).allowed, false);
    }
  });

  Map<Object?, Object?> native({
    List<int> pids = const [1, 2, 3],
    List<Map<String, int>>? records,
    bool enumeration = true,
  }) => {
    'totalFootprintBytes': 1000,
    'physicalMemoryBytes': 128000000000,
    'availableMemoryBytes': 100000000000,
    'pressure': 'normal',
    'complete': false,
    'enumerationComplete': enumeration,
    'processIds': pids,
    'processes':
        records ??
        [
          {'pid': 1, 'footprintBytes': 1000},
        ],
    'sampledUnixMicros': DateTime.now().microsecondsSinceEpoch,
  };
  test('known self telemetry fills denied TTS and attribution exactly once', () {
    final registry = RuntimeMemoryRegistry();
    final tts = registry.register(2), attribution = registry.register(3);
    registry.update(2, tts, 2000);
    registry.update(3, attribution, 3000);
    final result = registry.reconcile(native());
    expect(result.complete, true);
    expect(result.totalFootprintBytes, 6000);
    // Prefer the native record for a PID already counted, never add telemetry.
    expect(
      registry
          .reconcile(
            native(
              records: [
                {'pid': 1, 'footprintBytes': 1000},
                {'pid': 2, 'footprintBytes': 2500},
              ],
            ),
          )
          .totalFootprintBytes,
      6500,
    );
  });
  test(
    'unknown descendants, missing samples and denied enumeration remain incomplete',
    () {
      final registry = RuntimeMemoryRegistry();
      registry.register(2);
      expect(registry.reconcile(native()).complete, false);
      expect(registry.reconcile(native(pids: [1])).complete, false);
      expect(
        registry.reconcile(native(pids: [1], enumeration: false)).complete,
        false,
      );
    },
  );
  test('retired PID telemetry and removal cannot affect replacement', () {
    final registry = RuntimeMemoryRegistry();
    final old = registry.register(2);
    registry.update(2, old, 2000);
    registry.remove(2, old);
    final current = registry.register(2);
    registry.update(2, current, 3000);
    registry.update(2, old, 9999999);
    registry.remove(2, old);
    final result = registry.reconcile(native(pids: [1, 2]));
    expect(result.complete, true);
    expect(result.totalFootprintBytes, 4000);
  });
  test('delayed stdout cannot refresh already-stale child telemetry', () {
    final registry = RuntimeMemoryRegistry();
    final token = registry.register(2);
    registry.update(
      2,
      token,
      2000,
      sampledAt: DateTime.now().subtract(const Duration(seconds: 6)),
    );
    expect(registry.reconcile(native(pids: [1, 2])).complete, false);
  });
  test(
    'telemetry expires on a monotonic clock, independently of wall time',
    () {
      var elapsed = Duration.zero;
      final registry = RuntimeMemoryRegistry(monotonicNow: () => elapsed);
      final token = registry.register(2);
      registry.update(2, token, 2000);
      expect(registry.reconcile(native(pids: [1, 2])).complete, true);
      elapsed = const Duration(seconds: 6);
      expect(registry.reconcile(native(pids: [1, 2])).complete, false);
    },
  );
}
