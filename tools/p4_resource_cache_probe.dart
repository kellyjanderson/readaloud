// Native resource/cache proof only: no player, listening or UI claims.
// Build -t tools/p4_resource_cache_probe.dart in an isolated bundle. Launch with
// NEW_OUTPUT_DIRECTORY MODEL_PATH VOICE_NPY_PATH SOURCE_COMMIT. Paths must be
// readable inside that bundle's sandbox. Set READALOUD_ORT_RESOURCE_TRACE=1;
// preserve stdout/stderr for native counters alongside events.jsonl.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/kokoro_audio_identity.dart';
import 'package:read_aloud/src/services/kokoro_speech_worker_processor.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 4 || !RegExp(r'^[0-9a-f]{7,40}$').hasMatch(args[3])) {
    stderr.writeln('Usage: NEW_OUTPUT MODEL VOICE_NPY SOURCE_COMMIT');
    exit(64);
  }
  final output = Directory(args[0]);
  if (output.existsSync()) exit(64);
  output.createSync(recursive: true);
  final clock = Stopwatch()..start();
  final log = File('${output.path}/events.jsonl');
  void record(String kind, Map<String, Object?> fields) {
    final row = {
      'kind': kind,
      'elapsedMillis': clock.elapsedMilliseconds,
      'rssBytes': ProcessInfo.currentRss,
      ...fields,
    };
    log.writeAsStringSync(
      '${jsonEncode(row)}\n',
      mode: FileMode.append,
      flush: true,
    );
    stdout.writeln('READALOUD_P4_RESOURCE ${jsonEncode(row)}');
  }

  Future<Map<String, Object?>> fingerprint(String path) async => {
    'path': path,
    'resolvedPath': await File(path).resolveSymbolicLinks(),
    'bytes': await File(path).length(),
    'sha256': (await sha256.bind(File(path).openRead()).first).toString(),
  };
  KokoroSpeechWorkerChunkProcessor? worker;
  var passed = false;
  try {
    record('provenance', {
      'declaredSourceCommit': args[3],
      'executable': await fingerprint(Platform.resolvedExecutable),
      'buildAttestation':
          'Caller must retain bundle/dylib hashes and checkout manifest; a supplied commit is not build attestation.',
      'model': await fingerprint(args[1]),
      'voice': await fingerprint(args[2]),
      'nativeCounters':
          'Capture READALOUD_ORT stdout; not inferred from Dart events',
    });
    final sourceBefore = [
      await fingerprint(args[1]),
      await fingerprint(args[2]),
    ];
    final private = Directory('${output.path}/private')..createSync();
    // File.copy preserves source mode on macOS. Bundled model assets can be
    // read-only; create our own writable file without changing that source.
    final model = File('${private.path}/model.onnx');
    final modelCopy = model.openWrite();
    try {
      await modelCopy.addStream(File(args[1]).openRead());
      await modelCopy.flush();
    } finally {
      await modelCopy.close();
    }
    if ((await fingerprint(model.path))['sha256'] !=
        sourceBefore.first['sha256']) {
      throw StateError(
        'Private model copy differs before intentional mutation',
      );
    }
    final voiceDir = Directory('${private.path}/voices')..createSync();
    final voice = await File(args[2]).copy('${voiceDir.path}/fixture.npy');
    final audio = '${output.path}/audio';
    worker = KokoroSpeechWorkerChunkProcessor(
      rootIsolateToken: RootIsolateToken.instance!,
      modelPath: model.path,
      voicesDirectory: voiceDir.path,
      generatedAudioDirectory: audio,
      engineId: 'kokoro',
      engineVersion: 'p4-resource-probe-v1',
      timeout: const Duration(seconds: 90),
    );
    final tokenizer = Tokenizer(
      config: const TokenizerConfig(lexiconPath: 'assets/lexicon.json'),
    );
    await tokenizer.ensureInitialized();
    const text = 'Are you okay?';
    final phonemes = await tokenizer.phonemize(text, lang: 'en-us');
    final tokens = tokenizer.tokenize(phonemes);
    if (tokens.isEmpty) throw StateError('Empty fixture tokens');
    record('fixture', {'text': text, 'phonemes': phonemes, 'tokens': tokens});
    Future<PreparedVoiceBinding> prepare(int revision) async {
      final bindings = await worker!.prepareResources(
        documentId: 'p4-resource-document',
        revision: revision,
        voiceIds: ['fixture'],
      );
      final binding = bindings.single;
      record('prepared', {
        ...binding.toMap(),
        'fingerprint': binding.fingerprint,
      });
      return binding;
    }

    SpeechWorkerChunkRequest request(PreparedVoiceBinding b, String id) =>
        SpeechWorkerChunkRequest(
          sessionId: 'p4-resource',
          generationId: 'generation-${b.bindingRevision}',
          chunkId: id,
          segmentIds: [id],
          cacheKey: 'caller-key-is-not-authority',
          boundaryClass: BreakClass.none,
          documentId: b.documentId,
          normalizationVersion: 'p4-probe-v1',
          speakText: text,
          tokens: tokens,
          languageTag: 'en-us',
          voiceId: 'fixture',
          rate: 1,
          expectedBindingFingerprint: b.fingerprint,
          expectedBindingRevision: b.bindingRevision,
          synthesisIdentity: 'pinned-tokenizer-fixture-v1',
        );
    Future<String> render(
      PreparedVoiceBinding b,
      String id, {
      required bool hit,
    }) async {
      final events = <SpeechWorkerEvent>[];
      await worker!.process(request(b, id), events.add);
      record('chunkEvents', {
        'case': id,
        'events': events.map((e) => e.toMap()).toList(),
      });
      final cached = events.any(
        (e) => e.type == SpeechWorkerEventType.cacheHit,
      );
      final inferred = events.any(
        (e) => e.type == SpeechWorkerEventType.inferencing,
      );
      if (cached != hit ||
          inferred == hit ||
          events.any(
            (e) =>
                e.type == SpeechWorkerEventType.failed ||
                e.type == SpeechWorkerEventType.cancelled,
          )) {
        throw StateError('Unexpected cache/inference outcome $id');
      }
      final path = events
          .singleWhere((e) => e.type == SpeechWorkerEventType.completed)
          .audioPath!;
      final wav = await File(path).readAsBytes();
      final format = AudioArtifactStore.validateWav(wav);
      if (wav.sublist(44).every((v) => v == 0)) {
        throw StateError('Silent PCM $id');
      }
      record('emittedAudio', {
        'case': id,
        ...await fingerprint(path),
        'pcmSha256': sha256.convert(wav.sublist(44)).toString(),
        'frames': format.frames,
        'sampleRate': format.sampleRate,
        'bindingFingerprint': b.fingerprint,
      });
      return path;
    }

    final a = await prepare(1);
    final firstPath = await render(a, 'A-cold', hit: false);
    final b = await prepare(2);
    if (a.fingerprint != b.fingerprint) {
      throw StateError('Revision changed content identity');
    }
    final staleEvents = <SpeechWorkerEvent>[];
    Object? staleError;
    try {
      await worker.process(request(a, 'queued-old-A'), staleEvents.add);
    } catch (error) {
      staleError = error;
    }
    record('staleRejected', {
      'error': '$staleError',
      'events': staleEvents.map((e) => e.toMap()).toList(),
    });
    if (staleError == null ||
        !staleError.toString().contains('binding changed') ||
        staleEvents.isNotEmpty) {
      throw StateError('Old request was not rejected before cache/inference');
    }
    if (await render(b, 'B-reuse', hit: true) != firstPath) {
      throw StateError('Reuse path changed');
    }
    // Change one finite float in EVERY style row: whichever token-count style is
    // selected, it uses different private bytes. Preserve NPY header and shape.
    final voiceBytes = await voice.readAsBytes();
    final view = ByteData.sublistView(voiceBytes);
    final major = voiceBytes[6];
    final offset = major == 1
        ? 10 + view.getUint16(8, Endian.little)
        : 12 + view.getUint32(8, Endian.little);
    for (var at = offset; at + 4 <= voiceBytes.length; at += 4) {
      final value = view.getFloat32(at, Endian.little);
      if (!value.isFinite) throw StateError('Non-finite source voice');
      view.setFloat32(at, value * 0.999, Endian.little);
    }
    await voice.writeAsBytes(voiceBytes, flush: true);
    final c = await prepare(3);
    if (c.voiceDigest == b.voiceDigest) {
      throw StateError('Voice mutation did not change digest');
    }
    record('privateVoiceChanged', await fingerprint(voice.path));
    await render(c, 'same-id-new-voice-bytes', hit: false);
    await render(c, 'new-voice-reuse', hit: true);
    // Append a valid protobuf unknown length-delimited field1000 with zero bytes.
    // Native initialize AND successful emitted inference below are mandatory;
    // parser/inference failure is a failed run, never evidence of a cache miss.
    final sink = model.openWrite(mode: FileMode.append);
    sink.add([0xc2, 0x3e, 0]);
    await sink.close();
    record('privateModelChanged', await fingerprint(model.path));
    final d = await prepare(4);
    if (d.modelDigest == c.modelDigest) {
      throw StateError('Model digest unchanged');
    }
    await render(d, 'new-model-content', hit: false);
    await render(d, 'new-model-reuse', hit: true);
    // A partial generation under a fresh exact identity is never reusable.
    final partialRequest = request(d, 'partial').toMap()..['rate'] = 1.001;
    final partial = SpeechWorkerChunkRequest.fromMap(partialRequest);
    final identity = kokoroRawAudioIdentity(
      partial,
      d,
      'kokoro',
      'p4-resource-probe-v1',
    );
    final partialDir = Directory('$audio/raw-v1/$identity/incomplete')
      ..createSync(recursive: true);
    await File(firstPath).copy('${partialDir.path}/audio.wav');
    final store = AudioArtifactStore(Directory('$audio/raw-v1'));
    if (store.lookup(identity) != null) {
      throw StateError('Partial artifact reused');
    }
    final partialEvents = <SpeechWorkerEvent>[];
    await worker.process(partial, partialEvents.add);
    record('partialRegenerated', {
      'events': partialEvents.map((e) => e.toMap()).toList(),
    });
    if (partialEvents.any((e) => e.type == SpeechWorkerEventType.cacheHit) ||
        !partialEvents.any(
          (e) => e.type == SpeechWorkerEventType.inferencing,
        ) ||
        store.lookup(identity) == null) {
      throw StateError('Incomplete artifact not regenerated');
    }
    final complete = store.lookup(identity)!;
    final manifest = File(
      '${File(complete.audioPath).parent.path}/manifest.json',
    );
    final contents = jsonDecode(await manifest.readAsString()) as Map;
    contents['wavSha256'] = 'corrupt';
    await manifest.writeAsString(jsonEncode(contents));
    if (store.lookup(identity) != null) {
      throw StateError('Corrupted manifest reused');
    }
    record('corruptPublicationRejected', {
      'identity': identity,
      'path': complete.audioPath,
    });
    final sourceAfter = [
      await fingerprint(args[1]),
      await fingerprint(args[2]),
    ];
    if (jsonEncode(sourceBefore) != jsonEncode(sourceAfter)) {
      throw StateError('Source assets changed');
    }
    record('sourceAssetsUnchanged', {'assets': sourceAfter});
    passed = true;
  } catch (error, stack) {
    record('failure', {'error': '$error', 'stack': '$stack'});
  } finally {
    try {
      await worker?.dispose().timeout(const Duration(seconds: 120));
      record('shutdownDrained', {'passed': passed});
    } catch (error) {
      passed = false;
      record('shutdownFailed', {'error': '$error', 'drained': false});
    }
    record('terminal', {
      'passed': passed,
      'limits':
          'No playback/UI/acoustic proof; validate native counters and ffmpeg separately.',
    });
  }
  exit(passed ? 0 : 1);
}
