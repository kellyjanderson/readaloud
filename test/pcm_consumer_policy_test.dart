import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/kokoro_speech_worker_processor.dart';
import 'package:read_aloud/src/services/pcm_wav.dart';
import 'package:read_aloud/src/services/synthesis_boundary_policy.dart';

void main() {
  for (final rate in [24000, 44100, 48000]) {
    test('Kokoro retains quantization, little-endian PCM and $rate Hz', () {
      // Positive/negative half-scale, extrema and out-of-range values expose
      // clipping, rounding, sign and byte-order changes independently of RIFF.
      final audio = [-2, -1, -0.5, -1 / 32767, 0, 1 / 32767, 0.5, 1, 2];
      const expected = [-32767, -32767, -16384, -1, 0, 1, 16384, 32767, 32767];
      final bytes = encodeKokoroWav(audio, rate);
      final reference = _canonical(rate: rate, samples: expected);
      expect(bytes, reference);
      final format = AudioArtifactStore.validateWav(bytes);
      expect(format.sampleRate, rate);
      expect(format.frames, expected.length);
      expect(
        format.duration.inMilliseconds,
        (expected.length * 1000 / rate).round(),
      );
    });
  }

  final noncanonical = <String, Uint8List>{
    'odd padded metadata before fmt': _riff([
      ('JUNK', Uint8List.fromList([7, 8, 9])),
      ('fmt ', _format()),
      ('data', _pcm()),
    ]),
    'metadata after PCM': _riff([
      ('fmt ', _format()),
      ('data', _pcm()),
      ('LIST', Uint8List.fromList([1, 2])),
    ]),
    'fmt after data': _riff([('data', _pcm()), ('fmt ', _format())]),
    'extended fmt': _riff([
      ('fmt ', Uint8List.fromList([..._format(), 0, 0])),
      ('data', _pcm()),
    ]),
    'stereo': _riff([('fmt ', _format(channels: 2)), ('data', _pcm())]),
    'PCM24': _riff([
      ('fmt ', _format(bits: 24)),
      ('data', Uint8List.fromList([1, 2, 3, 4, 5, 6])),
    ]),
  };
  for (final entry in noncanonical.entries) {
    test(
      'artifact/trim policy rejects structurally valid ${entry.key}',
      () async {
        expect(() => decodePcmWav(entry.value), returnsNormally);
        expect(
          () => AudioArtifactStore.validateWav(entry.value),
          throwsFormatException,
        );
        final root = await Directory.systemTemp.createTemp('canonical-policy-');
        addTearDown(() => root.delete(recursive: true));
        final source = await File(
          '${root.path}/source.wav',
        ).writeAsBytes(entry.value);
        expect(
          () => const SynthesisBoundaryPolicy().correctWavFileSync(
            chunkId: 'c',
            wavFilePath: source.path,
            boundaryClass: BreakClass.none,
            isInitialChunk: true,
            isResumedChunk: false,
          ),
          throwsFormatException,
        );
        expect(await source.readAsBytes(), entry.value);
        expect(await root.list().length, 1);
      },
    );
  }

  test('canonical artifact validation rejects malformed structural fields', () {
    final mutations = <void Function(ByteData)>[
      (b) => b.setUint32(4, 1, Endian.little),
      (b) => b.setUint32(40, 1000, Endian.little),
      (b) => b.setUint32(40, 3, Endian.little),
      (b) => b.setUint32(28, 1, Endian.little),
      (b) => b.setUint16(32, 1, Endian.little),
      (b) => b.setUint32(24, 0, Endian.little),
      (b) => b.setUint16(20, 3, Endian.little),
    ];
    for (final mutate in mutations) {
      final bytes = _canonical(samples: [1, -2]);
      mutate(ByteData.sublistView(bytes));
      expect(
        () => AudioArtifactStore.validateWav(bytes),
        throwsFormatException,
      );
    }
    expect(
      () => AudioArtifactStore.validateWav(_canonical(samples: [])),
      throwsFormatException,
    );
    expect(
      () => AudioArtifactStore.validateWav(
        _riff([('fmt ', _format()), ('data', _pcm()), ('data', _pcm())]),
      ),
      throwsFormatException,
    );
    expect(
      () => AudioArtifactStore.validateWav(Uint8List(11)),
      throwsFormatException,
    );
  });
}

Uint8List _canonical({int rate = 24000, required List<int> samples}) =>
    _riff([('fmt ', _format(rate: rate)), ('data', _pcm(samples))]);

Uint8List _format({int rate = 24000, int channels = 1, int bits = 16}) {
  final bytes = Uint8List(16);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, channels, Endian.little);
  data.setUint32(4, rate, Endian.little);
  data.setUint32(8, rate * channels * (bits ~/ 8), Endian.little);
  data.setUint16(12, channels * (bits ~/ 8), Endian.little);
  data.setUint16(14, bits, Endian.little);
  return bytes;
}

Uint8List _pcm([List<int> samples = const [12000, -12000]]) {
  final bytes = Uint8List(samples.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

Uint8List _riff(List<(String, Uint8List)> chunks) {
  final body = BytesBuilder()..add('WAVE'.codeUnits);
  for (final (tag, payload) in chunks) {
    final length = ByteData(4)..setUint32(0, payload.length, Endian.little);
    body
      ..add(tag.codeUnits)
      ..add(length.buffer.asUint8List())
      ..add(payload);
    if (payload.length.isOdd) body.addByte(0);
  }
  final length = ByteData(4)..setUint32(0, body.length, Endian.little);
  return (BytesBuilder()
        ..add('RIFF'.codeUnits)
        ..add(length.buffer.asUint8List())
        ..add(body.takeBytes()))
      .takeBytes();
}
