import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/pcm_wav.dart';

void main() {
  for (final rate in [24000, 44100, 48000]) {
    for (final bits in [8, 16, 24, 32]) {
      for (final channels in [1, 2]) {
        test('$rate Hz PCM$bits/$channels preserves layout and header', () {
          final payload = List<int>.generate(
            3 * channels * (bits ~/ 8),
            (i) => i * 7 % 256,
          );
          final bytes = buildPcmWavFixture(
            payload: payload,
            rate: rate,
            bits: bits,
            channels: channels,
          );
          final layout = decodePcmWav(bytes);
          expect(layout.format.sampleRate, rate);
          expect(layout.format.channelCount, channels);
          expect(layout.format.bitsPerSample, bits);
          expect(layout.format.blockAlign, channels * bits ~/ 8);
          expect(layout.frameCount, 3);
          expect(
            bytes.sublist(
              layout.dataOffset,
              layout.dataOffset + layout.dataLength,
            ),
            payload,
          );
          expect(
            encodePcmWavHeader(layout.format, payload.length),
            bytes.sublist(0, 44),
          );
        });
      }
    }
  }
  for (final dataFirst in [false, true]) {
    test('odd metadata, extended fmt and data-first=$dataFirst', () {
      final bytes = buildPcmWavFixture(
        payload: [0, 1, 2, 3],
        junk: true,
        extended: true,
        dataFirst: dataFirst,
      );
      final layout = decodePcmWav(bytes);
      expect(layout.frameCount, 2);
      expect(bytes.sublist(layout.dataOffset, layout.dataOffset + 4), [
        0,
        1,
        2,
        3,
      ]);
    });
  }
  test('buffer views retain relative offsets', () {
    final bytes = buildPcmWavFixture(payload: [1, 2]);
    final framed = Uint8List.fromList([9, 9, ...bytes, 9]);
    expect(
      decodePcmWav(
        Uint8List.sublistView(framed, 2, 2 + bytes.length),
      ).dataOffset,
      44,
    );
  });
  for (final entry in malformedPcmWavFixtures().entries) {
    test('rejects ${entry.key}', () {
      expect(() => decodePcmWav(entry.value), throwsFormatException);
    });
  }
  test('header refuses native int64 overflow without allocating PCM', () {
    final pcm16 = PcmFormat(
      sampleRate: 24000,
      channelCount: 1,
      bitsPerSample: 16,
    );
    final pcm8 = PcmFormat(
      sampleRate: 24000,
      channelCount: 1,
      bitsPerSample: 8,
    );
    expect(
      () => encodePcmWavHeader(pcm16, 0x7ffffffffffffffe),
      throwsFormatException,
    );
    expect(
      () => encodePcmWavHeader(pcm8, 0x7fffffffffffffff),
      throwsFormatException,
    );
  });
  test('header honors final RIFF capacity with odd padding', () {
    final pcm16 = PcmFormat(
      sampleRate: 24000,
      channelCount: 1,
      bitsPerSample: 16,
    );
    final pcm8 = PcmFormat(
      sampleRate: 24000,
      channelCount: 1,
      bitsPerSample: 8,
    );
    for (final pair in [(pcm16, 0xffffffda), (pcm8, 0xffffffd9)]) {
      final header = ByteData.sublistView(encodePcmWavHeader(pair.$1, pair.$2));
      expect(header.getUint32(4, Endian.little), 0xfffffffe);
      expect(header.getUint32(40, Endian.little), pair.$2);
    }
    expect(() => encodePcmWavHeader(pcm16, 0xffffffdc), throwsFormatException);
    expect(() => encodePcmWavHeader(pcm8, 0xffffffdb), throwsFormatException);
  });
  test('header refuses partial frames and RIFF overflow', () {
    final stereo = PcmFormat(
      sampleRate: 48000,
      channelCount: 2,
      bitsPerSample: 16,
    );
    for (final length in [-4, 2, 0xfffffffc]) {
      expect(() => encodePcmWavHeader(stereo, length), throwsFormatException);
    }
    expect(
      () => PcmFormat(sampleRate: 0, channelCount: 1, bitsPerSample: 16),
      throwsFormatException,
    );
    expect(
      () =>
          PcmFormat(sampleRate: 48000, channelCount: 65536, bitsPerSample: 16),
      throwsFormatException,
    );
    expect(
      () =>
          PcmFormat(sampleRate: 0xffffffff, channelCount: 2, bitsPerSample: 32),
      throwsFormatException,
    );
  });
}

// Independent fixture encoder: no production parser/header mechanics are used.
Uint8List buildPcmWavFixture({
  List<int> payload = const [0, 1, 2, 3],
  int rate = 24000,
  int bits = 16,
  int channels = 1,
  bool junk = false,
  bool extended = false,
  bool dataFirst = false,
}) {
  final fmt = ByteData(extended ? 20 : 16)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, channels, Endian.little)
    ..setUint32(4, rate, Endian.little)
    ..setUint32(8, rate * channels * bits ~/ 8, Endian.little)
    ..setUint16(12, channels * bits ~/ 8, Endian.little)
    ..setUint16(14, bits, Endian.little);
  if (extended) fmt.setUint16(16, 2, Endian.little);
  final body = BytesBuilder();
  if (junk) body.add(fixtureChunk('JUNK', [91, 92, 93]));
  if (dataFirst) body.add(fixtureChunk('data', payload));
  body.add(fixtureChunk('fmt ', fmt.buffer.asUint8List()));
  if (!dataFirst) body.add(fixtureChunk('data', payload));
  return fixtureRiff(body.takeBytes());
}

Uint8List fixtureChunk(String tag, List<int> payload) {
  final size = ByteData(4)..setUint32(0, payload.length, Endian.little);
  return Uint8List.fromList([
    ...tag.codeUnits,
    ...size.buffer.asUint8List(),
    ...payload,
    if (payload.length.isOdd) 0,
  ]);
}

Uint8List fixtureRiff(List<int> body) {
  final size = ByteData(4)..setUint32(0, body.length + 4, Endian.little);
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ...size.buffer.asUint8List(),
    ...'WAVE'.codeUnits,
    ...body,
  ]);
}

Map<String, Uint8List> malformedPcmWavFixtures() {
  final valid = buildPcmWavFixture();
  Uint8List change(int offset, int value, int width) {
    final bytes = Uint8List.fromList(valid);
    final data = ByteData.sublistView(bytes);
    if (width == 2) {
      data.setUint16(offset, value, Endian.little);
    } else {
      data.setUint32(offset, value, Endian.little);
    }
    return bytes;
  }

  final fmt = valid.sublist(12, 36);
  final pcm = valid.sublist(36);
  return {
    'short RIFF': Uint8List(11),
    'RIFF signature': change(0, 0, 4),
    'WAVE signature': change(8, 0xffffffff, 4),
    'short extent': change(4, valid.length - 10, 4),
    'long extent': change(4, valid.length, 4),
    'truncated chunk header': fixtureRiff([...fmt, 1, 2, 3]),
    'truncated payload': change(40, 100, 4),
    'missing odd padding': fixtureRiff([
      ...fmt,
      ...'data'.codeUnits,
      1,
      0,
      0,
      0,
      7,
    ]),
    'duplicate fmt': fixtureRiff([...fmt, ...fmt, ...pcm]),
    'duplicate data': fixtureRiff([...fmt, ...pcm, ...pcm]),
    'missing fmt': fixtureRiff(pcm),
    'missing data': fixtureRiff(fmt),
    'short fmt': fixtureRiff([
      ...fixtureChunk('fmt ', List.filled(14, 0)),
      ...pcm,
    ]),
    'float': change(20, 3, 2),
    'extensible': change(20, 0xfffe, 2),
    'compressed': change(20, 6, 2),
    'zero rate': change(24, 0, 4),
    'zero channels': change(22, 0, 2),
    'unsupported bit depth': change(34, 20, 2),
    'bad block alignment': change(32, 4, 2),
    'bad byte rate': change(28, 100, 4),
    'partial frame': fixtureRiff([
      ...fmt,
      ...fixtureChunk('data', [1, 2, 3]),
    ]),
  };
}
