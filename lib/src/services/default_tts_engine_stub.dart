import 'flutter_tts_engine.dart';
import 'tts_engine.dart';

TtsEngine createPlatformTtsEngine({
  String? engineId,
  int voxtralQuantizationBits = 0,
}) => FlutterTtsEngine();
