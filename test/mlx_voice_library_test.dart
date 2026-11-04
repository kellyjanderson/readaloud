import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';
import 'package:read_aloud/src/services/mlx_voice_library.dart';
import 'package:read_aloud/src/services/speech_runtime.dart';
import 'package:read_aloud/src/models/engine_capability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all MLX configurations register native runtime and text capabilities',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final engine in [
        'qwen3_tts_1_7b',
        'qwen3_tts_base_1_7b',
        'voxtral_4b',
        'moss_tts_8b',
      ]) {
        expect(
          SpeechRuntimeCapabilities.detectForCurrentPlatform(
            engineId: engine,
          ).isEngineSupported,
          isTrue,
        );
        expect(
          const EngineCapabilityRegistry()
              .lookup(engineId: engine)
              .supportsPlainTextFallback,
          isTrue,
        );
      }
    },
  );

  test(
    'native catalogs expose actual presets without manufactured aliases',
    () {
      expect(mlxVoicesFor('qwen3_tts_1_7b').length, 9);
      expect(mlxVoicesFor('voxtral_4b').length, 20);
      expect(
        mlxVoicesFor('voxtral_4b').singleWhere((v) => v.id == 'fr_male').locale,
        'fr',
      );
      expect(
        mlxVoicesFor(
          'qwen3_tts_1_7b',
        ).singleWhere((v) => v.id == 'Sohee').locale,
        'ko',
      );
    },
  );

  test(
    'reference-capable engines expose 30 distinct verified voice assets',
    () async {
      await MlxVoiceLibrary.load();
      final root = await Directory.systemTemp.createTemp('reference-voices-');
      addTearDown(() => root.delete(recursive: true));
      for (final engine in ['qwen3_tts_base_1_7b', 'moss_tts_8b']) {
        final voices = mlxVoicesFor(engine);
        expect(voices.length, greaterThanOrEqualTo(30));
        expect(voices.where((v) => v.locale.startsWith('en')).length, 30);
        expect(
          voices.where((v) => v.rawValue['gender'] == 'female').length,
          15,
        );
        expect(voices.where((v) => v.rawValue['gender'] == 'male').length, 15);
        expect(voices.map((v) => v.id).toSet().length, voices.length);
        expect(
          voices.map((v) => v.rawValue['sha256']).toSet().length,
          voices.length,
        );
        for (final voice in voices) {
          final data = await rootBundle.load(voice.rawValue['asset'] as String);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          expect(sha256.convert(bytes).toString(), voice.rawValue['sha256']);
          expect(voice.rawValue['referenceText'], isNotEmpty);
        }
      }
      final file = await MlxVoiceLibrary.prepare('library_ava', root);
      await file.writeAsString('corrupted reference');
      final repaired = await MlxVoiceLibrary.prepare('library_ava', root);
      expect(
        sha256.convert(await repaired.readAsBytes()).toString(),
        MlxVoiceLibrary.voice('library_ava').rawValue['sha256'],
      );
      expect(() => MlxVoiceLibrary.voice('library_unknown'), throwsStateError);
    },
  );
}
