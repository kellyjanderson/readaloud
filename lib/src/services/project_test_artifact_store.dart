import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Directory> resolveProjectTestArtifactDirectory(
  String subdirectoryName,
) async {
  final projectRoot = _findProjectRoot();
  final baseDirectory = projectRoot ?? await getApplicationSupportDirectory();
  final directory = Directory(
    projectRoot != null
        ? p.join(baseDirectory.path, 'project', 'test-artifacts', subdirectoryName)
        : p.join(baseDirectory.path, subdirectoryName),
  );
  await directory.create(recursive: true);
  return directory;
}

Directory? _findProjectRoot() {
  final envRoot = Platform.environment['READ_ALOUD_PROJECT_ROOT'];
  if (envRoot != null && envRoot.trim().isNotEmpty) {
    final candidate = Directory(envRoot.trim());
    if (_looksLikeProjectRoot(candidate)) {
      return candidate;
    }
  }

  var current = Directory.current.absolute;
  while (true) {
    if (_looksLikeProjectRoot(current)) {
      return current;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      return null;
    }
    current = parent;
  }
}

bool _looksLikeProjectRoot(Directory directory) {
  return File(p.join(directory.path, 'pubspec.yaml')).existsSync() &&
      Directory(p.join(directory.path, 'project')).existsSync();
}
