import 'dart:io';

import 'package:flutter/services.dart';

/// macOS's maintained same-volume staging facility, scoped to one export.
/// The destination must already be authorized (normally by NSSavePanel).
/// No broader directory grant or direct-write/cross-volume fallback is used.
class RadocExportStaging {
  const RadocExportStaging();

  static const _channel = MethodChannel('read_aloud/document_access');

  Future<Directory> createStage(File destination) async {
    final path = await _channel.invokeMethod<String>('createRadocExportStage', {
      'path': destination.absolute.path,
    });
    if (path == null || path.isEmpty || !path.startsWith('/')) {
      throw const FileSystemException(
        'Could not allocate a same-volume audio-book staging directory.',
      );
    }
    return Directory(path);
  }
}
