import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/kokoro_audio_identity.dart';
import 'package:read_aloud/src/services/model_content_snapshot.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';
import 'package:read_aloud/src/services/synthesis_boundary_policy.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('p4-private-cache-'));
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'raw key uses exact rate and full realization; revision is a separate guard',
    () {
      final a = request(rate: 1.001);
      final b = request(rate: 1.002);
      String key(SpeechWorkerChunkRequest r, [PreparedVoiceBinding? bind]) =>
          kokoroRawAudioIdentity(r, bind ?? binding(), 'kokoro', '12');
      expect(key(a), isNot(key(b)));
      expect(key(a), isNot(key(request(rate: 1.001, tokens: [9]))));
      expect(
        key(a),
        isNot(key(request(rate: 1.001, synthesis: 'changed-tokenizer'))),
      );
      expect(key(a), isNot(key(a, binding(voice: 'new-bytes'))));
      expect(key(a), isNot(key(a, binding(model: 'new-model'))));
      expect(key(a), key(a, binding(revision: 99)));
      expect(() => validateExpectedBinding(a, binding()), returnsNormally);
      expect(
        () => validateExpectedBinding(a, binding(revision: 2)),
        throwsStateError,
      );
      expect(
        () => validateExpectedBinding(a, binding(voice: 'new-bytes')),
        throwsStateError,
      );
    },
  );

  test(
    'admission snapshots tokens and request-bound identity before queued work',
    () {
      final tokens = [1, 2];
      final command = SpeechWorkerCommand.prepareChunk(request(tokens: tokens));
      tokens[0] = 9;
      expect(command.chunks.single.tokens, [1, 2]);
      expect(() => command.chunks.single.tokens[0] = 7, throwsUnsupportedError);
      final restored = SpeechWorkerChunkRequest.fromMap(
        command.chunks.single.toMap(),
      );
      expect(restored.expectedBindingFingerprint, binding().fingerprint);
      expect(restored.expectedBindingRevision, 1);
      expect(restored.synthesisIdentity, 'tokenizer-v1');
    },
  );

  test(
    'incomplete/hash/schema/frame mismatches are rejected without overwriting paths',
    () {
      final store = AudioArtifactStore(Directory('${root.path}/artifacts'));
      final id = artifactIdentity({'raw': 'fixture'});
      final partial = Directory('${store.directory.path}/$id/incomplete')
        ..createSync(recursive: true);
      File('${partial.path}/audio.wav').writeAsBytesSync(wav());
      expect(store.lookup(id), isNull);
      final complete = store.publish(
        identity: id,
        wav: wav(),
        metadata: {'voiceId': 'fixture'},
      );
      final original = File(complete.audioPath).readAsBytesSync();
      expect(
        store.publish(identity: id, wav: wav(), metadata: {}).audioPath,
        complete.audioPath,
      );
      final manifestFile = File(
        '${File(complete.audioPath).parent.path}/manifest.json',
      );
      final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
      for (final invalid in [
        {...manifest, 'complete': false},
        {...manifest, 'schema': 900},
        {...manifest, 'frames': 0},
        {...manifest, 'wavSha256': 'bad'},
      ]) {
        manifestFile.writeAsStringSync(jsonEncode(invalid));
        expect(store.lookup(id), isNull);
      }
      final replacement = store.publish(identity: id, wav: wav(), metadata: {});
      expect(replacement.audioPath, isNot(complete.audioPath));
      expect(File(complete.audioPath).readAsBytesSync(), original);
      expect(partial.existsSync(), isTrue);
      expect(
        store.directory.listSync().where(
          (f) => f.path.split('/').last.startsWith('.stage-'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'pins survive reuse and derivative publication without mutating queued PCM',
    () {
      final store = AudioArtifactStore(Directory('${root.path}/raw'));
      final raw = store.publish(
        identity: artifactIdentity('raw'),
        wav: wav(),
        metadata: {},
      );
      final bytes = File(raw.audioPath).readAsBytesSync();
      final pins = AudioArtifactPins();
      final playback = pins.pin(raw.audioPath);
      final export = pins.pin(raw.audioPath);
      final policy = SynthesisBoundaryPolicy();
      final first = policy.correctWavFileSync(
        chunkId: 'c',
        wavFilePath: raw.audioPath,
        boundaryClass: BreakClass.weak,
        isInitialChunk: false,
        isResumedChunk: false,
        previousTrailingSilence: Duration(milliseconds: 100),
        previousArtifactIdentity: 'previous-A',
      );
      final second = policy.correctWavFileSync(
        chunkId: 'c',
        wavFilePath: raw.audioPath,
        boundaryClass: BreakClass.weak,
        isInitialChunk: false,
        isResumedChunk: false,
        previousTrailingSilence: Duration(milliseconds: 20),
        previousArtifactIdentity: 'previous-B',
      );
      final reused = policy.correctWavFileSync(
        chunkId: 'c',
        wavFilePath: raw.audioPath,
        boundaryClass: BreakClass.weak,
        isInitialChunk: false,
        isResumedChunk: false,
        previousTrailingSilence: Duration(milliseconds: 100),
        previousArtifactIdentity: 'previous-A',
      );
      expect(first.audioPath, reused.audioPath);
      expect(first.audioPath, isNot(second.audioPath));
      expect(first.leadingSilenceAfter, Duration(milliseconds: 20));
      expect(second.leadingSilenceAfter, Duration(milliseconds: 100));
      expect(File(raw.audioPath).readAsBytesSync(), bytes);
      expect(pins.pinCount(raw.audioPath), 2);
      playback.release();
      playback.release();
      expect(pins.pinCount(raw.audioPath), 1);
      export.release();
      expect(pins.isPinned(raw.audioPath), isFalse);
      expect(File(raw.audioPath).existsSync(), isTrue);
    },
  );

  test(
    'model replacement after snapshot cannot change native-open bytes',
    () async {
      final source = File('${root.path}/private-model.onnx')
        ..writeAsBytesSync([1, 2, 3]);
      final snapshots = Directory('${root.path}/models');
      final first = await ModelContentSnapshot.capture(source.path, snapshots);
      source.writeAsBytesSync([9, 8, 7]);
      expect(File(first.path).readAsBytesSync(), [1, 2, 3]);
      final second = await ModelContentSnapshot.capture(source.path, snapshots);
      expect(second.digest, isNot(first.digest));
      expect(second.path, isNot(first.path));
      expect(
        (await ModelContentSnapshot.capture(source.path, snapshots)).path,
        second.path,
      );
      expect(
        snapshots.listSync().where(
          (f) => f.path.split('/').last.startsWith('.stage-'),
        ),
        isEmpty,
      );
    },
  );
  test(
    'corrupted reused model snapshot is rejected and never repaired in place',
    () async {
      final source = File('${root.path}/source.onnx')
        ..writeAsBytesSync([1, 2, 3]);
      final snapshots = Directory('${root.path}/snapshots');
      final original = await ModelContentSnapshot.capture(
        source.path,
        snapshots,
      );
      File(original.path).writeAsBytesSync([7, 8, 9]);
      await expectLater(
        ModelContentSnapshot.capture(source.path, snapshots),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('snapshot was modified'),
          ),
        ),
      );
      expect(File(original.path).readAsBytesSync(), [7, 8, 9]);
      expect(source.readAsBytesSync(), [1, 2, 3]);
      expect(
        snapshots.listSync().where(
          (e) => e.path.split('/').last.startsWith('.stage-'),
        ),
        isEmpty,
      );
    },
  );
  test(
    'simultaneous isolate publishers leave complete immutable generations',
    () async {
      final path = '${root.path}/concurrent';
      final id = artifactIdentity('shared-content');
      final ready = ReceivePort();
      final workers = <SendPort>[];
      final results = <String>[];
      final done = Completer<void>();
      final subscription = ready.listen((message) {
        if (message is SendPort) {
          workers.add(message);
          if (workers.length == 4) {
            for (final worker in workers) {
              worker.send(true);
            }
          }
        } else if (message is String) {
          results.add(message);
          if (results.length == 4) done.complete();
        }
      });
      try {
        for (var i = 0; i < 4; i++) {
          await Isolate.spawn(publishArtifact, [ready.sendPort, path, id]);
        }
        await done.future.timeout(const Duration(seconds: 10));
        final store = AudioArtifactStore(Directory(path));
        final hit = store.lookup(id)!;
        expect(hit.frames, 24000);
        for (final result in results) {
          expect(File(result).readAsBytesSync(), wav());
          expect(
            File('${File(result).parent.path}/manifest.json').existsSync(),
            isTrue,
          );
        }
        expect(
          Directory(path).listSync().where(
            (e) => e.path.split('/').last.startsWith('.stage-'),
          ),
          isEmpty,
        );
      } finally {
        await subscription.cancel();
        ready.close();
      }
    },
  );
  test(
    'publication failure cleans only owned staging and rejects malformed WAV',
    () {
      final store = AudioArtifactStore(Directory('${root.path}/artifacts'));
      store.directory.createSync(recursive: true);
      final otherOwner = Directory('${store.directory.path}/.stage-other-owner')
        ..createSync();
      File('${otherOwner.path}/keep').writeAsStringSync('owned elsewhere');
      expect(
        () => store.publish(
          identity: artifactIdentity('bad-metadata'),
          wav: wav(),
          metadata: {'unserializable': Object()},
        ),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect(otherOwner.existsSync(), isTrue);
      expect(store.directory.listSync().map((e) => e.path).toList(), [
        otherOwner.path,
      ]);
      final invalid = wav();
      ByteData.sublistView(invalid).setUint32(40, 0, Endian.little);
      expect(
        () => store.publish(
          identity: artifactIdentity('bad-wav'),
          wav: invalid,
          metadata: {},
        ),
        throwsFormatException,
      );
    },
  );
}

void publishArtifact(List<Object> input) async {
  final reply = input[0] as SendPort;
  final gate = ReceivePort();
  reply.send(gate.sendPort);
  await gate.first;
  gate.close();
  final artifact = AudioArtifactStore(Directory(input[1] as String)).publish(
    identity: input[2] as String,
    wav: wav(),
    metadata: {'fixture': 'concurrent'},
  );
  Isolate.exit(reply, artifact.audioPath);
}

PreparedVoiceBinding binding({
  String voice = 'voice-bytes',
  String model = 'model-bytes',
  int revision = 1,
}) => PreparedVoiceBinding(
  voiceId: 'fixture',
  voiceDigest: voice,
  modelDigest: model,
  engineVersion: '12',
  pronunciationProfileId: 'english',
  bindingRevision: revision,
  documentId: 'doc',
);

SpeechWorkerChunkRequest request({
  double rate = 1,
  List<int> tokens = const [1, 2],
  String synthesis = 'tokenizer-v1',
}) => SpeechWorkerChunkRequest(
  sessionId: 'session',
  generationId: 'generation',
  chunkId: 'c',
  segmentIds: ['s'],
  cacheKey: 'rounded-caller-key',
  boundaryClass: BreakClass.none,
  documentId: 'doc',
  normalizationVersion: 'v1',
  speakText: 'John said',
  tokens: tokens,
  languageTag: 'en-US',
  voiceId: 'fixture',
  rate: rate,
  expectedBindingFingerprint: binding().fingerprint,
  expectedBindingRevision: 1,
  synthesisIdentity: synthesis,
);

Uint8List wav() {
  final bytes = Uint8List(44 + 24000 * 2);
  final b = ByteData.sublistView(bytes);
  void tag(int at, String s) => bytes.setRange(at, at + 4, s.codeUnits);
  tag(0, 'RIFF');
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  tag(36, 'data');
  b.setUint32(4, bytes.length - 8, Endian.little);
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, 24000, Endian.little);
  b.setUint32(28, 48000, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  b.setUint32(40, bytes.length - 44, Endian.little);
  for (var i = 4800; i < 19200; i++) {
    b.setInt16(44 + i * 2, 12000, Endian.little);
  }
  return bytes;
}
