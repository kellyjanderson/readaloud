import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/fish_drama_catalog_store.dart';

/// Read-only Settings snapshot. Uses the same validated catalog/store as model
/// acquisition, without refreshing the network or starting a download.
Future<Map<String, int?>> loadModelDiskRequirements() async {
  final support = await getApplicationSupportDirectory();
  final store = FishDramaCatalogStore(
    root: Directory('${support.path}/read_aloud/mlx-tts'),
    bundledModelsJson: await rootBundle.loadString(
      'assets/fish_drama_models.json',
    ),
    bundledChecksumsJson: await rootBundle.loadString(
      'assets/fish_drama_model_checksums.json',
    ),
    bundledManifestJson: await rootBundle.loadString(
      'assets/fish_drama_catalog_update.json',
    ),
  );
  try {
    final snapshot = await store.load();
    return {
      for (final entry in snapshot.catalog.variants.entries)
        entry.key: entry.value.expectedDiskBytes,
    };
  } finally {
    await store.close();
  }
}

class ModelDiskSpace {
  const ModelDiskSpace(this.availableBytes, this.checkedAt);
  final int availableBytes;
  final DateTime checkedAt;

  static Future<ModelDiskSpace> query() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      throw UnsupportedError('Model volume query requires macOS');
    }
    final raw = await const MethodChannel('read_aloud/mlx_tts_lifecycle')
        .invokeMapMethod<String, Object?>('modelDiskSpace')
        .timeout(const Duration(seconds: 5));
    final bytes = raw?['availableBytes'];
    final micros = raw?['checkedAtUnixMicros'];
    if (bytes is! int || bytes < 0 || micros is! int || micros <= 0) {
      throw const FormatException('No valid disk-space measurement');
    }
    return ModelDiskSpace(bytes, DateTime.fromMicrosecondsSinceEpoch(micros));
  }
}

String _diskBytes(int bytes) =>
    '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB ($bytes bytes)';

/// One query per opening or explicit refresh, no polling. The widget owns one
/// bounded request; FutureBuilder fences disposed/replaced futures. Disk I/O is
/// native utility-queue owned, and catalog parsing uses the existing store worker.
class ModelDiskCapacity extends StatefulWidget {
  const ModelDiskCapacity({
    super.key,
    required this.engineId,
    this.loadRequirements = loadModelDiskRequirements,
    this.querySpace = ModelDiskSpace.query,
  });
  final String engineId;
  final Future<Map<String, int?>> Function() loadRequirements;
  final Future<ModelDiskSpace> Function() querySpace;

  @override
  State<ModelDiskCapacity> createState() => _ModelDiskCapacityState();
}

class _ModelDiskCapacityState extends State<ModelDiskCapacity> {
  late final Future<Map<String, int?>> _requirements;
  late Future<ModelDiskSpace> _space;

  // Observe early failures immediately, before FutureBuilder's next frame
  // subscribes. Its snapshot still receives the original error for display.
  Future<T> _observe<T>(Future<T> future) {
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return future;
  }

  @override
  void initState() {
    super.initState();
    _requirements = _observe(widget.loadRequirements());
    _space = _observe(widget.querySpace());
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Model storage'),
      FutureBuilder<Map<String, int?>>(
        future: _requirements,
        builder: (context, snapshot) {
          final bytes = snapshot.data?[widget.engineId];
          return Text(
            snapshot.connectionState != ConnectionState.done
                ? 'Expected model files: checking catalog…'
                : snapshot.hasError
                ? 'Expected model files: unavailable (catalog could not be read).'
                : bytes == null
                ? 'Expected model files: unknown for this engine.'
                : 'Expected model files: ${_diskBytes(bytes)}.',
          );
        },
      ),
      FutureBuilder<ModelDiskSpace>(
        future: _space,
        builder: (context, snapshot) {
          final pending = snapshot.connectionState != ConnectionState.done;
          final space = snapshot.data;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pending
                    ? 'Available on model-store volume: checking…'
                    : snapshot.hasError || space == null
                    ? 'Available on model-store volume: unavailable. Retry to check.'
                    : 'Available on model-store volume: ${_diskBytes(space.availableBytes)}. Checked ${TimeOfDay.fromDateTime(space.checkedAt).format(context)}.',
              ),
              TextButton(
                onPressed: pending
                    ? null
                    : () => setState(() {
                        _space = _observe(widget.querySpace());
                      }),
                child: const Text('Refresh available space'),
              ),
            ],
          );
        },
      ),
      const Text(
        'Catalog totals describe all required model files, not remaining download bytes. Available space can change; temporary files may require additional space. Disk capacity does not establish memory suitability.',
      ),
    ],
  );
}
