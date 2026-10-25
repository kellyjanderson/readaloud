// Native lifetime probe, not live playback or acoustic-quality acceptance.
// Build: flutter build macos --debug -t tools/p2_native_probe.dart
// Launch only through run_p2_native_probe.rb in the isolated p2 bundle.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/kokoro_assets.dart';
import 'package:read_aloud/src/services/kokoro_speech_worker_processor.dart';
import 'package:read_aloud/src/services/kokoro_voice_manager.dart';
import 'package:read_aloud/src/services/kokoro_voice_repository.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final contexts = arguments.length == 2 ? int.tryParse(arguments[1]) : 3;
  if (arguments.isEmpty ||
      arguments.length > 2 ||
      contexts == null ||
      contexts < 3 ||
      contexts > 100) {
    stderr.writeln(
      'Usage: p2 probe NEW_OUTPUT_DIRECTORY [CONTEXTS=3, range 3..100]',
    );
    exit(64);
  }
  final output = Directory(arguments.first);
  if (await output.exists()) {
    stderr.writeln('Probe output must not exist: ${output.path}');
    exit(64);
  }
  await output.create(recursive: true);
  final events = File('${output.path}/events.jsonl');
  final started = Stopwatch()..start();
  Future<void> record(String kind, Map<String, Object?> fields) async {
    final entry = <String, Object?>{
      'kind': kind,
      'elapsedMillis': started.elapsedMilliseconds,
      'rssBytes': ProcessInfo.currentRss,
      ...fields,
    };
    await events.writeAsString(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
      flush: true,
    );
    stdout.writeln('READALOUD_P2 ${jsonEncode(entry)}');
  }

  KokoroSpeechWorkerChunkProcessor? processor;
  try {
    final assets = await prepareKokoroAssets();
    if (!assets.isReady) {
      throw StateError(assets.message ?? 'Assets unavailable');
    }
    final voices = KokoroVoiceRepository(
      voicesDirectory: assets.voicesDirectory!,
    );
    await KokoroVoiceManager(
      voiceRepository: voices,
      cacheDirectory: assets.cacheDirectory!,
    ).initialize();
    const voiceIds = ['af_bella', 'am_fenrir'];
    final paths = <String, String>{
      'model': assets.modelPath!,
      for (final voice in voiceIds)
        voice: '${assets.voicesDirectory}/$voice.npy',
    };
    Future<Map<String, Object?>> fingerprints() async => {
      for (final item in paths.entries)
        item.key: {
          'path': item.value,
          'resolvedPath': await File(item.value).resolveSymbolicLinks(),
          'bytes': await File(item.value).length(),
          'sha256': (await sha256.bind(File(item.value).openRead()).first)
              .toString(),
        },
    };
    await record('assets_before', await fingerprints());
    final tokenizer = Tokenizer(
      config: const TokenizerConfig(lexiconPath: 'assets/lexicon.json'),
    );
    await tokenizer.ensureInitialized();
    const text = 'Are you okay?';
    final phonemes = await tokenizer.phonemize(text, lang: 'en-us');
    final tokens = tokenizer.tokenize(phonemes);
    if (tokens.isEmpty) throw StateError('No tokens');
    await record('fixture', {
      'text': text,
      'phonemes': phonemes,
      'tokens': tokens,
      'sha256': sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'text': text,
                'phonemes': phonemes,
                'tokens': tokens,
              }),
            ),
          )
          .toString(),
      'mainChunks': 300,
      'cycleChunks': (contexts - 1) * 3,
      'contexts': contexts,
    });
    KokoroSpeechWorkerChunkProcessor createProcessor() =>
        KokoroSpeechWorkerChunkProcessor(
          rootIsolateToken: RootIsolateToken.instance!,
          modelPath: assets.modelPath!,
          voicesDirectory: assets.voicesDirectory!,
          generatedAudioDirectory: '${output.path}/audio',
          engineId: 'kokoro',
          engineVersion: 'p2-probe',
        );
    final referencePcm = <String, String>{};
    for (var cycle = 0; cycle < contexts; cycle++) {
      processor ??= createProcessor();
      final documentId = 'p2-probe-document-$cycle';
      await record('before_prepare', {'cycle': cycle});
      final bindings = await processor.prepareResources(
        documentId: documentId,
        revision: cycle + 1,
        voiceIds: voiceIds,
      );
      await record('prepared', {
        'cycle': cycle,
        'documentId': documentId,
        'bindings': [
          for (final binding in bindings)
            {...binding.toMap(), 'fingerprint': binding.fingerprint},
        ],
      });
      final count = cycle == 0 ? 300 : 3;
      for (var index = 0; index < count; index++) {
        final voice = index % 3 == 1 ? voiceIds[1] : voiceIds[0];
        final chunk = 'cycle_${cycle}_chunk_$index';
        final emitted = <SpeechWorkerEvent>[];
        final watch = Stopwatch()..start();
        await processor.process(
          SpeechWorkerChunkRequest(
            sessionId: 'p2-probe-$cycle',
            generationId: 'generation-$cycle',
            chunkId: chunk,
            segmentIds: [chunk],
            cacheKey: '${output.path}:$chunk',
            boundaryClass: BreakClass.none,
            documentId: documentId,
            normalizationVersion: 'p2-probe-v1',
            speakText: text,
            tokens: tokens,
            languageTag: 'en-us',
            voiceId: voice,
            rate: 1,
          ),
          emitted.add,
        );
        watch.stop();
        if (emitted.any(
          (event) =>
              event.type == SpeechWorkerEventType.cacheHit ||
              event.type == SpeechWorkerEventType.failed ||
              event.type == SpeechWorkerEventType.cancelled,
        )) {
          throw StateError(
            'Unexpected cache/failure: ${emitted.map((event) => event.toMap()).toList()}',
          );
        }
        final complete = emitted
            .where((event) => event.type == SpeechWorkerEventType.completed)
            .toList();
        if (complete.length != 1 || complete.single.audioPath == null) {
          throw StateError('Missing terminal audio for $chunk');
        }
        final path = complete.single.audioPath!;
        final wav = await File(path).readAsBytes();
        final pcm = _pcm(wav);
        if (pcm.isEmpty || pcm.every((value) => value == 0)) {
          throw StateError('Empty/silent PCM');
        }
        final pcmHash = sha256.convert(pcm).toString();
        referencePcm.putIfAbsent(voice, () => pcmHash);
        await record('chunk', {
          'cycle': cycle,
          'index': index,
          'chunkId': chunk,
          'voiceId': voice,
          'path': path,
          'inferenceMillis': watch.elapsedMilliseconds,
          'durationMillis': complete.single.duration?.inMilliseconds,
          'wavSha256': sha256.convert(wav).toString(),
          'pcmSha256': pcmHash,
          'pcmBytes': pcm.length,
          'sameVoicePcmMatchesFirst': referencePcm[voice] == pcmHash,
          'events': [for (final event in emitted) event.type.name],
        });
      }
      if (cycle == 0) {
        await record('before_release', {'cycle': cycle});
        await processor.releaseResources();
        await record('released', {'cycle': cycle});
      } else {
        await record('before_dispose', {'cycle': cycle});
        await processor.dispose();
        processor = null;
        await record('disposed', {'cycle': cycle});
      }
    }
    await record('assets_after', await fingerprints());
    await record('complete', {
      'chunks': 300 + (contexts - 1) * 3,
      'contexts': contexts,
      'limitation':
          'Native synthesis lifetime only; no player, live playback continuity or perceptual-quality claim.',
    });
    exit(0);
  } catch (error, stack) {
    await record('failure', {'error': '$error', 'stack': '$stack'});
    try {
      await processor?.dispose();
      await record('failure_cleanup', {'completed': true});
    } catch (cleanupError) {
      await record('failure_cleanup', {
        'completed': false,
        'error': '$cleanupError',
      });
    }
    exit(1);
  }
}

Uint8List _pcm(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  if (wav.length < 12 ||
      ascii.decode(wav.sublist(0, 4)) != 'RIFF' ||
      ascii.decode(wav.sublist(8, 12)) != 'WAVE' ||
      data.getUint32(4, Endian.little) + 8 != wav.length) {
    throw const FormatException('Invalid RIFF length/header');
  }
  for (var offset = 12; offset + 8 <= wav.length;) {
    final size = data.getUint32(offset + 4, Endian.little);
    if (offset + 8 + size > wav.length) {
      throw const FormatException('Truncated WAV');
    }
    if (ascii.decode(wav.sublist(offset, offset + 4)) == 'data') {
      return Uint8List.sublistView(wav, offset + 8, offset + 8 + size);
    }
    offset += 8 + size + size % 2;
  }
  throw const FormatException('Missing PCM data');
}
