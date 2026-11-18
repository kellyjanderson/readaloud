import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/pcm_wav.dart';
import 'package:read_aloud/src/services/pcm_wav_io.dart';

import 'pcm_wav_test.dart'
    show buildPcmWavFixture, malformedPcmWavFixtures, fixtureChunk;

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pcm-scan-');
  });
  tearDown(() => dir.delete(recursive: true));

  for (final rate in [24000, 44100, 48000]) {
    for (final dataFirst in [false, true]) {
      test('byte/file equivalence $rate Hz, data-first=$dataFirst', () async {
        final bytes = buildPcmWavFixture(
          rate: rate,
          junk: true,
          extended: true,
          dataFirst: dataFirst,
        );
        final file = await File('${dir.path}/input.wav').writeAsBytes(bytes);
        final handle = await file.open();
        try {
          final expected = decodePcmWav(bytes);
          final actual = await scanPcmWavFile(handle);
          expect(actual.format.matches(expected.format), isTrue);
          expect(actual.dataOffset, expected.dataOffset);
          expect(actual.dataLength, expected.dataLength);
          expect(actual.frameCount, expected.frameCount);
          // The caller still owns a usable handle after scanning.
          expect(await handle.length(), bytes.length);
        } finally {
          await handle.close();
        }
      });
    }
  }
  for (final entry in malformedPcmWavFixtures().entries) {
    test('file rejects ${entry.key} like bytes', () async {
      final file = await File(
        '${dir.path}/input.wav',
      ).writeAsBytes(entry.value);
      final handle = await file.open();
      try {
        await expectLater(scanPcmWavFile(handle), throwsFormatException);
      } finally {
        await handle.close();
      }
    });
  }
  test(
    'large sparse payload and metadata need only bounded structural reads',
    () async {
      const payloadLength = 512 * 1024 * 1024;
      const junkLength = 256 * 1024 * 1024;
      final small = buildPcmWavFixture();
      final handle = await File(
        '${dir.path}/sparse.wav',
      ).open(mode: FileMode.write);
      try {
        final riff = ByteData(12)
          ..setUint32(0, 0x46464952, Endian.little)
          ..setUint32(
            4,
            4 + 8 + junkLength + 24 + 8 + payloadLength,
            Endian.little,
          )
          ..setUint32(8, 0x45564157, Endian.little);
        await handle.writeFrom(riff.buffer.asUint8List());
        final junk = fixtureChunk('JUNK', []).sublist(0, 8);
        final junkHeader = Uint8List.fromList(junk);
        ByteData.sublistView(
          junkHeader,
        ).setUint32(4, junkLength, Endian.little);
        await handle.writeFrom(junkHeader);
        await handle.setPosition(20 + junkLength);
        await handle.writeFrom(small.sublist(12, 44));
        await handle.setPosition(20 + junkLength + 24 + 4);
        final lengthBytes = ByteData(4)
          ..setUint32(0, payloadLength, Endian.little);
        await handle.writeFrom(lengthBytes.buffer.asUint8List());
        await handle.truncate(20 + junkLength + 24 + 8 + payloadLength);
        final measured = _MeasuredFile(handle);
        final layout = await scanPcmWavFile(measured);
        expect(layout.dataLength, payloadLength);
        expect(layout.frameCount, payloadLength ~/ 2);
        expect(measured.readSizes, [12, 8, 8, 16, 8]);
        expect(measured.readSizes.reduce((a, b) => a + b), 52);
      } finally {
        await handle.close();
      }
    },
  );
  test(
    'short read after extent check fails without taking handle ownership',
    () async {
      final file = await File(
        '${dir.path}/input.wav',
      ).writeAsBytes(buildPcmWavFixture());
      final handle = await file.open();
      final measured = _MeasuredFile(handle, shortReadAt: 3);
      try {
        await expectLater(scanPcmWavFile(measured), throwsFormatException);
        expect(measured.readSizes, [12, 8, 16]);
        expect(await handle.length(), greaterThan(0));
      } finally {
        await handle.close();
      }
    },
  );
  test(
    'checkpoint cancellation stops scanning and leaves close to caller',
    () async {
      final file = await File(
        '${dir.path}/input.wav',
      ).writeAsBytes(buildPcmWavFixture(junk: true));
      final handle = await file.open();
      final measured = _MeasuredFile(handle);
      var checkpoints = 0;
      try {
        await expectLater(
          scanPcmWavFile(
            measured,
            checkpoint: () {
              if (++checkpoints == 5) throw StateError('cancelled');
            },
          ),
          throwsStateError,
        );
        expect(measured.readSizes, [12]);
        expect(await handle.length(), greaterThan(0));
      } finally {
        await handle.close();
      }
    },
  );
}

class _MeasuredFile implements RandomAccessFile {
  _MeasuredFile(this.file, {this.shortReadAt});
  final RandomAccessFile file;
  final int? shortReadAt;
  final readSizes = <int>[];
  @override
  Future<int> length() => file.length();
  @override
  Future<RandomAccessFile> setPosition(int position) async {
    await file.setPosition(position);
    return this;
  }

  @override
  Future<Uint8List> read(int bytes) {
    readSizes.add(bytes);
    return file.read(readSizes.length == shortReadAt ? bytes - 1 : bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
