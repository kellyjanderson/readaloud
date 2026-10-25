// Bounded real-native errors; no user/runtime asset mutation or hung-work claim.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';
import 'package:read_aloud/src/services/kokoro_assets.dart';
import 'package:read_aloud/src/services/kokoro_model_runner.dart';
import 'package:read_aloud/src/services/kokoro_speech_worker_processor.dart';
import 'package:read_aloud/src/services/kokoro_voice_manager.dart';
import 'package:read_aloud/src/services/kokoro_voice_repository.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 1 || await Directory(args.single).exists()) {
    stderr.writeln('Expected one NEW output directory');
    exit(64);
  }
  final output = Directory(args.single);
  await output.create(recursive: true);
  Future<void> record(String event, Map<String, Object?> fields) async {
    final row = {'event': event, 'rssBytes': ProcessInfo.currentRss, ...fields};
    await File(
      '${output.path}/events.jsonl',
    ).writeAsString('${jsonEncode(row)}\n', mode: FileMode.append, flush: true);
    stdout.writeln('READALOUD_FAILURE ${jsonEncode(row)}');
  }

  try {
    final assets = await prepareKokoroAssets();
    if (!assets.isReady) {
      throw StateError(assets.message ?? 'Assets unavailable');
    }
    final repository = KokoroVoiceRepository(
      voicesDirectory: assets.voicesDirectory!,
    );
    await KokoroVoiceManager(
      voiceRepository: repository,
      cacheDirectory: assets.cacheDirectory!,
    ).initialize();
    final model = File(assets.modelPath!);
    final voice = File('${assets.voicesDirectory}/af_bella.npy');
    Future<Map<String, Object?>> hashes() async => {
      'model': {
        'path': model.path,
        'sha256': (await sha256.bind(model.openRead()).first).toString(),
      },
      'voice': {
        'path': voice.path,
        'sha256': (await sha256.bind(voice.openRead()).first).toString(),
      },
    };
    await record('assets_before', await hashes());
    KokoroSpeechWorkerChunkProcessor processor(
      String modelPath,
      String voicesPath,
    ) => KokoroSpeechWorkerChunkProcessor(
      rootIsolateToken: RootIsolateToken.instance!,
      modelPath: modelPath,
      voicesDirectory: voicesPath,
      generatedAudioDirectory: '${output.path}/unused-audio',
      engineId: 'kokoro',
      engineVersion: 'p2-failure-probe',
    );
    Future<void> expectError(
      String name,
      Future<void> Function() operation,
    ) async {
      Object? observed;
      try {
        await operation();
      } catch (error) {
        observed = error;
      }
      if (observed == null) throw StateError('$name unexpectedly succeeded');
      await record('expected_error', {'case': name, 'error': '$observed'});
    }

    await record('case_start', {'case': 'malformed_model'});
    final malformed = File('${output.path}/malformed.onnx');
    await malformed.writeAsBytes(
      utf8.encode('not an ONNX protobuf model'),
      flush: true,
    );
    final badModel = processor(malformed.path, assets.voicesDirectory!);
    try {
      await expectError('malformed_model', () async {
        await badModel.prepareResources(
          documentId: 'bad-model',
          revision: 1,
          voiceIds: ['af_bella'],
        );
      });
    } finally {
      await badModel.dispose();
    }
    await record('case_complete', {'case': 'malformed_model'});

    await record('case_start', {'case': 'truncated_voice'});
    final privateVoices = Directory('${output.path}/private-voices');
    await privateVoices.create();
    final privateVoice = File('${privateVoices.path}/af_bella.npy');
    final voiceBytes = await voice.readAsBytes();
    await privateVoice.writeAsBytes(voiceBytes.sublist(0, 32), flush: true);
    final preservedCorruption = await privateVoice.copy(
      '${output.path}/truncated-voice.npy',
    );
    await record('private_corruption', {
      'path': preservedCorruption.path,
      'sha256': sha256
          .convert(await preservedCorruption.readAsBytes())
          .toString(),
      'bytes': 32,
    });
    final badVoice = processor(model.path, privateVoices.path);
    try {
      await expectError('truncated_voice', () async {
        await badVoice.prepareResources(
          documentId: 'bad-voice',
          revision: 1,
          voiceIds: ['af_bella'],
        );
      });
      await privateVoice.writeAsBytes(voiceBytes, flush: true);
      final bindings = await badVoice.prepareResources(
        documentId: 'recovered-voice',
        revision: 2,
        voiceIds: ['af_bella'],
      );
      if (bindings.length != 1 ||
          bindings.single.voiceDigest !=
              sha256.convert(voiceBytes).toString()) {
        throw StateError('Recovered voice binding differs');
      }
      await record('voice_recovered', {
        'bindings': bindings.map((binding) => binding.toMap()).toList(),
      });
    } finally {
      await badVoice.dispose();
    }
    await record('case_complete', {'case': 'truncated_voice'});

    await record('case_start', {'case': 'inference_shape'});
    final runner = KokoroModelRunner(modelPath: model.path);
    try {
      await runner.initialize();
      final tokenizer = Tokenizer(
        config: const TokenizerConfig(lexiconPath: 'assets/lexicon.json'),
      );
      await tokenizer.ensureInitialized();
      final tokens = tokenizer.tokenize(
        await tokenizer.phonemize('Are you okay?', lang: 'en-us'),
      );
      final style = (await repository.loadVoice(
        'af_bella',
      )).getStyleVectorForTokens(tokens.length);
      await expectError('inference_shape', () async {
        await runner.runInference(
          tokens: tokens,
          voice: Float32List.fromList(style.take(255).toList()),
          speed: 1,
        );
      });
      final audio = await runner.runInference(
        tokens: tokens,
        voice: style,
        speed: 1,
      );
      if (audio.isEmpty ||
          audio.every((sample) => sample == 0) ||
          audio.any((sample) => !sample.isFinite)) {
        throw StateError('Recovery produced invalid/silent audio');
      }
      final floats = Float32List.fromList(
        audio.map((sample) => sample.toDouble()).toList(),
      );
      final path = '${output.path}/recovered.f32';
      await File(path).writeAsBytes(floats.buffer.asUint8List(), flush: true);
      await record('inference_recovered', {
        'samples': audio.length,
        'path': path,
        'float32Sha256': sha256.convert(floats.buffer.asUint8List()).toString(),
      });
    } finally {
      await runner.dispose();
    }
    await record('case_complete', {'case': 'inference_shape'});
    await record('assets_after', await hashes());
    await record('complete', {
      'cases': 3,
      'limitation':
          'Real initialization/voice-validation/inference errors only. No hung-native or live playback claim.',
    });
    exit(0);
  } catch (error, stack) {
    await record('failure', {'error': '$error', 'stack': '$stack'});
    exit(1);
  }
}
