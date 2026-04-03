import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const String _bundledModelAssetPath = 'assets/kokoro/model/kokoro-v1.0.onnx';

class KokoroAssetBundle {
  const KokoroAssetBundle({
    required this.isReady,
    required this.message,
    this.modelPath,
    this.voicesDirectory,
    this.cacheDirectory,
  });

  final bool isReady;
  final String? message;
  final String? modelPath;
  final String? voicesDirectory;
  final String? cacheDirectory;
}

Future<KokoroAssetBundle> prepareKokoroAssets({
  void Function(String? message)? onStatus,
}) async {
  try {
    final supportDirectory = await getApplicationSupportDirectory();
    final kokoroDirectory = Directory(
      _joinPaths(<String>[supportDirectory.path, 'kokoro']),
    );
    final modelsDirectory = Directory(
      _joinPaths(<String>[kokoroDirectory.path, 'models']),
    );
    final voicesDirectory = Directory(
      _joinPaths(<String>[kokoroDirectory.path, 'voices']),
    );
    final cacheDirectory = Directory(
      _joinPaths(<String>[kokoroDirectory.path, 'cache']),
    );

    await Future.wait(<Future<void>>[
      modelsDirectory.create(recursive: true),
      voicesDirectory.create(recursive: true),
      cacheDirectory.create(recursive: true),
    ]);

    final modelFile = File(
      _joinPaths(<String>[modelsDirectory.path, 'kokoro-v1.0.onnx']),
    );

    await _seedModelFromLegacyRuntime(modelFile);
    if (!await modelFile.exists() || await modelFile.length() == 0) {
      onStatus?.call('Preparing the bundled Kokoro speech model...');
      await _copyAssetToFile(_bundledModelAssetPath, modelFile);
    }

    if (!await modelFile.exists() || await modelFile.length() == 0) {
      return const KokoroAssetBundle(
        isReady: false,
        message: 'The bundled Kokoro speech model is missing.',
      );
    }

    onStatus?.call(null);
    return KokoroAssetBundle(
      isReady: true,
      message: null,
      modelPath: modelFile.path,
      voicesDirectory: voicesDirectory.path,
      cacheDirectory: cacheDirectory.path,
    );
  } catch (error) {
    return KokoroAssetBundle(
      isReady: false,
      message: 'Kokoro setup failed: $error',
    );
  }
}

Future<void> _seedModelFromLegacyRuntime(File modelFile) async {
  final homeDirectory =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (homeDirectory == null || homeDirectory.isEmpty) {
    return;
  }

  final legacyModel = File(
    _joinPaths(<String>[
      homeDirectory,
      '.read-aloud',
      'kokoro-runtime',
      'models',
      'kokoro-v1.0.onnx',
    ]),
  );

  if (!await modelFile.exists() && await legacyModel.exists()) {
    await legacyModel.copy(modelFile.path);
  }
}

Future<void> _copyAssetToFile(String assetKey, File destination) async {
  final data = await rootBundle.load(assetKey);
  await destination.parent.create(recursive: true);
  await destination.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
}

String _joinPaths(List<String> parts) {
  return parts.join(Platform.pathSeparator);
}
