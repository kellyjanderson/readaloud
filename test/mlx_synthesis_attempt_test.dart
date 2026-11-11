import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';

void main() {
  test(
    'failed and cancelled attempts retain audio outside the complete cache',
    () async {
      final root = await Directory.systemTemp.createTemp('mlx-retention-test-');
      addTearDown(() => root.delete(recursive: true));
      final store = AudioArtifactStore(root);
      final completedId = artifactIdentity('earlier complete passage');
      final prior = store.publish(
        identity: completedId,
        wav: _wav(),
        metadata: {},
      );
      final original = await File(prior.audioPath).readAsBytes();
      final pendingId = artifactIdentity('later incomplete passage');
      final attempts = <MlxSynthesisAttempt>[];
      for (final outcome in ['failed', 'cancelled', 'retry-failed']) {
        final attempt = await MlxSynthesisAttempt.create(root, {
          'artifactIdentity': pendingId,
          'chunkId': 'later',
          'generationId': outcome,
        });
        attempts.add(attempt);
        await File(
          '${attempt.directory.path}/rendered.partial.wav',
        ).writeAsBytes(_wav());
        await attempt.finish();
        expect(await attempt.directory.exists(), isTrue);
        final metadata = jsonDecode(
          await File('${attempt.directory.path}/request.json').readAsString(),
        );
        expect(metadata['complete'], isFalse);
        expect(store.lookup(pendingId), isNull);
        expect(await File(prior.audioPath).readAsBytes(), original);
      }
      expect(attempts.map((a) => a.directory.path).toSet(), hasLength(3));
      for (final attempt in attempts) {
        final bytes = await File(
          '${attempt.directory.path}/rendered.partial.wav',
        ).readAsBytes();
        expect(AudioArtifactStore.validateWav(bytes).frames, 2);
      }
      final success = await MlxSynthesisAttempt.create(root, {
        'artifactIdentity': pendingId,
      });
      await success.audio.writeAsBytes(_wav());
      final published = store.publish(
        identity: pendingId,
        wav: await success.audio.readAsBytes(),
        metadata: {},
      );
      await success.finish(publishedAudioPath: published.audioPath);
      expect(await success.directory.exists(), isFalse);
      expect(await File(published.audioPath).exists(), isTrue);
      for (final attempt in attempts) {
        expect(await attempt.directory.exists(), isTrue);
      }
    },
  );

  test(
    'successful streamed spool survives publication and derivative pins',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mlx-stream-retention-',
      );
      addTearDown(() => root.delete(recursive: true));
      final attempt = await MlxSynthesisAttempt.create(root, {});
      await attempt.audio.writeAsBytes(_wav());
      final packet = File('${attempt.directory.path}/packet-0000.wav');
      final derivative = File('${packet.path}.onset-1.wav');
      await packet.writeAsBytes(_wav());
      await derivative.writeAsBytes(_wav());
      final published = AudioArtifactStore(root).publish(
        identity: artifactIdentity('streamed'),
        wav: _wav(),
        metadata: {},
      );
      final pin = AudioArtifactPins.shared.pin(derivative.path);
      try {
        await attempt.finish(publishedAudioPath: published.audioPath);
        expect(await packet.exists(), true);
        expect(await derivative.exists(), true);
        expect(await attempt.audio.exists(), true);
      } finally {
        pin.release();
      }
    },
  );

  test('an attempt with no rendered audio can be cleaned up', () async {
    final root = await Directory.systemTemp.createTemp('mlx-empty-attempt-');
    addTearDown(() => root.delete(recursive: true));
    final attempt = await MlxSynthesisAttempt.create(root, {});
    await attempt.finish();
    expect(await attempt.directory.exists(), isFalse);
  });

  test(
    'a competing different render never authorizes deleting this attempt',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mlx-competing-audio-',
      );
      addTearDown(() => root.delete(recursive: true));
      final attempt = await MlxSynthesisAttempt.create(root, {});
      final rendered = _wav();
      await attempt.audio.writeAsBytes(rendered);
      final other = _wav();
      ByteData.sublistView(other).setInt16(44, 12000, Endian.little);
      final published = AudioArtifactStore(root).publish(
        identity: artifactIdentity('same synthesis request'),
        wav: other,
        metadata: {},
      );
      await attempt.finish(publishedAudioPath: published.audioPath);
      expect(await attempt.audio.readAsBytes(), rendered);
      expect(await File(published.audioPath).readAsBytes(), other);
    },
  );
}

Uint8List _wav() {
  final bytes = Uint8List(48);
  final data = ByteData.sublistView(bytes);
  void tag(int offset, String value) =>
      bytes.setRange(offset, offset + 4, ascii.encode(value));
  tag(0, 'RIFF');
  data.setUint32(4, 40, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 44100, Endian.little);
  data.setUint32(28, 88200, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, 4, Endian.little);
  data.setInt16(44, 8000, Endian.little);
  data.setInt16(46, -8000, Endian.little);
  return bytes;
}
