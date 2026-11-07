import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:read_aloud/src/services/packaged_python_runtime.dart';

void main() {
  late Directory temp, source, resources, support;
  late PackagedPythonRuntimeOwner owner;
  Map<String, dynamic> manifest() =>
      jsonDecode(
            File(
              p.join(resources.path, 'python-runtimes/mlx.json'),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  void writeManifest(Map<String, dynamic> value, {bool identity = true}) {
    if (identity) {
      final content = {
        for (final key in [
          'policy',
          'runtimeId',
          'python',
          'packages',
          'executable',
          'entries',
        ])
          key: value[key],
      };
      value['signedTreeDigest'] = sha256
          .convert(utf8.encode(jsonEncode(content)))
          .toString();
    }
    File(
      p.join(resources.path, 'python-runtimes/mlx.json'),
    ).writeAsStringSync(jsonEncode(value));
  }

  Future<void> command(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  Future<void> package() => command('/usr/bin/ruby', [
    'tools/package_python_runtime.rb',
    source.path,
    'mlx',
    'bin/python',
    p.join(resources.path, 'python-runtimes'),
  ]);
  PackagedRuntimeLease acquire({
    void Function(Map<String, dynamic>)? onProgress,
    bool verify = false,
    PackagedPythonRuntimeOwner? other,
    Duration timeout = const Duration(minutes: 1),
  }) => (other ?? owner).acquire(
    runtimeId: 'mlx',
    resources: resources,
    support: support,
    consumerRevision: 'test/revision',
    onProgress: onProgress,
    verifyExecutable: verify,
    timeout: timeout,
  );
  Future<void> noStaging() async {
    final root = Directory(p.join(support.path, 'python-runtimes/v1/mlx'));
    if (await root.exists()) {
      expect(
        await root
            .list()
            .where((e) => p.basename(e.path).contains('-attempt-'))
            .toList(),
        isEmpty,
      );
    }
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('readaloud-runtime-test-');
    source = await Directory(p.join(temp.path, 'standalone')).create();
    await Directory(
      p.join(source.path, 'include/python3.12'),
    ).create(recursive: true);
    await File(
      p.join(source.path, 'include/python3.12/patchlevel.h'),
    ).writeAsString('#define PY_VERSION "3.12.99"\n');
    resources = await Directory(p.join(temp.path, 'Resources')).create();
    support = Directory(p.join(temp.path, 'support'));
    await Directory(p.join(source.path, 'bin')).create();
    await File(
      p.join(source.path, 'bin/python'),
    ).writeAsString('#!/bin/sh\necho "Python fixture"\n');
    await command('/bin/chmod', ['755', p.join(source.path, 'bin/python')]);
    await File(
      p.join(source.path, 'license'),
    ).writeAsString('preserved license');
    await Link(p.join(source.path, 'bin/alias')).create('python');
    owner = PackagedPythonRuntimeOwner();
    await package();
  });
  tearDown(() async {
    await owner.shutdown();
    await temp.delete(recursive: true);
  });

  test(
    'real ditto roundtrip preserves modes, relative links and relocated execution; immutable reuse',
    () async {
      final progress = <Map<String, dynamic>>[];
      final lease = acquire(onProgress: progress.add);
      final executable = await lease.executable;
      expect(
        (await Process.run(executable, ['--version'])).stdout,
        'Python fixture\n',
      );
      expect(
        await Link(p.join(p.dirname(executable), 'alias')).target(),
        'python',
      );
      expect((await File(executable).stat()).mode & 511, 493);
      await lease.cancelAndDrain();
      final modified = (await File(executable).stat()).modified;
      final reused = acquire();
      expect(await reused.executable, executable);
      expect((await File(executable).stat()).modified, modified);
      await reused.cancelAndDrain();
      expect(
        progress.map((e) => e['stage']),
        containsAll([
          'runtimeArchive',
          'runtimeExtract',
          'runtimeTree',
          'runtimePublish',
        ]),
      );
      expect(
        progress.every((e) => e['consumerRevision'] == 'test/revision'),
        true,
      );
      expect(
        progress.where((e) => e['stage'] == 'runtimeExtract').single['total'],
        isNull,
      );
      await noStaging();
    },
  );
  test(
    'same-identity consumers share one attempt and cancel independently',
    () async {
      final stages = <String>[];
      final first = acquire(
        onProgress: (e) => stages.add(e['stage'] as String),
      );
      final second = acquire();
      final failure = expectLater(
        first.executable,
        throwsA(isA<PackagedRuntimeCancelled>()),
      );
      await first.cancelAndDrain();
      await failure;
      expect(await second.executable, contains('/python-runtimes/v1/mlx/'));
      await second.cancelAndDrain();
      expect(
        stages.where((s) => s == 'runtimeExtract').length,
        lessThanOrEqualTo(1),
      );
      await noStaging();
    },
  );
  test(
    'independent publishers atomically reuse one immutable winner',
    () async {
      final other = PackagedPythonRuntimeOwner();
      addTearDown(other.shutdown);
      final first = acquire();
      final second = acquire(other: other);
      final values = await Future.wait([first.executable, second.executable]);
      expect(values[0], values[1]);
      await first.cancelAndDrain();
      await second.cancelAndDrain();
      await noStaging();
    },
  );
  test(
    'changed signed content produces a different path while preserving old readers',
    () async {
      final first = acquire();
      final old = await first.executable;
      await first.cancelAndDrain();
      await File(
        p.join(source.path, 'license'),
      ).writeAsString('new preserved license');
      await package();
      final second = acquire();
      expect(await second.executable, isNot(old));
      expect(
        await File(p.join(p.dirname(p.dirname(old)), 'license')).readAsString(),
        'preserved license',
      );
      await second.cancelAndDrain();
    },
  );
  test('corrupt archive fails and leaves no staging', () async {
    final archive = File(p.join(resources.path, 'python-runtimes/mlx.zip'));
    final bytes = await archive.readAsBytes();
    bytes[bytes.length ~/ 2] ^= 1;
    await archive.writeAsBytes(bytes);
    final lease = acquire();
    await expectLater(lease.executable, throwsStateError);
    await lease.cancelAndDrain();
    await noStaging();
  });
  test('manifest digest mismatch is rejected', () async {
    final value = manifest()..['python'] = 'unrelated';
    writeManifest(value, identity: false);
    final lease = acquire();
    await expectLater(lease.executable, throwsStateError);
    await lease.cancelAndDrain();
  });
  for (final corruption in [
    'path',
    'link',
    'mode',
    'hash',
    'inventory',
    'executable',
  ]) {
    test(
      'rejects unsafe or mismatched $corruption before publication',
      () async {
        final value = manifest();
        final entries = (value['entries'] as List).cast<Map<String, dynamic>>();
        final file = entries.firstWhere((e) => e['path'] == 'license');
        switch (corruption) {
          case 'path':
            file['path'] = '../escape';
          case 'link':
            entries.firstWhere((e) => e['type'] == 'link')['target'] =
                '../../outside';
          case 'mode':
            file['mode'] = 511;
          case 'hash':
            file['sha256'] = '0' * 64;
          case 'inventory':
            entries.remove(file);
          case 'executable':
            value['executable'] = 'license';
        }
        writeManifest(value);
        final lease = acquire();
        await expectLater(lease.executable, throwsStateError);
        await lease.cancelAndDrain();
        await noStaging();
      },
    );
  }
  for (final corruption in ['file', 'receipt', 'extra', 'empty']) {
    test(
      'corrupt published $corruption fails without repair or replacement',
      () async {
        final first = acquire();
        final executable = await first.executable;
        await first.cancelAndDrain();
        final tree = Directory(p.dirname(p.dirname(executable)));
        switch (corruption) {
          case 'file':
            await File(executable).writeAsString('corrupt');
          case 'receipt':
            await File(p.join(tree.path, '.complete.json')).writeAsString('{}');
          case 'extra':
            await File(p.join(tree.path, 'extra')).writeAsString('unexpected');
          case 'empty':
            await tree.delete(recursive: true);
            await tree.create();
        }
        final before = await tree
            .list(recursive: true)
            .map((e) => e.path)
            .toList();
        final retry = acquire();
        await expectLater(retry.executable, throwsStateError);
        await retry.cancelAndDrain();
        expect(
          await tree.list(recursive: true).map((e) => e.path).toList(),
          before,
        );
        await noStaging();
      },
    );
  }
  for (final stage in ['runtimeArchive', 'runtimeExtract', 'runtimeTree']) {
    test(
      'last-interest cancellation during $stage settles immediately and drains staging',
      () async {
        late PackagedRuntimeLease lease;
        Future<void>? drain;
        lease = acquire(
          onProgress: (e) {
            if (e['stage'] == stage) drain ??= lease.cancelAndDrain();
          },
        );
        await expectLater(
          lease.executable,
          throwsA(isA<PackagedRuntimeCancelled>()),
        );
        await drain;
        await noStaging();
      },
    );
  }
  test('deadline drains owned work and reports actionable failure', () async {
    final lease = acquire(timeout: Duration.zero);
    await expectLater(
      lease.executable,
      throwsA(predicate((Object e) => '$e'.contains('deadline'))),
    );
    await lease.cancelAndDrain();
    await noStaging();
  });
  test(
    'shutdown immediately cancels consumer, drains worker and rejects admission',
    () async {
      final lease = acquire();
      final result = expectLater(
        lease.executable,
        throwsA(isA<PackagedRuntimeCancelled>()),
      );
      await owner.shutdown();
      await result;
      expect(acquire, throwsStateError);
      await noStaging();
    },
  );
  test(
    'real signed arm64 executable passes production verifier after extraction',
    () async {
      final c = File(p.join(temp.path, 'tiny.c'));
      await c.writeAsString(
        '#include <stdio.h>\nint main(void) { puts("Python signed fixture"); return 0; }\n',
      );
      final executable = p.join(source.path, 'bin/python');
      await command('/usr/bin/clang', [
        '-arch',
        'arm64',
        c.path,
        '-o',
        executable,
      ]);
      await command('/usr/bin/codesign', [
        '--force',
        '--sign',
        '-',
        '--entitlements',
        'tools/mlx_python.entitlements',
        executable,
      ]);
      await package();
      final lease = acquire(verify: true);
      final installed = await lease.executable;
      expect(await File(installed).length(), greaterThan(0));
      await command('/usr/bin/codesign', ['--verify', '--strict', installed]);
      final entitlements = await Process.run('/usr/bin/codesign', [
        '-d',
        '--entitlements',
        ':-',
        installed,
      ]);
      expect(
        '${entitlements.stdout}${entitlements.stderr}',
        contains('com.apple.security.inherit'),
      );
      await lease.cancelAndDrain();
    },
  );
  test(
    'observer failure drains its interest without interrupting another consumer',
    () async {
      final first = acquire(
        onProgress: (_) => throw StateError('observer failed'),
      );
      final second = acquire();
      await expectLater(first.executable, throwsStateError);
      expect(await second.executable, contains('/python-runtimes/v1/mlx/'));
      await first.cancelAndDrain();
      await second.cancelAndDrain();
      await noStaging();
    },
  );
  test(
    'bounded interests reject excessive admission; no pending queue',
    () async {
      final leases = List.generate(16, (_) => acquire());
      expect(acquire, throwsStateError);
      await owner.shutdown();
      for (final lease in leases) {
        await expectLater(
          lease.executable,
          throwsA(isA<PackagedRuntimeCancelled>()),
        );
        await lease.cancelAndDrain();
      }
      await noStaging();
    },
  );
  test(
    'linked publication parent is rejected without writing outside support',
    () async {
      await support.create();
      final outside = await Directory(p.join(temp.path, 'outside')).create();
      await Link(p.join(support.path, 'python-runtimes')).create(outside.path);
      final lease = acquire();
      await expectLater(lease.executable, throwsStateError);
      await lease.cancelAndDrain();
      expect(await outside.list().toList(), isEmpty);
    },
  );
}
