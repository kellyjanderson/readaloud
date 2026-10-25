import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_voice_repository.dart';

void main() {
  late Directory directory;
  late KokoroVoiceRepository repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kokoro-voice-test-');
    repository = KokoroVoiceRepository(voicesDirectory: directory.path);
  });
  tearDown(() async => directory.delete(recursive: true));
  Future<void> write(Uint8List bytes) =>
      File('${directory.path}/af_heart.npy').writeAsBytes(bytes);

  test('510x1x256 archive is cached until clear, then reread', () async {
    await write(_npy([510, 1, 256], first: 0.25));
    final first = await repository.loadVoice('af_heart');
    expect(first.styleVectors.length, 510);
    expect(first.styleVectors.every((row) => row.length == 256), isTrue);
    expect(first.styleVectors.first.first, 0.25);
    expect(repository.loadedVoiceCount, 1);
    await write(_npy([510, 1, 256], first: 0.5));
    expect(await repository.loadVoice('af_heart'), same(first));
    repository.clear();
    expect(repository.loadedVoiceCount, 0);
    final refreshed = await repository.loadVoice('af_heart');
    expect(refreshed, isNot(same(first)));
    expect(refreshed.styleVectors.first.first, 0.5);
  });

  for (final shape in <List<int>>[
    [],
    [0, 1, 256],
    [513, 1, 256],
    [510, 1, 255],
    [510],
  ]) {
    test('rejects incompatible shape $shape without caching', () async {
      await write(_npy(shape));
      await expectLater(
        repository.loadVoice('af_heart'),
        throwsFormatException,
      );
      expect(repository.loadedVoiceCount, 0);
    });
  }
  for (final value in [double.nan, double.infinity, double.negativeInfinity]) {
    test('rejects nonfinite vector value $value', () async {
      await write(_npy([510, 1, 256], first: value));
      await expectLater(
        repository.loadVoice('af_heart'),
        throwsFormatException,
      );
      expect(repository.loadedVoiceCount, 0);
    });
  }
  test('rejects truncated payload and retries repaired file', () async {
    final valid = _npy([510, 1, 256]);
    await write(Uint8List.sublistView(valid, 0, valid.length - 1));
    await expectLater(repository.loadVoice('af_heart'), throwsFormatException);
    expect(repository.loadedVoiceCount, 0);
    await write(valid);
    expect((await repository.loadVoice('af_heart')).styleVectors.length, 510);
  });
  test('rejects truncated header with a format error', () async {
    await write(Uint8List.sublistView(_npy([510, 1, 256]), 0, 16));
    await expectLater(repository.loadVoice('af_heart'), throwsFormatException);
    expect(repository.loadedVoiceCount, 0);
  });
  for (final id in [
    '',
    '../af_heart',
    '/af_heart',
    r'..\af_heart',
    'af heart',
    'af_heart.npy',
  ]) {
    test(
      'rejects invalid voice ID ${jsonEncode(id)} before file access',
      () async {
        await expectLater(repository.loadVoice(id), throwsFormatException);
        expect(repository.loadedVoiceCount, 0);
      },
    );
  }
}

// Small deterministic NPY v1 fixture, independent of installed model assets.
Uint8List _npy(List<int> shape, {double first = 0}) {
  final tuple = shape.isEmpty ? '' : '${shape.join(', ')},';
  final header =
      "{'descr': '<f4', 'fortran_order': False, 'shape': ($tuple), }";
  final padding = (16 - ((10 + header.length + 1) % 16)) % 16;
  final headerBytes = ascii.encode('$header${' ' * padding}\n');
  final count = shape.isEmpty ? 0 : shape.fold<int>(1, (a, b) => a * b);
  final bytes = Uint8List(10 + headerBytes.length + count * 4);
  bytes.setAll(0, [0x93, ...ascii.encode('NUMPY'), 1, 0]);
  final data = ByteData.sublistView(bytes);
  data.setUint16(8, headerBytes.length, Endian.little);
  bytes.setAll(10, headerBytes);
  if (count > 0) data.setFloat32(10 + headerBytes.length, first, Endian.little);
  return bytes;
}
