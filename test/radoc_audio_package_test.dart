import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/radoc_audio_manifest.dart';
import 'package:read_aloud/src/services/radoc_audio_package.dart';

void main() {
  late Directory temp;
  late RadocAudioPackage service;
  late Map<String, File> files;
  late RadocAudioManifest manifest;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('radoc-package-test-');
    service = RadocAudioPackage(
      cacheDirectory: Directory('${temp.path}/cache'),
    );
    files = {
      'prepared/0.json': await File('${temp.path}/range0').writeAsString(
        jsonEncode({
          'globalStartWord': 0,
          'text': 'First range.',
          'voice': 'narrator',
        }),
      ),
      'prepared/1.json': await File('${temp.path}/range1').writeAsString(
        jsonEncode({
          'globalStartWord': 2,
          'text': 'Second range.',
          'directions': ['softly'],
        }),
      ),
      'analysis/0.json': await File('${temp.path}/analysis').writeAsString(
        jsonEncode({
          'characters': [
            {'id': 'c1', 'voice': 'explicit-choice'},
          ],
        }),
      ),
      'audio/0.wav': await File('${temp.path}/audio0').writeAsBytes(_wav()),
    };
    manifest = _manifest();
  });

  tearDown(() async {
    await service.dispose();
    await temp.delete(recursive: true);
  });

  Future<File> exportBook() async {
    final output = File('${temp.path}/book.radoc');
    await service.export(
      destination: output,
      manifest: manifest,
      members: files,
    );
    return output;
  }

  test(
    'copied book retains independent prepared/analysis/intent/audio offline',
    () async {
      final original = await exportBook();
      final copied = await original.copy('${temp.path}/copied.radoc');
      final expected = {
        for (final entry in files.entries)
          entry.key: await entry.value.readAsBytes(),
      };
      for (final file in files.values) {
        await file.delete();
      }
      await original.delete();
      expect(await RadocAudioPackage.isPackage(copied), isTrue);
      final book = await service.open(copied);
      expect(book.manifest.documentId, 'document-1');
      expect(book.manifest.preparationComplete, isTrue);
      expect(book.manifest.renderingComplete, isFalse);
      expect(book.manifest.preparedRanges.map((r) => r.startWord), [0, 2]);
      expect(book.manifest.intent, {'narratorVoice': 'explicit-choice'});
      expect(book.manifest.scenes.single.dependencies['direction'], 'softly');
      expect(book.manifest.scenes.single.provenance['turns'], [
        {'characterId': 'c1', 'startWord': 0, 'endWord': 2},
      ]);
      expect(book.manifestDigest, matches(RegExp(r'^[a-f0-9]{64}$')));
      for (final entry in expected.entries) {
        final materialized = await service.materializeMember(book, entry.key);
        expect(await materialized.readAsBytes(), entry.value);
        expect(materialized.path, isNot(contains(entry.key)));
      }
      await expectLater(
        service.materializeMember(book, '../outside'),
        throwsA(isA<RadocPackageException>()),
      );
      final cached = await service.materializeMember(book, 'audio/0.wav');
      await service.dispose();
      expect(await cached.exists(), isFalse);
      expect(await copied.exists(), isTrue);
    },
  );

  test(
    'partial preparation is distinct from partial audio and complete coverage',
    () {
      final partial = _manifest(preparationComplete: false, secondRange: false);
      partial.validate(requireMembers: false);
      expect(partial.preparationComplete, isFalse);
      expect(partial.renderingComplete, isFalse);
      expect(
        () => _manifest(secondRange: false).validate(requireMembers: false),
        throwsFormatException,
      );
      final complete = RadocAudioManifest(
        documentId: 'document-1',
        sourceId: 'source-1',
        preparationComplete: true,
        totalWords: 2,
        preparedRanges: [
          const RadocPreparedRange(
            member: 'prepared/0.json',
            startWord: 0,
            endWord: 2,
          ),
        ],
        analysisMembers: [],
        scenes: [_scene()],
      );
      complete.validate(requireMembers: false);
      expect(complete.renderingComplete, isTrue);
    },
  );

  test(
    'DEFLATE uses streaming decoder and independently verifies member CRC',
    () async {
      final members = {
        for (final entry in files.entries)
          entry.key: await entry.value.readAsBytes(),
      };
      final checked = _checksummed(manifest, members);
      final zip = await _writeZip(temp, checked, members, compress: true);
      final book = await service.open(zip);
      for (final entry in members.entries) {
        expect(
          await (await service.materializeMember(
            book,
            entry.key,
          )).readAsBytes(),
          entry.value,
        );
      }
    },
  );

  test(
    'later missing member remains a demand error while initial range works',
    () async {
      final members = {
        for (final entry in files.entries)
          entry.key: await entry.value.readAsBytes(),
      };
      final checked = _checksummed(manifest, members);
      members.remove('prepared/1.json');
      final zip = await _writeZip(temp, checked, members);
      final book = await service.open(zip);
      expect(
        await (await service.materializeMember(
          book,
          'prepared/0.json',
        )).exists(),
        isTrue,
      );
      await expectLater(
        service.materializeMember(book, 'prepared/1.json'),
        throwsA(isA<RadocPackageException>()),
      );
    },
  );

  test('tampered stored payload passes open but fails demand CRC', () async {
    final zip = await exportBook();
    final bytes = await zip.readAsBytes();
    final needle = utf8.encode('Second range.');
    final at = _indexOf(bytes, needle);
    expect(at, greaterThan(0));
    bytes[at] ^= 1;
    await zip.writeAsBytes(bytes);
    final book = await service.open(zip);
    await service.materializeMember(book, 'prepared/0.json');
    await expectLater(
      service.materializeMember(book, 'prepared/1.json'),
      throwsA(isA<RadocPackageException>()),
    );
  });

  test('valid ZIP CRC cannot replace the manifest SHA-256', () async {
    final members = {
      for (final entry in files.entries)
        entry.key: await entry.value.readAsBytes(),
    };
    final checked = _checksummed(manifest, members);
    final changed = Uint8List.fromList(members['prepared/1.json']!);
    changed[4] ^= 1;
    members['prepared/1.json'] = changed;
    final zip = await _writeZip(temp, checked, members);
    final book = await service.open(zip);
    await expectLater(
      service.materializeMember(book, 'prepared/1.json'),
      throwsA(predicate((e) => e.toString().contains('SHA-256'))),
    );
  });

  test(
    'duplicate ZIP names and unsafe/aliased paths fail before extraction',
    () async {
      final members = {
        for (final entry in files.entries)
          entry.key: await entry.value.readAsBytes(),
      };
      final checked = _checksummed(manifest, members);
      for (final name in [
        'prepared/0.json',
        '../outside',
        '/absolute',
        'a/../alias',
        r'a\backslash',
        'UPPER.json',
        'a//empty',
        './dot',
        'a/./dot',
      ]) {
        final zip = await _writeZip(
          temp,
          checked,
          members,
          extra: ArchiveFile.bytes(name, [1, 2]),
        );
        await expectLater(
          service.open(zip),
          throwsA(isA<RadocPackageException>()),
          reason: name,
        );
      }
      expect(await File('${temp.parent.path}/outside').exists(), isFalse);
    },
  );

  test(
    'ZIP symlink and unknown compression fail without inflating a link',
    () async {
      final members = {
        for (final entry in files.entries)
          entry.key: await entry.value.readAsBytes(),
      };
      final checked = _checksummed(manifest, members);
      final zip = await _writeZip(
        temp,
        checked,
        members,
        extra: ArchiveFile.bytes('evil.link', utf8.encode('/tmp/outside'))
          ..mode = 0xa1ff,
      );
      await expectLater(
        service.open(zip),
        throwsA(isA<RadocPackageException>()),
      );
      final good = await exportBook();
      final bytes = await good.readAsBytes();
      final central = _indexOf(bytes, [0x50, 0x4b, 1, 2]);
      ByteData.sublistView(bytes).setUint16(central + 10, 99, Endian.little);
      await good.writeAsBytes(bytes);
      await expectLater(
        service.open(good),
        throwsA(isA<RadocPackageException>()),
      );
    },
  );

  test('member/directory/archive/count limits fail explicitly', () async {
    final zip = await exportBook();
    for (final limits in [
      const RadocPackageLimits(maxMemberBytes: 8),
      const RadocPackageLimits(maxManifestBytes: 8),
      const RadocPackageLimits(maxDirectoryBytes: 8),
      const RadocPackageLimits(maxMembers: 2),
      const RadocPackageLimits(maxArchiveBytes: 8),
      const RadocPackageLimits(maxTotalMemberBytes: 8),
    ]) {
      final bounded = RadocAudioPackage(limits: limits);
      try {
        await expectLater(
          bounded.open(zip),
          throwsA(isA<RadocPackageException>()),
        );
      } finally {
        await bounded.dispose();
      }
    }
  });

  test('WAV format/frame mismatch cannot be committed', () async {
    files['audio/0.wav'] = await File(
      '${temp.path}/invalid-audio',
    ).writeAsBytes(_wav(frames: 17));
    final destination = await File(
      '${temp.path}/prior.radoc',
    ).writeAsString('prior-output');
    await expectLater(
      service.export(
        destination: destination,
        manifest: manifest,
        members: files,
      ),
      throwsA(isA<RadocPackageException>()),
    );
    expect(await destination.readAsString(), 'prior-output');
    expect(await files['audio/0.wav']!.exists(), isTrue);
  });

  test(
    'progress reports actual stage counts and cancellation during copying drains',
    () async {
      await files['prepared/0.json']!.writeAsString(
        '"${'x' * (3 * 1024 * 1024)}"',
      );
      final destination = await File(
        '${temp.path}/prior.radoc',
      ).writeAsString('prior-output');
      final progress = <RadocPackageProgress>[];
      Future<void>? drain;
      await service.dispose();
      service = RadocAudioPackage(
        onProgress: (event) {
          progress.add(event);
          if (event.stage == 'copy' && event.completed > 0 && drain == null) {
            drain = service.cancelAndDrain();
          }
        },
      );
      await expectLater(
        service.export(
          destination: destination,
          manifest: manifest,
          members: files,
        ),
        throwsA(isA<RadocPackageCancelled>()),
      );
      await drain;
      expect(
        progress.any((p) => p.stage == 'copy' && p.completed >= 1024 * 1024),
        isTrue,
      );
      expect(
        progress.where((p) => p.stage == 'copy').last.completed,
        lessThan(await files['prepared/0.json']!.length()),
      );
      for (final event in progress) {
        expect(event.completed, greaterThanOrEqualTo(0));
        if (event.total != null) {
          expect(event.completed, lessThanOrEqualTo(event.total!));
        }
      }
      expect(await destination.readAsString(), 'prior-output');
      expect(
        await temp.list().any((e) => e.path.contains('.radoc-stage-')),
        isFalse,
      );
    },
  );

  test(
    'emitted decompression bytes cannot exceed a forged declared size',
    () async {
      final expanded = utf8.encode('x' * (1024 * 1024));
      final forged = RadocAudioManifest(
        documentId: 'bomb',
        sourceId: 'source',
        preparationComplete: true,
        totalWords: 1,
        preparedRanges: [
          const RadocPreparedRange(
            member: 'prepared/0.json',
            startWord: 0,
            endWord: 1,
          ),
        ],
        analysisMembers: [],
        scenes: [],
        members: [
          RadocAudioMember(
            name: 'prepared/0.json',
            sizeBytes: 8,
            sha256: sha256.convert(expanded).toString(),
          ),
        ],
      );
      final encoder = ZipEncoder();
      final output = OutputMemoryStream();
      encoder.startEncode(output);
      encoder.add(
        ArchiveFile.string('manifest.json', jsonEncode(forged.toJson())),
      );
      encoder.add(ArchiveFile.bytes('prepared/0.json', expanded)..size = 8);
      encoder.endEncode();
      final zip = await File(
        '${temp.path}/bomb.radoc',
      ).writeAsBytes(output.getBytes());
      final book = await service.open(zip);
      await expectLater(
        service.materializeMember(book, 'prepared/0.json'),
        throwsA(predicate((e) => e.toString().contains('emitted member size'))),
      );
    },
  );

  test(
    'symlink input is rejected without changing its target or existing output',
    () async {
      final target = files['prepared/0.json']!;
      final before = await target.readAsBytes();
      final link = await Link('${temp.path}/input-link').create(target.path);
      files['prepared/0.json'] = File(link.path);
      final destination = await File(
        '${temp.path}/prior.radoc',
      ).writeAsString('prior-output');
      await expectLater(
        service.export(
          destination: destination,
          manifest: manifest,
          members: files,
        ),
        throwsA(isA<RadocPackageException>()),
      );
      expect(await destination.readAsString(), 'prior-output');
      expect(await target.readAsBytes(), before);
    },
  );

  test(
    'cancel drains, rejects overlap and preserves previous output/source',
    () async {
      final destination = await File(
        '${temp.path}/prior.radoc',
      ).writeAsString('prior-output');
      final future = service.export(
        destination: destination,
        manifest: manifest,
        members: files,
      );
      final rejected = expectLater(
        future,
        throwsA(isA<RadocPackageCancelled>()),
      );
      await expectLater(service.open(destination), throwsStateError);
      await service.cancelAndDrain();
      await rejected;
      expect(await destination.readAsString(), 'prior-output');
      expect(await files['prepared/0.json']!.exists(), isTrue);
      expect(
        await temp.list().any((e) => e.path.contains('.radoc-stage-')),
        isFalse,
      );
      await exportBook(); // Lane can be reused after the worker is drained.
    },
  );

  test(
    'stale publication check rejects finished export without replacing output',
    () async {
      final destination = await File(
        '${temp.path}/prior.radoc',
      ).writeAsString('prior-output');
      var current = true;
      var sawPublication = false;
      await service.dispose();
      service = RadocAudioPackage(
        onProgress: (progress) {
          if (progress.stage == 'publication') {
            sawPublication = true;
            current = false;
          }
        },
      );
      await expectLater(
        service.export(
          destination: destination,
          manifest: manifest,
          members: files,
          isCurrent: () => current,
        ),
        throwsA(isA<RadocPackageCancelled>()),
      );
      expect(sawPublication, isTrue);
      expect(await destination.readAsString(), 'prior-output');
      expect(
        await temp.list().any((e) => e.path.contains('.radoc-stage-')),
        isFalse,
      );
    },
  );

  test('stale materialization cannot expose a late cached file', () async {
    var current = true;
    var staleOnAudio = false;
    await service.dispose();
    service = RadocAudioPackage(
      cacheDirectory: Directory('${temp.path}/cache'),
      onProgress: (progress) {
        if (staleOnAudio &&
            progress.stage == 'read' &&
            progress.member == 'audio/0.wav' &&
            progress.completed == progress.total) {
          current = false;
        }
      },
    );
    final book = await service.open(await exportBook());
    staleOnAudio = true;
    await expectLater(
      service.materializeMember(book, 'audio/0.wav', isCurrent: () => current),
      throwsA(isA<RadocPackageCancelled>()),
    );
    final cacheRoot = Directory('${temp.path}/cache');
    expect(
      await cacheRoot.list(recursive: true).where((e) => e is File).isEmpty,
      isTrue,
    );
    staleOnAudio = false;
    await service.materializeMember(book, 'audio/0.wav');
  });

  test(
    'unknown schemas fail and manifests are deeply immutable snapshots',
    () async {
      final direction = <String, dynamic>{
        'turns': [
          {'voice': 'original'},
        ],
      };
      final scene = RadocAudioScene(
        sceneId: 's',
        startWord: 0,
        endWord: 2,
        audioMember: 'audio/0.wav',
        dependencyDigest: 'a' * 64,
        dependencies: direction,
        provenance: {},
        sampleRate: 24000,
        channels: 1,
        frameCount: 16,
      );
      (direction['turns'] as List).clear();
      expect(scene.dependencies['turns'], hasLength(1));
      expect(
        () => (scene.dependencies['turns'] as List).clear(),
        throwsUnsupportedError,
      );
      final output = await exportBook();
      final book = await service.open(output);
      final json = book.manifest.toJson()..['version'] = 'radoc-v999';
      final archive = Archive()
        ..addFile(ArchiveFile.string('manifest.json', jsonEncode(json)));
      await output.writeAsBytes(ZipEncoder().encode(archive));
      await expectLater(
        service.open(output),
        throwsA(isA<RadocPackageException>()),
      );
    },
  );

  test('package replacement is detected before materialization', () async {
    final output = await exportBook();
    final book = await service.open(output);
    final replacement = RadocAudioManifest(
      documentId: 'replacement',
      sourceId: manifest.sourceId,
      preparationComplete: manifest.preparationComplete,
      totalWords: manifest.totalWords,
      preparedRanges: manifest.preparedRanges,
      analysisMembers: manifest.analysisMembers,
      scenes: manifest.scenes,
    );
    await service.export(
      destination: output,
      manifest: replacement,
      members: files,
    );
    await expectLater(
      service.materializeMember(book, 'audio/0.wav'),
      throwsA(isA<RadocPackageException>()),
    );
  });
}

RadocAudioManifest _manifest({
  bool preparationComplete = true,
  bool secondRange = true,
}) => RadocAudioManifest(
  documentId: 'document-1',
  sourceId: 'source-1',
  preparationComplete: preparationComplete,
  totalWords: 4,
  preparedRanges: [
    const RadocPreparedRange(
      member: 'prepared/0.json',
      startWord: 0,
      endWord: 2,
    ),
    if (secondRange)
      const RadocPreparedRange(
        member: 'prepared/1.json',
        startWord: 2,
        endWord: 4,
      ),
  ],
  analysisMembers: ['analysis/0.json'],
  scenes: [_scene()],
  intent: {'narratorVoice': 'explicit-choice'},
);

RadocAudioScene _scene() => RadocAudioScene(
  sceneId: 'scene-0',
  startWord: 0,
  endWord: 2,
  audioMember: 'audio/0.wav',
  dependencyDigest: 'a' * 64,
  dependencies: {
    'direction': 'softly',
    'voice': 'explicit-choice',
    'modelRevision': 'r1',
  },
  provenance: {
    'turns': [
      {'characterId': 'c1', 'startWord': 0, 'endWord': 2},
    ],
  },
  sampleRate: 24000,
  channels: 1,
  frameCount: 16,
);

RadocAudioManifest _checksummed(
  RadocAudioManifest manifest,
  Map<String, List<int>> members,
) => manifest.withMembers(
  members.entries.map(
    (entry) => RadocAudioMember(
      name: entry.key,
      sizeBytes: entry.value.length,
      sha256: sha256.convert(entry.value).toString(),
    ),
  ),
);

Future<File> _writeZip(
  Directory temp,
  RadocAudioManifest manifest,
  Map<String, List<int>> members, {
  bool compress = false,
  ArchiveFile? extra,
}) async {
  final encoder = ZipEncoder();
  final output = OutputMemoryStream();
  encoder.startEncode(output);
  encoder.add(
    ArchiveFile.string('manifest.json', jsonEncode(manifest.toJson()))
      ..compression = compress ? CompressionType.deflate : CompressionType.none,
  );
  for (final entry in members.entries) {
    encoder.add(
      ArchiveFile.bytes(entry.key, entry.value)
        ..compression = compress
            ? CompressionType.deflate
            : CompressionType.none,
    );
  }
  if (extra != null) encoder.add(extra);
  encoder.endEncode();
  return File('${temp.path}/hostile.radoc').writeAsBytes(output.getBytes());
}

Uint8List _wav({int frames = 16}) {
  final bytes = Uint8List(44 + frames * 2);
  final b = ByteData.sublistView(bytes);
  void tag(int offset, String value) =>
      bytes.setRange(offset, offset + 4, ascii.encode(value));
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
  b.setUint32(40, frames * 2, Endian.little);
  return bytes;
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var at = 0; at <= haystack.length - needle.length; at++) {
    var equal = true;
    for (var i = 0; i < needle.length; i++) {
      if (haystack[at + i] != needle[i]) {
        equal = false;
        break;
      }
    }
    if (equal) return at;
  }
  return -1;
}
