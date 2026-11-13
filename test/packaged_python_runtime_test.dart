import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:archive/archive_io.dart';
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
          'nativeRoot',
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
    String consumerRevision = 'test/revision',
    bool verify = false,
    PackagedPythonRuntimeOwner? other,
    Duration timeout = const Duration(minutes: 1),
  }) => (other ?? owner).acquire(
    runtimeId: 'mlx',
    resources: resources,
    support: support,
    consumerRevision: consumerRevision,
    onProgress: onProgress,
    verifyExecutable: verify,
    timeout: timeout,
  );
  Future<void> noStaging() async {
    final root = Directory(p.join(support.path, 'python-runtimes/v2/mlx'));
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
    final c = File(p.join(temp.path, 'fixture.c'));
    await c.writeAsString(
      '#include <stdio.h>\nint main(void) { puts("Python fixture"); return 0; }\n',
    );
    await command('/usr/bin/clang', [
      '-arch',
      'arm64',
      c.path,
      '-o',
      p.join(source.path, 'bin/python'),
    ]);
    await command('/usr/bin/codesign', [
      '--force',
      '--sign',
      '-',
      p.join(source.path, 'bin/python'),
    ]);
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
      final runtime = await lease.runtime;
      final executable = runtime.executable;
      expect(
        (await Process.run(executable, ['--version'])).stdout,
        'Python fixture\n',
      );
      expect(
        await Link(p.join(runtime.pythonHome, 'bin/alias')).target(),
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
      expect(
        (await second.runtime).pythonHome,
        contains('/python-runtimes/v2/mlx/'),
      );
      await second.cancelAndDrain();
      expect(
        stages.where((s) => s == 'runtimeExtract').length,
        lessThanOrEqualTo(1),
      );
      await noStaging();
    },
  );
  test(
    'platform digest covers empty, padding and stream boundaries across batches',
    () async {
      final sizes = [0, 1, 55, 56, 63, 64, 65, 65535, 65536, 65537, 196625];
      await Directory(p.join(source.path, 'digest')).create();
      final expected = <String, String>{};
      for (var index = 0; index < 35; index++) {
        final bytes = List.generate(
          sizes[index % sizes.length],
          (byte) => (byte * 37 + index * 19) & 255,
        );
        final name = 'digest/${index.toString().padLeft(2, '0')}';
        await File(p.join(source.path, name)).writeAsBytes(bytes);
        expected[name] = sha256.convert(bytes).toString();
      }
      await package();
      final entries = (manifest()['entries'] as List)
          .cast<Map<String, dynamic>>();
      for (final entry in entries.where(
        (e) => expected.containsKey(e['path']),
      )) {
        expect(entry['sha256'], expected[entry['path']]);
      }
      final first = acquire();
      final runtime = await first.runtime;
      await first.cancelAndDrain();
      final second = acquire();
      expect((await second.runtime).pythonHome, runtime.pythonHome);
      await second.cancelAndDrain();

      // Keep length and mode intact: only a complete byte digest detects this
      // corruption in a member beyond the first finite verification batch.
      final corrupt = File(p.join(runtime.pythonHome, 'digest/31'));
      final original = await corrupt.readAsBytes();
      final changed = List<int>.of(original)..[65536] ^= 1;
      await corrupt.writeAsBytes(changed);
      final rejected = acquire();
      await expectLater(rejected.runtime, throwsStateError);
      await rejected.cancelAndDrain();
      await corrupt.writeAsBytes(original);
      final retry = acquire();
      expect((await retry.runtime).pythonHome, runtime.pythonHome);
      await retry.cancelAndDrain();
      await noStaging();
    },
  );
  test(
    'cancellation drains admitted native peers before a fresh acquisition',
    () async {
      final executable = File(p.join(source.path, 'bin/python'));
      for (var index = 0; index < 34; index++) {
        await executable.copy(p.join(source.path, 'bin/native-$index'));
      }
      await package();
      late PackagedRuntimeLease lease;
      Future<void>? drain;
      final progress = <Map<String, dynamic>>[];
      lease = acquire(
        onProgress: (event) {
          progress.add(event);
          if (event['stage'] == 'runtimeNative') {
            drain ??= lease.cancelAndDrain();
          }
        },
      );
      await expectLater(
        lease.runtime,
        throwsA(isA<PackagedRuntimeCancelled>()),
      );
      await drain;
      await noStaging();
      final eventsAfterDrain = progress.length;
      final verified = <int>[];
      final retry = acquire(
        onProgress: (event) {
          if (event['stage'] == 'runtimeNative') {
            verified.add(event['completed'] as int);
          }
        },
      );
      await retry.runtime;
      await retry.cancelAndDrain();
      expect(verified.first, 1);
      expect(verified.last, 35);
      expect(verified.length, lessThan(35));
      expect(verified, orderedEquals(verified.toSet().toList()..sort()));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(progress.length, eventsAfterDrain);
      await noStaging();
    },
  );
  test(
    'replacement interest receives its own revision and no cancelled progress',
    () async {
      final executable = File(p.join(source.path, 'bin/python'));
      for (var index = 0; index < 34; index++) {
        await executable.copy(p.join(source.path, 'bin/native-$index'));
      }
      await package();
      final firstProgress = <Map<String, dynamic>>[];
      final replacementProgress = <Map<String, dynamic>>[];
      late PackagedRuntimeLease first;
      PackagedRuntimeLease? replacement;
      Future<void>? firstDrain;
      first = acquire(
        consumerRevision: 'old/revision',
        onProgress: (event) {
          firstProgress.add(event);
          if (event['stage'] == 'runtimeNative') {
            replacement ??= acquire(
              consumerRevision: 'replacement/revision',
              onProgress: replacementProgress.add,
            );
            firstDrain ??= first.cancelAndDrain();
          }
        },
      );
      await expectLater(
        first.runtime,
        throwsA(isA<PackagedRuntimeCancelled>()),
      );
      await firstDrain;
      final oldCount = firstProgress.length;
      await replacement!.runtime;
      await replacement!.cancelAndDrain();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(firstProgress, hasLength(oldCount));
      expect(
        replacementProgress.every(
          (event) => event['consumerRevision'] == 'replacement/revision',
        ),
        true,
      );
      expect(replacementProgress.map((event) => event['attemptId']).toSet(), {
        firstProgress.last['attemptId'],
      });
      expect(
        replacementProgress
            .where((event) => event['stage'] == 'runtimeNative')
            .last['completed'],
        35,
      );
      await noStaging();
    },
  );
  test(
    'native verification failure discards pending counts before error and repair',
    () async {
      final executable = File(p.join(source.path, 'bin/python'));
      for (var index = 0; index < 34; index++) {
        await executable.copy(p.join(source.path, 'bin/native-$index'));
      }
      await package();
      final corrupt = File(
        p.join(resources.path, 'python-runtimes/mlx-native/bin/native-9'),
      );
      final original = await corrupt.readAsBytes();
      final changed = List<int>.of(original)..[100] ^= 1;
      await corrupt.writeAsBytes(changed);
      final progress = <Map<String, dynamic>>[];
      final failed = acquire(onProgress: progress.add);
      await expectLater(failed.runtime, throwsStateError);
      final eventsAtError = progress.length;
      await failed.cancelAndDrain();
      await corrupt.writeAsBytes(original);
      final retryProgress = <Map<String, dynamic>>[];
      final retry = acquire(onProgress: retryProgress.add);
      await retry.runtime;
      await retry.cancelAndDrain();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(progress, hasLength(eventsAtError));
      expect(
        retryProgress.first['attemptId'],
        isNot(progress.first['attemptId']),
      );
      expect(
        retryProgress
            .where((event) => event['stage'] == 'runtimeNative')
            .last['completed'],
        35,
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
      final old = (await first.runtime).pythonHome;
      await first.cancelAndDrain();
      await File(
        p.join(source.path, 'license'),
      ).writeAsString('new preserved license');
      await package();
      final second = acquire();
      expect((await second.runtime).pythonHome, isNot(old));
      expect(
        await File(p.join(old, 'license')).readAsString(),
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
  test(
    'data archive excludes native code; home contains only declared native links',
    () async {
      final archive = ZipDecoder().decodeBytes(
        await File(
          p.join(resources.path, 'python-runtimes/mlx.zip'),
        ).readAsBytes(),
      );
      expect(
        archive.files.map((file) => file.name),
        isNot(contains('bin/python')),
      );
      final lease = acquire();
      final runtime = await lease.runtime;
      expect(
        runtime.executable,
        contains('/Resources/python-runtimes/mlx-native/bin/python'),
      );
      expect(
        await Link(p.join(runtime.pythonHome, 'bin/python')).target(),
        runtime.executable,
      );
      expect(
        await Link(
          p.join(runtime.pythonHome, 'bin/alias'),
        ).resolveSymbolicLinks(),
        runtime.executable,
      );
      await lease.cancelAndDrain();
    },
  );
  test('relocation publishes a new home without rewriting old links', () async {
    final first = acquire();
    final old = await first.runtime;
    await first.cancelAndDrain();
    final moved = Directory(p.join(temp.path, 'MovedResources'));
    await command('/usr/bin/ditto', [resources.path, moved.path]);
    resources = moved;
    final second = acquire();
    final current = await second.runtime;
    expect(current.pythonHome, isNot(old.pythonHome));
    expect(current.executable, startsWith(await moved.resolveSymbolicLinks()));
    expect(
      await Link(p.join(old.pythonHome, 'bin/python')).target(),
      old.executable,
    );
    expect(
      await Link(p.join(current.pythonHome, 'bin/python')).target(),
      current.executable,
    );
    await second.cancelAndDrain();
  });
  test('changed native content changes complete runtime identity', () async {
    final first = acquire();
    final old = await first.runtime;
    await first.cancelAndDrain();
    final c = File(p.join(temp.path, 'changed.c'));
    await c.writeAsString('int main(void) { return 42; }');
    await command('/usr/bin/clang', [
      '-arch',
      'arm64',
      c.path,
      '-o',
      p.join(source.path, 'bin/python'),
    ]);
    await command('/usr/bin/codesign', [
      '--force',
      '--sign',
      '-',
      p.join(source.path, 'bin/python'),
    ]);
    await package();
    final second = acquire();
    expect((await second.runtime).pythonHome, isNot(old.pythonHome));
    await second.cancelAndDrain();
  });
  for (final corruption in [
    'hash',
    'mode',
    'type',
    'bundlePath',
    'missing',
    'extra',
    'parent',
  ]) {
    test(
      'bundled native $corruption fails even when reusing a published home',
      () async {
        final first = acquire();
        final runtime = await first.runtime;
        await first.cancelAndDrain();
        final value = manifest();
        final native = (value['entries'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((entry) => entry['type'] == 'bundledNative');
        final target = File(runtime.executable);
        switch (corruption) {
          case 'hash':
            await target.writeAsString('changed code');
          case 'mode':
            await command('/bin/chmod', ['700', target.path]);
          case 'type':
            await target.delete();
            await Link(target.path).create(p.join(source.path, 'bin/python'));
          case 'bundlePath':
            native['bundlePath'] = '../outside';
            writeManifest(value);
          case 'missing':
            await target.delete();
          case 'extra':
            await File(
              p.join(p.dirname(target.path), 'undeclared'),
            ).writeAsString('unexpected');
          case 'parent':
            final directory = Directory(p.dirname(target.path));
            final saved = '${directory.path}-saved';
            await directory.rename(saved);
            await Link(directory.path).create(saved);
        }
        final second = acquire();
        await expectLater(second.runtime, throwsStateError);
        await second.cancelAndDrain();
        expect(await Directory(runtime.pythonHome).exists(), true);
        await noStaging();
      },
    );
  }
  test(
    'published native links cannot be redirected to an undeclared target',
    () async {
      final first = acquire();
      final runtime = await first.runtime;
      await first.cancelAndDrain();
      final link = Link(p.join(runtime.pythonHome, 'bin/python'));
      await link.delete();
      await link.create(p.join(source.path, 'bin/python'));
      final second = acquire();
      await expectLater(second.runtime, throwsStateError);
      await second.cancelAndDrain();
    },
  );
  test(
    'incomplete data archive with a matching archive hash fails inventory validation',
    () async {
      final value = manifest();
      final archive = File(p.join(resources.path, 'python-runtimes/mlx.zip'));
      await command('/usr/bin/zip', ['-d', archive.path, 'license']);
      value['archive'] = {
        'size': await archive.length(),
        'sha256': sha256.convert(await archive.readAsBytes()).toString(),
      };
      writeManifest(value);
      final lease = acquire();
      await expectLater(lease.runtime, throwsStateError);
      await lease.cancelAndDrain();
      await noStaging();
    },
  );
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
        final runtime = await first.runtime;
        final executable = p.join(runtime.pythonHome, 'license');
        await first.cancelAndDrain();
        final tree = Directory(runtime.pythonHome);
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
  for (final stage in [
    'runtimeNative',
    'runtimeArchive',
    'runtimeExtract',
    'runtimeTree',
  ]) {
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
      expect(
        (await second.runtime).pythonHome,
        contains('/python-runtimes/v2/mlx/'),
      );
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
