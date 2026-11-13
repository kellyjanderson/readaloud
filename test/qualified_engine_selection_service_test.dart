import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:read_aloud/src/models/speech_engine_catalog.dart';
import 'package:read_aloud/src/services/fish_drama_catalog_store.dart';
import 'package:read_aloud/src/services/qualified_engine_selection_service.dart';
import 'package:read_aloud/src/services/runtime_memory_policy.dart';

void main() {
  test(
    'checked-in admission budgets have exact local evidence and current pins',
    () async {
      final current = FishDramaCatalog.fromJson(
        modelsJson: await File('assets/fish_drama_models.json').readAsString(),
        checksumsJson: await File(
          'assets/fish_drama_model_checksums.json',
        ).readAsString(),
      );
      for (final record in qualifiedModelMemoryRecords) {
        expect(
          record.checkpointIdentity,
          current.variants[record.engineId]!.pinnedIdentity,
        );
        expect(
          record.envelope.runtimeIdentity,
          '$fishDramaCatalogRuntime|${record.checkpointIdentity}',
        );
        final uri = Uri.parse(record.envelope.evidence);
        final relative = uri.pathSegments.skip(4).join('/');
        expect(relative, startsWith('project/test-artifacts/'));
        final evidence = jsonDecode(await File(relative).readAsString()) as Map;
        expect(evidence['deviceIdentity'], record.envelope.deviceIdentity);
        final key = switch (record.engineId) {
          'fish_drama3' => 'bf16',
          'fish_drama3_8bit' => '8bit',
          _ => '4bit',
        };
        final measured = evidence['variants'][key] as Map;
        expect(
          record.envelope.additionalPeakBytes,
          measured['admissionAdditionalEnvelopeBytes'],
        );
        expect(
          record.envelope.additionalPeakBytes,
          greaterThan(measured['observedWholeTreePeakBytes'] as int),
        );
      }
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 11);
  const device = 'Apple M5 Max/137438953472';
  FishDramaCatalog catalog() => FishDramaCatalog.fromJson(
    modelsJson: File('assets/fish_drama_models.json').readAsStringSync(),
    checksumsJson: File(
      'assets/fish_drama_model_checksums.json',
    ).readAsStringSync(),
  );
  EngineSelectionMemory memory({
    int available = 100000000000,
    RuntimeMemoryPressure pressure = RuntimeMemoryPressure.normal,
  }) => EngineSelectionMemory(
    RuntimeMemorySnapshot(
      totalFootprintBytes: 2000000000,
      physicalMemoryBytes: 137438953472,
      availableMemoryBytes: available,
      pressure: pressure,
      complete: true,
      sampledAt: now,
    ),
    device,
  );
  Map<String, Object> receipt(
    String id,
    int peak, {
    String? onDevice,
    String? checkpoint,
  }) {
    final pin = checkpoint ?? catalog().variants[id]!.pinnedIdentity;
    return {
      'engineId': id,
      'checkpointIdentity': pin,
      'runtimeIdentity': '$fishDramaCatalogRuntime|$pin',
      'deviceIdentity': onDevice ?? device,
      'additionalPeakBytes': peak,
      'evidence':
          'https://github.com/kellyjanderson/readaloud/issues/112#issuecomment-123',
    };
  }

  QualifiedEngineSelectionService service(
    List<Map<String, Object>> receipts, {
    EngineSelectionMemory? sample,
  }) => QualifiedEngineSelectionService(
    records: QualifiedModelMemoryRecord.fromJson(jsonEncode(receipts)),
    catalogLoader: () async => catalog(),
    memorySampler: () async => sample ?? memory(),
    now: () => now,
  );

  test(
    'unknown envelopes never become a default from estimates or digests',
    () async {
      final result = await service([]).select();
      expect(result.engineId, 'kokoro');
      expect(result.reason, contains('no qualified Fish memory envelope'));
    },
  );
  test(
    'selects highest qualified precision that fits actual measured headroom',
    () async {
      final receipts = [
        receipt('fish_drama3', 80000000000),
        receipt('fish_drama3_8bit', 48000000000),
        receipt('fish_drama3_4bit', 30000000000),
      ];
      expect((await service(receipts).select()).engineId, 'fish_drama3');
      expect(
        (await service(
          receipts,
          sample: memory(available: 60000000000),
        ).select()).engineId,
        'fish_drama3_8bit',
      );
      expect(
        (await service(
          receipts,
          sample: memory(available: 40000000000),
        ).select()).engineId,
        'fish_drama3_4bit',
      );
    },
  );
  test('exact device and checkpoint identity required', () async {
    final result = await service([
      receipt('fish_drama3', 1000000000, onDevice: 'Apple M3/17179869184'),
      receipt(
        'fish_drama3_8bit',
        1000000000,
        checkpoint: 'mlx-community/fish-audio-drama-3-8bit@${'a' * 40}',
      ),
    ]).select();
    expect(result.engineId, 'kokoro');
  });

  test(
    'actual-load lookup requires exact runtime, checkpoint, device and optional engine',
    () {
      final records = QualifiedModelMemoryRecord.fromJson(
        jsonEncode([receipt('fish_drama3', 80000000000)]),
      );
      final identity = records.single.envelope.runtimeIdentity;
      expect(
        qualifiedMemoryEnvelopeFor(
          runtimeIdentity: identity,
          deviceIdentity: device,
          engineId: 'fish_drama3',
          records: records,
        ),
        same(records.single.envelope),
      );
      expect(
        qualifiedMemoryEnvelopeFor(
          runtimeIdentity: identity,
          deviceIdentity: 'other Mac',
          records: records,
        ),
        isNull,
      );
      expect(
        qualifiedMemoryEnvelopeFor(
          runtimeIdentity: '$identity-other',
          deviceIdentity: device,
          records: records,
        ),
        isNull,
      );
      expect(
        qualifiedMemoryEnvelopeFor(
          runtimeIdentity: identity,
          deviceIdentity: device,
          engineId: 'fish_drama3_8bit',
          records: records,
        ),
        isNull,
      );
    },
  );
  test('memory pressure refuses defaults even with trusted receipts', () async {
    final result = await service([
      receipt('fish_drama3', 1000000000),
    ], sample: memory(pressure: RuntimeMemoryPressure.warning)).select();
    expect(result.engineId, 'kokoro');
    expect(result.reason, contains('memory pressure'));
  });
  test('unavailable native accounting discloses fallback', () async {
    final result = await QualifiedEngineSelectionService(
      catalogLoader: () async => catalog(),
      memorySampler: () async => throw StateError('native unavailable'),
    ).select();
    expect(result.engineId, 'kokoro');
    expect(result.reason, contains('native unavailable'));
  });
  test(
    'production sampler reconciles native accounting on lifecycle channel',
    () async {
      const channel = MethodChannel('read_aloud/mlx_tts_lifecycle');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'runtimeDeviceIdentity') return device;
            return {
              ...memory().snapshot.toMap(),
              'processIds': [123],
              'enumerationComplete': true,
              'processes': [
                {'pid': 123, 'footprintBytes': 2000000000},
              ],
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final selection = await QualifiedEngineSelectionService(
        records: QualifiedModelMemoryRecord.fromJson(
          jsonEncode([receipt('fish_drama3', 80000000000)]),
        ),
        catalogLoader: () async => catalog(),
        now: () => now,
      ).select();
      expect(selection.engineId, 'fish_drama3');
      expect(calls, ['runtimeDeviceIdentity', 'runtimeMemorySnapshot']);
    },
  );
  for (final mutation in <void Function(Map<String, Object>)>[
    (r) => r['evidence'] = 'estimated peak',
    (r) => r['evidence'] = 'https://example.com/claim',
    (r) => r['additionalPeakBytes'] = 0,
    (r) => r['runtimeIdentity'] = 'other-runtime',
    (r) => r['checkpointIdentity'] = 'main',
    (r) => r['engineId'] = 'unknown',
    (r) => r['execute'] = 'custom.py',
  ]) {
    test('invalid qualification receipt is rejected $mutation', () {
      final value = receipt('fish_drama3', 80000000000);
      mutation(value);
      expect(
        () => QualifiedModelMemoryRecord.fromJson(jsonEncode([value])),
        throwsFormatException,
      );
    });
  }
}
