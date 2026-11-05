import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'modernbooknlp_provider.dart';

/// Packaged code is immutable; all models/helper copies belong to stable App
/// Support locations. Neither debug mode nor executable path is a model identity.
Future<ModernBookNlpProvider> createModernBookNlpProvider() async {
  final resources = p.normalize(
    p.join(p.dirname(Platform.resolvedExecutable), '..', 'Resources'),
  );
  final python = p.join(resources, 'modernbooknlp-python', 'bin', 'python3.11');
  if (!await File(python).exists()) {
    throw StateError(
      'This build does not include the ModernBookNLP runtime. Install a build with ModernBookNLP support, then retry.',
    );
  }
  final support = await getApplicationSupportDirectory();
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
  return ModernBookNlpProvider(
    pythonPath: python,
    helperPath: p.join(helpers.path, 'modernbooknlp_worker.py'),
    runtimePath: p.join(root.path, 'models'),
  );
}
