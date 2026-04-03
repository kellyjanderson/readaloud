import 'package:flutter/foundation.dart';

import 'flutter_tts_engine.dart';
import 'kokoro_tts_engine.dart';
import 'tts_engine.dart';

TtsEngine createPlatformTtsEngine() {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    return KokoroTtsEngine();
  }
  return FlutterTtsEngine();
}
