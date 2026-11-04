import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A local macOS filesystem generation, not a cryptographic content identity.
/// Dart FileStat rounds timestamps to milliseconds; use the system metadata
/// provider's nanosecond timespecs and inode generation instead. No source bytes
/// are read. Unsupported/unavailable providers miss conservatively.
Future<String?> fileSourceRevision(
  String path, {
  Future<String?> Function(String)? metadataProbe,
}) async {
  if (!Platform.isMacOS && metadataProbe == null) return null;
  try {
    final canonical = await File(path).resolveSymbolicLinks();
    final metadata = await (metadataProbe ?? _macosStatMetadata)(canonical);
    if (metadata == null ||
        !RegExp(
          r'^[0-9]+:[0-9]+:[0-9]+:[0-9]+:[0-9]+\.[0-9]{9}:[0-9]+\.[0-9]{9}:[0-7]+:Regular File$',
        ).hasMatch(metadata)) {
      return null;
    }
    return 'file-stat-v2:${jsonEncode([canonical, metadata])}';
  } on FileSystemException {
    return null;
  } on ProcessException {
    return null;
  }
}

bool isFileSourceRevision(String? revision) =>
    revision?.startsWith('file-stat-v2:') ?? false;

/// One fixed-size subprocess per caller; the admission owner serializes calls.
/// No shell or filename output, one-second deadline, kill and drain on timeout.
Future<String?> _macosStatMetadata(String canonical) async {
  final process = await Process.start(
    '/usr/bin/stat',
    ['-f', '%d:%i:%v:%z:%Fm:%Fc:%p:%HT', canonical],
    environment: const {'LC_ALL': 'C'},
  );
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.drain<void>();
  try {
    final code = await process.exitCode.timeout(const Duration(seconds: 1));
    final metadata = await output;
    await errors;
    return code == 0 ? metadata.trim() : null;
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    await output;
    await errors;
    return null;
  }
}

Future<void> requireFileSourceRevision(String path, String revision) async {
  if (await fileSourceRevision(path) != revision) {
    throw const FileSystemException(
      'The source file changed during preparation. Retry to read its current revision.',
    );
  }
}
