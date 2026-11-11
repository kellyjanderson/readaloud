import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/fish_drama_catalog_store.dart';

void main() {
  late Directory root;
  late String models;
  late String checksums;
  late Map<String, dynamic> manifest;
  late List<Uri> requests;
  late List<FishDramaCatalogStore> stores;

  Map<String, String> payloads() {
    final hashes = manifest['files'] as Map;
    hashes['fish_drama_models.json'] = sha256
        .convert(utf8.encode(models))
        .toString();
    hashes['fish_drama_model_checksums.json'] = sha256
        .convert(utf8.encode(checksums))
        .toString();
    return {
      'fish_drama_catalog_update.json': jsonEncode(manifest),
      'fish_drama_models.json': models,
      'fish_drama_model_checksums.json': checksums,
    };
  }

  FishDramaCatalogStore store({
    FishDramaCatalogTransport? transport,
    Duration timeout = const Duration(seconds: 8),
  }) {
    final payload = payloads();
    final result = FishDramaCatalogStore(
      root: root,
      bundledModelsJson: File(
        'assets/fish_drama_models.json',
      ).readAsStringSync(),
      bundledChecksumsJson: File(
        'assets/fish_drama_model_checksums.json',
      ).readAsStringSync(),
      timeout: timeout,
      transport:
          transport ??
          (uri) async {
            requests.add(uri);
            return utf8.encode(payload[uri.pathSegments.last]!);
          },
    );
    stores.add(result);
    return result;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fish-catalog-test-');
    models = File('assets/fish_drama_models.json').readAsStringSync();
    checksums = File(
      'assets/fish_drama_model_checksums.json',
    ).readAsStringSync();
    manifest =
        jsonDecode(
              File('assets/fish_drama_catalog_update.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    requests = [];
    stores = [];
  });
  tearDown(() async {
    for (final owner in stores) {
      await owner.close();
    }
    await root.delete(recursive: true);
  });

  void reviseCheckpoint() {
    final updatedModels = jsonDecode(models) as Map<String, dynamic>;
    updatedModels['fish_drama3_4bit']['revision'] = 'a' * 40;
    final updatedChecksums = jsonDecode(checksums) as Map<String, dynamic>;
    final entry = updatedChecksums['variants']['fish_drama3_4bit'] as Map;
    entry['revision'] = 'a' * 40;
    entry['source'] =
        'https://huggingface.co/api/models/${entry['repo']}/tree/${entry['revision']}';
    models = jsonEncode(updatedModels);
    checksums = jsonEncode(updatedChecksums);
  }

  test(
    'published update manifest hashes exactly the committed bundled data',
    () {
      final expected = Map<String, dynamic>.from(manifest['files'] as Map);
      payloads();
      expect(manifest['files'], expected);
      expect(manifest['runtime']['id'], fishDramaCatalogRuntime);
    },
  );

  test(
    'load is offline and refresh changes next lookup, not captured session',
    () async {
      reviseCheckpoint();
      final owner = store();
      final captured = await owner.load();
      expect(requests, isEmpty);
      final result = await owner.refresh();
      expect(result.error, isNull);
      expect(result.snapshot.catalogVersion, 1);
      expect(
        result.snapshot.catalog.variants['fish_drama3_4bit']!.revision,
        'a' * 40,
      );
      expect(
        captured.catalog.variants['fish_drama3_4bit']!.revision,
        isNot('a' * 40),
      );
      expect((await owner.load()).identity, result.snapshot.identity);
      expect(requests.map((uri) => uri.host).toSet(), {
        'raw.githubusercontent.com',
      });
      expect(
        requests.first.path,
        '/kellyjanderson/readaloud/main/assets/fish_drama_catalog_update.json',
      );
      for (final uri in requests.skip(1)) {
        expect(
          uri.path,
          startsWith(
            '/kellyjanderson/readaloud/${manifest['sourceRevision']}/assets/',
          ),
        );
        expect(uri.query, isEmpty);
      }
      await owner.close();
      final offline = store(
        transport: (_) async => throw StateError('offline'),
      );
      expect((await offline.load()).identity, result.snapshot.identity);
      expect(
        (await offline.refresh()).snapshot.identity,
        result.snapshot.identity,
      );
      expect((await offline.refresh()).error, isNotNull);
    },
  );

  test(
    'qualification can pin only the same manifest at an immutable commit',
    () async {
      final owner = store();
      expect(
        (await owner.refresh(manifestRevision: 'b' * 40)).succeeded,
        isTrue,
      );
      expect(
        requests.first.path,
        '/kellyjanderson/readaloud/${'b' * 40}/assets/fish_drama_catalog_update.json',
      );
      expect(
        () => owner.refresh(manifestRevision: 'https://evil.test/x'),
        throwsFormatException,
      );
      expect(
        () => owner.refresh(manifestRevision: '../main'),
        throwsFormatException,
      );
    },
  );

  test('refresh coalesces without an unbounded request queue', () async {
    final gate = Completer<void>();
    final payload = payloads();
    final owner = store(
      transport: (uri) async {
        requests.add(uri);
        await gate.future;
        return utf8.encode(payload[uri.pathSegments.last]!);
      },
    );
    await owner.load();
    final first = owner.refresh();
    final second = owner.refresh();
    expect(identical(first, second), isTrue);
    gate.complete();
    expect((await first).succeeded, isTrue);
    expect(requests, hasLength(3));
  });

  test(
    'close cancels stalled transport and late success cannot publish',
    () async {
      final started = Completer<void>();
      final delayed = Completer<List<int>>();
      final owner = store(
        transport: (_) {
          started.complete();
          return delayed.future;
        },
      );
      final before = await owner.load();
      final pending = owner.refresh();
      await started.future;
      await owner.close();
      expect((await pending).error, isNotNull);
      delayed.complete(utf8.encode(jsonEncode(manifest)));
      await Future<void>.delayed(Duration.zero);
      expect(
        await File('${root.path}/catalog/last-valid.json').exists(),
        isFalse,
      );
      expect(before.catalogVersion, 0);
      expect(() => owner.refresh(), throwsStateError);
    },
  );

  test(
    'deadline cancels stalled transport and permits a clean retry',
    () async {
      final owner = store(
        timeout: const Duration(milliseconds: 30),
        transport: (_) => Completer<List<int>>().future,
      );
      await owner.load();
      final result = await owner.refresh();
      expect(result.error, isNotNull);
      expect(result.snapshot.catalogVersion, 0);
      expect(
        await File('${root.path}/catalog/last-valid.json').exists(),
        isFalse,
      );
    },
  );

  test('network failure retains a persisted valid catalog unchanged', () async {
    final initial = store();
    final good = (await initial.refresh()).snapshot;
    await initial.close();
    final saved = File('${root.path}/catalog/last-valid.json');
    final bytes = await saved.readAsBytes();
    final failing = store(
      transport: (_) async => throw const HttpException('404'),
    );
    final result = await failing.refresh();
    expect(result.succeeded, isFalse);
    expect(result.snapshot.identity, good.identity);
    expect(await saved.readAsBytes(), bytes);
  });

  test('corrupt persisted catalog falls back to trusted bundle', () async {
    final file = File('${root.path}/catalog/last-valid.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('{"manifest":"broken"}');
    final loaded = await store().load();
    expect(loaded.catalogVersion, 0);
    expect(requests, isEmpty);
  });

  final invalidMetadata = <String, void Function(Map<String, dynamic>)>{
    'unknown schema': (m) => m['schemaVersion'] = 2,
    'fractional schema': (m) => m['schemaVersion'] = 1.0,
    'unversioned update': (m) => m['catalogVersion'] = 0,
    'mutable source revision': (m) => m['sourceRevision'] = 'main',
    'external source': (m) => m['sourceRevision'] = 'https://evil.test',
    'extra executable source': (m) => m['script'] = 'custom.py',
    'new runtime dependency': (m) => m['runtime']['id'] = 'install-me',
    'unsupported architecture': (m) => m['runtime']['architecture'] = 'custom',
    'unsupported platform': (m) => m['runtime']['platform'] = 'macos-x64',
    'broadened capabilities': (m) =>
        m['runtime']['capabilities'] = 'arbitrary-python',
    'extra runtime field': (m) => m['runtime']['pip'] = 'evil',
    'extra download': (m) => m['files']['code.py'] = 'b' * 64,
  };
  for (final entry in invalidMetadata.entries) {
    test('rejects ${entry.key} without changing the catalog', () async {
      entry.value(manifest);
      final owner = store();
      final before = await owner.load();
      final result = await owner.refresh();
      expect(result.succeeded, isFalse);
      expect(result.snapshot.identity, before.identity);
      expect(requests, hasLength(1));
      expect(
        await File('${root.path}/catalog/last-valid.json').exists(),
        isFalse,
      );
    });
  }

  test(
    'rejects valid schema whose fetched bytes mismatch metadata digest',
    () async {
      final payload = payloads();
      final owner = store(
        transport: (uri) async => utf8.encode(
          uri.pathSegments.last == 'fish_drama_models.json'
              ? '$models '
              : payload[uri.pathSegments.last]!,
        ),
      );
      expect((await owner.refresh()).succeeded, isFalse);
    },
  );

  test(
    'rejects an executable required file even with matching catalog hashes',
    () async {
      final model = jsonDecode(models) as Map;
      (model['fish_drama3']['requiredFiles'] as List).add('custom.py');
      models = jsonEncode(model);
      final integrity = jsonDecode(checksums) as Map;
      integrity['variants']['fish_drama3']['files']['custom.py'] = {
        'size': 10,
        'algorithm': 'sha256',
        'digest': 'a' * 64,
      };
      checksums = jsonEncode(integrity);
      expect((await store().refresh()).succeeded, isFalse);
    },
  );

  test('rejects a legacy partial integrity manifest for refresh', () async {
    checksums = jsonEncode(
      (jsonDecode(checksums) as Map)['variants']['fish_drama3'],
    );
    expect((await store().refresh()).succeeded, isFalse);
  });

  test(
    'rejects invalid required-file digests despite valid catalog hashes',
    () async {
      final integrity = jsonDecode(checksums) as Map;
      integrity['variants']['fish_drama3_4bit']['files']['config.json']['digest'] =
          'bad';
      checksums = jsonEncode(integrity);
      expect((await store().refresh()).succeeded, isFalse);
    },
  );

  test(
    'rejects downgrade and same-version different immutable metadata',
    () async {
      manifest['catalogVersion'] = 2;
      final first = store();
      final accepted = (await first.refresh()).snapshot;
      await first.close();
      manifest['catalogVersion'] = 1;
      final older = store();
      expect((await older.refresh()).succeeded, isFalse);
      await older.close();
      manifest['catalogVersion'] = 2;
      manifest['sourceRevision'] = 'a' * 40;
      final collision = await store().refresh();
      expect(collision.succeeded, isFalse);
      expect(collision.snapshot.identity, accepted.identity);
    },
  );

  test('rejects oversized response without persistence', () async {
    final result = await store(
      transport: (_) async => List.filled(256 * 1024 + 1, 32),
    ).refresh();
    expect(result.succeeded, isFalse);
    expect(
      await File('${root.path}/catalog/last-valid.json').exists(),
      isFalse,
    );
  });
}
