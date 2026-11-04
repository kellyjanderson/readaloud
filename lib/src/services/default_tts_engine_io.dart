import 'dart:io';

import 'package:flutter/foundation.dart';

import 'flutter_tts_engine.dart';
import 'kokoro_tts_engine.dart';
import 'tts_engine.dart';

TtsEngine createPlatformTtsEngine({
  String? engineId,
  int voxtralQuantizationBits = 0,
}) {
  final environmentEngineId = Platform.isMacOS
      ? Platform.environment['READALOUD_TTS_ENGINE']
      : null;
  final mlxEngineId =
      environmentEngineId == null || environmentEngineId.trim().isEmpty
      ? engineId
      : environmentEngineId;
  if (mlxEngineId == 'qwen3_tts_base_1_7b' ||
      mlxEngineId == 'qwen3_tts_1_7b' ||
      mlxEngineId == 'voxtral_4b' ||
      mlxEngineId == 'moss_tts_8b') {
    return KokoroTtsEngine(
      engineId: mlxEngineId!,
      mlxQuantizationBits: mlxEngineId == 'voxtral_4b'
          ? voxtralQuantizationBits
          : 0,
      mlxModelPath: Platform.environment['READALOUD_MLX_TTS_MODEL_PATH'],
      mlxPythonPath: Platform.environment['READALOUD_MLX_PYTHON'] ?? '',
    );
  }
  if (mlxEngineId == 'kokoro' && Platform.isMacOS) {
    return KokoroTtsEngine();
  }
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    return KokoroTtsEngine();
  }
  return FlutterTtsEngine();
}
