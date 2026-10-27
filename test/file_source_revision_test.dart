import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/file_source_revision.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('source-revision-'),
  );
  tearDown(() => directory.delete(recursive: true));

  test(
    'metadata revision handles large sparse files without a source read',
    () async {
      final file = File('${directory.path}/large.txt');
      final handle = await file.open(mode: FileMode.write);
      await handle.truncate(1024 * 1024 * 1024);
      await handle.close();
      final revision = await fileSourceRevision(file.path);
      expect(revision, startsWith('file-stat-v2:'));
      expect(await fileSourceRevision(file.path), revision);
      await requireFileSourceRevision(file.path, revision!);
      expect(await fileSourceRevision(directory.path), isNull);
      expect(await fileSourceRevision('${directory.path}/missing.txt'), isNull);
    },
  );

  test('canonical targets share identity; retargeted symlinks miss', () async {
    final first = await File(
      '${directory.path}/first.txt',
    ).writeAsString('first');
    final second = await File(
      '${directory.path}/second.txt',
    ).writeAsString('other');
    final link = await Link('${directory.path}/link.txt').create(first.path);
    final revision = await fileSourceRevision(first.path);
    expect(await fileSourceRevision(link.path), revision);
    await link.update(second.path);
    expect(await fileSourceRevision(link.path), isNot(revision));
    await expectLater(
      requireFileSourceRevision(link.path, revision!),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'sub-millisecond rewrite collides in Dart precision but native revision changes',
    () async {
      final file = await File(
        '${directory.path}/book.txt',
      ).writeAsString('first');
      const firstCtime = 2000123456;
      const nextCtime = 2000123987;
      expect(
        DateTime.fromMicrosecondsSinceEpoch(firstCtime).millisecondsSinceEpoch,
        DateTime.fromMicrosecondsSinceEpoch(nextCtime).millisecondsSinceEpoch,
      );
      final before = await fileSourceRevision(
        file.path,
        metadataProbe: (_) async =>
            '1:2:0:5:1000.123456789:2000.123456789:100644:Regular File',
      );
      final after = await fileSourceRevision(
        file.path,
        metadataProbe: (_) async =>
            '1:2:0:5:1000.123456789:2000.123987654:100644:Regular File',
      );
      expect(before, isNotNull);
      expect(after, isNot(before));
      expect(
        await fileSourceRevision(file.path, metadataProbe: (_) async => null),
        isNull,
      );
      expect(
        await fileSourceRevision(
          file.path,
          metadataProbe: (_) async => 'coarse-or-unsupported',
        ),
        isNull,
      );
    },
  );

  test(
    'a same-length rewrite with restored mtime still changes ctime',
    () async {
      final file = await File(
        '${directory.path}/book.txt',
      ).writeAsString('first');
      // Choose a distinct mtime explicitly; no scheduler delay decides the test.
      await file.setLastModified(DateTime(2020));
      final modified = (await file.stat()).modified;
      final revision = await fileSourceRevision(file.path);
      await file.writeAsString('other');
      await file.setLastModified(modified);
      expect(await fileSourceRevision(file.path), isNot(revision));
    },
  );
}
