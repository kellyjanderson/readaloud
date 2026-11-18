import 'dart:io';

import 'package:flutter/services.dart';

/// Native-owned same-volume allocation for one WAV/related-JSON transaction.
class AudioExportStage {
  const AudioExportStage({required this.ownerId, required this.directory});
  final String ownerId;
  final Directory directory;
}

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

  Future<AudioExportStage> createAudioStage(File destination) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'createAudioExportStage',
      {'path': destination.absolute.path},
    );
    final id = result?['ownerId'];
    final path = result?['path'];
    if (id is! String ||
        id.isEmpty ||
        path is! String ||
        !path.startsWith('/')) {
      throw const FileSystemException('Could not prepare a safe audio export.');
    }
    return AudioExportStage(ownerId: id, directory: Directory(path));
  }

  /// The native owner derives both destinations from its authorized WAV URL;
  /// callers cannot substitute a sidecar or stage path at publication time.
  Future<void> publishAudioPair(AudioExportStage stage) => _channel
      .invokeMethod('publishAudioExportPair', {'ownerId': stage.ownerId});

  Future<void> releaseAudioStage(AudioExportStage stage) => _channel
      .invokeMethod('releaseAudioExportStage', {'ownerId': stage.ownerId});
}
