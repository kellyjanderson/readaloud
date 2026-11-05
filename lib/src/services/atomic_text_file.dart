import 'dart:io';

/// One owner per destination; same-directory rename publishes a flushed file.
/// Callers own admission/revision checks and must not share a destination writer.
Future<void> atomicWriteText(String path, String contents) async {
  final temporary = File('$path.tmp');
  try {
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
