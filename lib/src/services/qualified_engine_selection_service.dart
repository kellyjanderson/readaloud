import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/speech_engine_catalog.dart';
import 'fish_drama_catalog_store.dart';
import 'runtime_memory_policy.dart';
import 'runtime_memory_registry.dart';

/// Trusted application qualification receipts, never refreshed model metadata.
/// Leave empty until measured additional peaks and sustained reading evidence
/// have been reconciled for the exact checkpoint/runtime/device combination.
const qualifiedModelMemoryRecords = <QualifiedModelMemoryRecord>[];

/// Shared by default selection and actual model-load admission. Both must use
/// the same exact checkpoint/runtime/device receipt; refresh metadata has no
/// authority to manufacture an envelope. No match remains unqualified.
QualifiedMemoryEnvelope? qualifiedMemoryEnvelopeFor({
  required String runtimeIdentity,
  required String deviceIdentity,
  String? engineId,
  Iterable<QualifiedModelMemoryRecord> records = qualifiedModelMemoryRecords,
}) {
  for (final record in records) {
    final envelope = record.envelope;
    if ((engineId == null || record.engineId == engineId) &&
        runtimeIdentity ==
            '$fishDramaCatalogRuntime|${record.checkpointIdentity}' &&
        envelope.runtimeIdentity == runtimeIdentity &&
        envelope.deviceIdentity == deviceIdentity &&
        envelope.additionalPeakBytes > 0 &&
        envelope.evidence.isNotEmpty) {
      return envelope;
    }
  }
  return null;
}

final class QualifiedModelMemoryRecord {
  const QualifiedModelMemoryRecord({
    required this.engineId,
    required this.checkpointIdentity,
    required this.envelope,
  });
  final String engineId, checkpointIdentity;
  final QualifiedMemoryEnvelope envelope;

  /// Intake for reviewed receipts. Hashes and checkpoint estimates are not
  /// measurements. The caller, not a downloaded catalog, supplies trusted JSON.
  static List<QualifiedModelMemoryRecord> fromJson(String json) {
    final raw = jsonDecode(json);
    if (raw is! List || raw.length > 32) {
      throw const FormatException('Invalid qualified memory records');
    }
    final seen = <String>{};
    return List.unmodifiable(
      raw.map((entry) {
        const fields = {
          'engineId',
          'checkpointIdentity',
          'runtimeIdentity',
          'deviceIdentity',
          'additionalPeakBytes',
          'evidence',
        };
        if (entry is! Map<String, dynamic> ||
            entry.length != fields.length ||
            !fields.containsAll(entry.keys) ||
            fields
                .where((key) => key != 'additionalPeakBytes')
                .any(
                  (key) =>
                      entry[key] is! String ||
                      (entry[key] as String).trim().isEmpty,
                ) ||
            !isDramaEngine(entry['engineId'] as String) ||
            entry['additionalPeakBytes'] is! int ||
            entry['additionalPeakBytes'] <= 0 ||
            entry['additionalPeakBytes'] >= RuntimeMemoryPolicy.ceilingBytes) {
          throw const FormatException('Invalid qualified memory record');
        }
        final checkpoint = entry['checkpointIdentity'] as String;
        final runtime = entry['runtimeIdentity'] as String;
        final device = entry['deviceIdentity'] as String;
        final uri = Uri.tryParse(entry['evidence'] as String);
        if (!RegExp(
              r'^mlx-community/[a-zA-Z0-9_-]+@[a-f0-9]{40}$',
            ).hasMatch(checkpoint) ||
            runtime != '$fishDramaCatalogRuntime|$checkpoint' ||
            uri?.scheme != 'https' ||
            uri?.host != 'github.com' ||
            !uri!.path.startsWith('/kellyjanderson/readaloud/') ||
            !seen.add('$runtime|$device')) {
          throw const FormatException(
            'Qualification identity or evidence mismatch',
          );
        }
        return QualifiedModelMemoryRecord(
          engineId: entry['engineId'] as String,
          checkpointIdentity: checkpoint,
          envelope: QualifiedMemoryEnvelope(
            runtimeIdentity: runtime,
            deviceIdentity: device,
            additionalPeakBytes: entry['additionalPeakBytes'] as int,
            evidence: entry['evidence'] as String,
          ),
        );
      }),
    );
  }
}

final class EngineSelectionMemory {
  const EngineSelectionMemory(this.snapshot, this.deviceIdentity);
  final RuntimeMemorySnapshot snapshot;
  final String deviceIdentity;
}

final class DefaultEngineSelection {
  const DefaultEngineSelection(this.engineId, this.reason);
  final String engineId, reason;
}

/// One bounded startup query, owned by ReaderController.initialize. No polling,
/// downloads or background queue. The controller fences disposal after awaiting;
/// explicit preference and launch intent bypass this service entirely.
class QualifiedEngineSelectionService {
  QualifiedEngineSelectionService({
    this.records = qualifiedModelMemoryRecords,
    Future<FishDramaCatalog> Function()? catalogLoader,
    Future<EngineSelectionMemory> Function()? memorySampler,
    DateTime Function()? now,
  }) : _catalogLoader = catalogLoader ?? _loadCatalog,
       _memorySampler = memorySampler ?? _sampleMemory,
       _now = now ?? DateTime.now;
  final List<QualifiedModelMemoryRecord> records;
  final Future<FishDramaCatalog> Function() _catalogLoader;
  final Future<EngineSelectionMemory> Function() _memorySampler;
  final DateTime Function() _now;

  Future<DefaultEngineSelection> select() async {
    try {
      final catalog = await _catalogLoader();
      final memory = await _memorySampler().timeout(const Duration(seconds: 3));
      final envelopes = <String, QualifiedMemoryEnvelope>{};
      final identities = <String, String>{};
      // Accepted order is precision preference, not an acoustic quality claim.
      for (final id in const [
        'fish_drama3',
        'fish_drama3_8bit',
        'fish_drama3_4bit',
      ]) {
        final descriptor = catalog.variants[id]!;
        if (descriptor.profile == null ||
            descriptor.integrityManifest == null) {
          continue;
        }
        final identity =
            '$fishDramaCatalogRuntime|${descriptor.pinnedIdentity}';
        identities[identity] = id;
        final envelope = qualifiedMemoryEnvelopeFor(
          runtimeIdentity: identity,
          deviceIdentity: memory.deviceIdentity,
          engineId: id,
          records: records,
        );
        if (envelope != null) envelopes[identity] = envelope;
      }
      const policy = RuntimeMemoryPolicy();
      final selected = policy.highestQualified(
        qualityOrder: identities.keys,
        envelopes: envelopes,
        deviceIdentity: memory.deviceIdentity,
        sample: memory.snapshot,
        now: _now(),
      );
      if (selected != null) {
        return DefaultEngineSelection(
          identities[selected]!,
          'Automatic default: highest qualified precision fitting measured headroom.',
        );
      }
      final guard = policy.monitor(memory.snapshot, _now());
      return DefaultEngineSelection(
        'kokoro',
        guard.allowed
            ? 'Using Kokoro: no qualified Fish memory envelope for this runtime and device. Choose a model in Settings for monitored qualification.'
            : 'Using Kokoro: ${guard.reason}',
      );
    } catch (error) {
      return DefaultEngineSelection(
        'kokoro',
        'Using Kokoro: qualified model selection is unavailable ($error). Choose an engine in Settings.',
      );
    }
  }

  static Future<FishDramaCatalog> _loadCatalog() async {
    final support = await getApplicationSupportDirectory();
    final store = FishDramaCatalogStore(
      root: Directory('${support.path}/read_aloud/mlx-tts'),
      bundledModelsJson: await rootBundle.loadString(
        'assets/fish_drama_models.json',
      ),
      bundledChecksumsJson: await rootBundle.loadString(
        'assets/fish_drama_model_checksums.json',
      ),
    );
    try {
      // Same offline last-valid lookup as the synthesis owner. An older bundled
      // checkpoint's receipt must never qualify a refreshed checkpoint instead.
      return (await store.load()).catalog;
    } finally {
      await store.close();
    }
  }

  static Future<EngineSelectionMemory> _sampleMemory() async {
    const channel = MethodChannel('read_aloud/mlx_tts_lifecycle');
    final device = await channel.invokeMethod<String>('runtimeDeviceIdentity');
    if (device == null || device.isEmpty) {
      throw StateError('Missing device identity');
    }
    final native = await channel.invokeMapMethod<Object?, Object?>(
      'runtimeMemorySnapshot',
    );
    if (native == null) {
      throw StateError('Missing process-tree memory snapshot');
    }
    return EngineSelectionMemory(
      RuntimeMemoryRegistry.shared.reconcile(native),
      device,
    );
  }
}
