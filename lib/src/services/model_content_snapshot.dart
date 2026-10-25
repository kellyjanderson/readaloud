import 'dart:io';

import 'package:crypto/crypto.dart';

/// Native inference opens exactly the private bytes whose digest was bound.
/// Copy first, hash the copy, and never open the mutable source path afterward.
class ModelContentSnapshot {
  const ModelContentSnapshot(this.path, this.digest);
  final String path;
  final String digest;

  static Future<ModelContentSnapshot> capture(
    String sourcePath,
    Directory root,
  ) async {
    await root.create(recursive: true);
    final stage = await root.createTemp('.stage-');
    try {
      final copy = await File(sourcePath).copy('${stage.path}/model.onnx');
      if (await copy.length() == 0) throw StateError('Missing model asset.');
      final digest = (await sha256.bind(copy.openRead()).first).toString();
      final bucket = Directory('${root.path}/$digest');
      if (await bucket.exists()) {
        final existing = File('${bucket.path}/model.onnx');
        if (await existing.exists() &&
            (await sha256.bind(existing.openRead()).first).toString() ==
                digest) {
          return ModelContentSnapshot(existing.path, digest);
        }
        throw StateError('Immutable model snapshot was modified.');
      }
      try {
        await stage.rename(bucket.path);
      } on FileSystemException {
        // Another resident owner may have published identical bytes.
        final existing = File('${bucket.path}/model.onnx');
        if (!await existing.exists() ||
            (await sha256.bind(existing.openRead()).first).toString() !=
                digest) {
          rethrow;
        }
      }
      return ModelContentSnapshot('${bucket.path}/model.onnx', digest);
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }
}
