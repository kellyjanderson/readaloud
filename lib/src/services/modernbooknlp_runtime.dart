import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'modernbooknlp_provider.dart';
import 'packaged_python_runtime.dart';

/// Packaged code is immutable; all models/helper copies belong to stable App
/// Support locations. Neither debug mode nor executable path is a model identity.
Future<ModernBookNlpProvider> createModernBookNlpProvider({
  required Future<void> cancelled,
  required String consumerRevision,
  required void Function(Map<String, dynamic>) onProgress,
}) async {
  final resources = p.normalize(
    p.join(p.dirname(Platform.resolvedExecutable), '..', 'Resources'),
  );
  final support = await getApplicationSupportDirectory();
  final lease = PackagedPythonRuntimeOwner.shared.acquire(
    runtimeId: 'modernbooknlp',
    resources: Directory(resources),
    support: support,
    consumerRevision: consumerRevision,
    onProgress: onProgress,
  );
  var obsolete = false;
  unawaited(
    cancelled.then((_) {
      obsolete = true;
      return lease.cancelAndDrain();
    }),
  );
  try {
    final runtime = await lease.runtime;
    if (obsolete) throw const PackagedRuntimeCancelled();
    final root = Directory(p.join(support.path, 'modernbooknlp'));
    final helpers = Directory(p.join(root.path, 'helpers'));
    await helpers.create(recursive: true);
    for (final name in [
      'modernbooknlp_worker.py',
      'modernbooknlp_assets.py',
      'modernbooknlp_models.json',
    ]) {
      final contents = await rootBundle.loadString('assets/$name');
      final file = File(p.join(helpers.path, name));
      if (!await file.exists() || await file.readAsString() != contents) {
        await file.writeAsString(contents, flush: true);
      }
    }
    if (obsolete) throw const PackagedRuntimeCancelled();
    return ModernBookNlpProvider(
      pythonPath: runtime.executable,
      pythonHome: runtime.pythonHome,
      helperPath: p.join(helpers.path, 'modernbooknlp_worker.py'),
      runtimePath: p.join(root.path, 'models'),
    );
  } finally {
    await lease.cancelAndDrain();
  }
}
