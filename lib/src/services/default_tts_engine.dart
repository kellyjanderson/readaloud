import 'tts_engine.dart';
import 'default_tts_engine_stub.dart'
    if (dart.library.io) 'default_tts_engine_io.dart';

TtsEngine createDefaultTtsEngine() => createPlatformTtsEngine();
