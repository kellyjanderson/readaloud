import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_engine_catalog.dart';

void main() {
  late Map<String, dynamic> models;
  late Map<String, dynamic> checksums;

  FishDramaCatalog parse() => FishDramaCatalog.fromJson(
    modelsJson: jsonEncode(models),
    checksumsJson: jsonEncode(checksums),
  );

  setUp(() {
    models =
        jsonDecode(File('assets/fish_drama_models.json').readAsStringSync())
            as Map<String, dynamic>;
    checksums =
        jsonDecode(
              File('assets/fish_drama_model_checksums.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  test('bundled assets retain saved IDs, labels and checkpoint precision', () {
    final catalog = parse();
    expect(catalog.variants.keys, [
      'fish_drama3',
      'fish_drama3_8bit',
      'fish_drama3_4bit',
    ]);
    for (final entry in catalog.variants.entries) {
      final descriptor = entry.value;
      final source = models[entry.key] as Map;
      expect(descriptor.engineId, entry.key);
      expect(descriptor.label, speechEngineLabels[entry.key]);
      expect(descriptor.repository, source['repo']);
      expect(descriptor.revision, source['revision']);
      expect(
        descriptor.pinnedIdentity,
        '${source['repo']}@${source['revision']}',
      );
      expect(descriptor.quantizationBits, source['bits']);
      expect(descriptor.estimatedPeakBytes, source['estimatedPeakBytes']);
      expect(descriptor.requiredFiles, source['requiredFiles']);
    }
    expect(catalog.variants['fish_drama3']!.quantizationBits, 0);
    expect(catalog.variants['fish_drama3_8bit']!.quantizationBits, 8);
    expect(catalog.variants['fish_drama3_4bit']!.quantizationBits, 4);
    expect(isMlxEngine('kokoro'), isFalse);
    expect(isDramaEngine('unknown'), isFalse);
  });

  for (final entry in const {
    'fish_drama3': 8,
    'fish_drama3_8bit': 4,
    'fish_drama3_4bit': 8,
  }.entries) {
    test('rejects checkpoint precision inconsistent with ${entry.key}', () {
      models[entry.key]['bits'] = entry.value;
      expect(parse, throwsFormatException);
    });
  }

  test('v2 checksums cover each exact pinned checkpoint', () {
    final catalog = parse();
    for (final entry in catalog.variants.entries) {
      final descriptor = entry.value;
      final manifest = descriptor.integrityManifest!;
      expect(manifest.repository, descriptor.repository);
      expect(manifest.revision, descriptor.revision);
      expect(manifest.files.keys, containsAll(descriptor.requiredFiles));
      final sourceFiles = checksums['variants'][entry.key]['files'] as Map;
      expect(manifest.files.length, sourceFiles.length);
      for (final file in manifest.files.entries) {
        final source = sourceFiles[file.key] as Map;
        expect(file.value.sizeBytes, source['size']);
        expect(file.value.algorithm, source['algorithm']);
        expect(file.value.digest, source['digest']);
      }
    }
    expect(
      catalog.variants['fish_drama3']!.integrityManifest!.files.length,
      26,
    );
    expect(
      catalog.variants['fish_drama3_8bit']!.integrityManifest!.files.length,
      20,
    );
    expect(
      catalog.variants['fish_drama3_4bit']!.integrityManifest!.files.length,
      16,
    );
  });

  test('legacy v1 retains exact bf16 data and absent other manifests', () {
    final legacy = checksums['variants']['fish_drama3'] as Map<String, dynamic>;
    checksums = legacy;
    final catalog = parse();
    expect(
      catalog.variants['fish_drama3']!.integrityManifest!.files.length,
      26,
    );
    expect(catalog.variants['fish_drama3_8bit']!.integrityManifest, isNull);
    expect(catalog.variants['fish_drama3_4bit']!.integrityManifest, isNull);
  });

  test(
    'descriptor records mixed quantization without claiming codec precision',
    () {
      final catalog = parse();
      final four = catalog.variants['fish_drama3_4bit']!;
      expect(four.profile!.defaultBits, 8);
      expect(
        four.profile!.overrides.map((g) => [g.scope, g.bits, g.moduleCount]),
        [
          ['dense', 8, 251],
          ['experts', 4, 120],
          ['tower', 8, 87],
        ],
      );
      expect(four.profile!.codecPrecision, 'not-declared');
      expect(four.profile!.nativeScenes, 'unqualified');
      expect(
        catalog
            .variants['fish_drama3_8bit']!
            .profile!
            .overrides
            .single
            .moduleCount,
        120,
      );
      expect(
        catalog.variants['fish_drama3']!.profile!.nativeScenes,
        'bounded-qualified',
      );
      expect(
        four.expectedDiskBytes,
        four.requiredFiles.fold<int>(
          0,
          (n, file) => n + four.integrityManifest!.files[file]!.sizeBytes,
        ),
      );
      expect(four.licenseIntegrity!.digest, isNotEmpty);
      expect(four.noticeIntegrity!.digest, isNotEmpty);
      expect(four.configIntegrity!.digest, isNotEmpty);
    },
  );

  test(
    'legacy descriptors without profile remain readable and unqualified',
    () {
      for (final value in models.values) {
        (value as Map).remove('profile');
      }
      expect(parse().variants.values.every((v) => v.profile == null), true);
    },
  );

  for (final mutation in <String, void Function(Map<String, dynamic>)>{
    'wrong config pin': (p) =>
        p['configSource'] = 'https://example.com/config.json',
    'new executable runtime': (p) => p['runtime']['id'] = 'new-python-code',
    'new scene capability': (p) =>
        p['capabilities']['nativeScenes'] = 'bounded-qualified',
    'new native format': (p) => p['nativeFormat']['sampleRate'] = 48000,
    'claimed qualified memory': (p) =>
        p['qualification']['memory'] = 'qualified',
    'unknown profile field': (p) => p['executable'] = 'custom.py',
    'fractional precision': (p) => p['quantizationLayout']['defaultBits'] = 8.0,
    'guessed codec precision': (p) =>
        p['quantizationLayout']['codecPrecision'] = 'bfloat16',
  }.entries) {
    test('rejects profile ${mutation.key}', () {
      mutation.value(
        models['fish_drama3_4bit']['profile'] as Map<String, dynamic>,
      );
      expect(parse, throwsFormatException);
    });
  }

  test('catalog and nested collections are immutable', () {
    final catalog = parse();
    final descriptor = catalog.variants['fish_drama3']!;
    expect(() => catalog.variants.clear(), throwsUnsupportedError);
    expect(() => descriptor.requiredFiles.clear(), throwsUnsupportedError);
    expect(
      () => descriptor.integrityManifest!.files.clear(),
      throwsUnsupportedError,
    );
  });

  for (final revision in ['main', '', 'a' * 39, 'a' * 41]) {
    test('rejects unpinned revision "$revision"', () {
      models['fish_drama3_4bit']['revision'] = revision;
      expect(parse, throwsFormatException);
    });
  }

  for (final repository in [
    'other/model',
    'https://huggingface.co/mlx-community/model',
    'mlx-community/../model',
  ]) {
    test('rejects unsupported repository "$repository"', () {
      models['fish_drama3_4bit']['repo'] = repository;
      expect(parse, throwsFormatException);
    });
  }

  final invalidModels = <String, void Function(Map<String, dynamic>)>{
    'unknown saved ID': (m) => m['unknown'] = m.remove('fish_drama3_4bit'),
    'missing saved ID': (m) => m.remove('fish_drama3_4bit'),
    'unknown field': (m) => m['fish_drama3']['executable'] = 'custom.py',
    'non-object descriptor': (m) => m['fish_drama3'] = [],
    'missing field': (m) => m['fish_drama3'].remove('bits'),
    'unsupported precision': (m) => m['fish_drama3']['bits'] = 3,
    'fractional precision': (m) => m['fish_drama3']['bits'] = 4.0,
    'invalid estimate': (m) => m['fish_drama3']['estimatedPeakBytes'] = -1,
    'missing core file': (m) =>
        (m['fish_drama3']['requiredFiles'] as List).remove('config.json'),
    'missing model shards': (m) => (m['fish_drama3']['requiredFiles'] as List)
        .removeWhere((f) => (f as String).startsWith('model-')),
    'duplicate file': (m) =>
        (m['fish_drama3']['requiredFiles'] as List).add('config.json'),
    'unsafe file': (m) =>
        (m['fish_drama3']['requiredFiles'] as List).add('../model'),
    'duplicate checkpoint': (m) {
      m['fish_drama3_4bit']['repo'] = m['fish_drama3']['repo'];
      m['fish_drama3_4bit']['revision'] = m['fish_drama3']['revision'];
    },
  };
  for (final entry in invalidModels.entries) {
    test('rejects ${entry.key}', () {
      entry.value(models);
      expect(parse, throwsFormatException);
    });
  }

  final invalidManifests = <String, void Function(Map<String, dynamic>)>{
    'revision mismatch': (m) => m['revision'] = 'a' * 40,
    'repository mismatch': (m) => m['repo'] = 'mlx-community/other',
    'mutable source': (m) => m['source'] =
        'https://huggingface.co/api/models/mlx-community/model/tree/main',
    'incomplete checksums': (m) => m['files'].remove('codec.safetensors'),
    'unknown algorithm': (m) => m['files']['config.json']['algorithm'] = 'md5',
    'malformed digest': (m) => m['files']['config.json']['digest'] = 'abcd',
    'invalid size': (m) => m['files']['config.json']['size'] = 0,
    'unsafe manifest path': (m) =>
        m['files']['../config.json'] = m['files']['config.json'],
    'extra executable field': (m) => m['runtime'] = 'custom.py',
  };
  for (final entry in invalidManifests.entries) {
    test('rejects checksum ${entry.key}', () {
      entry.value(checksums['variants']['fish_drama3'] as Map<String, dynamic>);
      expect(parse, throwsFormatException);
    });
  }

  final invalidContainers = <String, void Function(Map<String, dynamic>)>{
    'unknown version': (m) => m['schemaVersion'] = 3,
    'fractional version': (m) => m['schemaVersion'] = 2.0,
    'missing version': (m) => m.remove('schemaVersion'),
    'extra field': (m) => m['executable'] = 'custom.py',
    'missing variant': (m) => m['variants'].remove('fish_drama3_4bit'),
    'unknown variant': (m) =>
        m['variants']['unknown'] = m['variants']['fish_drama3_4bit'],
    'non-object variants': (m) => m['variants'] = [],
    'non-object manifest': (m) => m['variants']['fish_drama3_4bit'] = [],
    'swapped variants': (m) {
      final variants = m['variants'] as Map;
      final bf16 = variants['fish_drama3'];
      variants['fish_drama3'] = variants['fish_drama3_4bit'];
      variants['fish_drama3_4bit'] = bf16;
    },
  };
  for (final entry in invalidContainers.entries) {
    test('rejects v2 ${entry.key}', () {
      entry.value(checksums);
      expect(parse, throwsFormatException);
    });
  }

  for (final id in ['fish_drama3', 'fish_drama3_8bit', 'fish_drama3_4bit']) {
    test('rejects incomplete required coverage for $id', () {
      checksums['variants'][id]['files'].remove('model-00001.safetensors');
      expect(parse, throwsFormatException);
    });
    test('rejects a valid different pin for $id', () {
      final manifest = checksums['variants'][id] as Map;
      manifest['revision'] = 'a' * 40;
      manifest['source'] =
          'https://huggingface.co/api/models/${manifest['repo']}/tree/${manifest['revision']}';
      expect(parse, throwsFormatException);
    });
  }

  test('rejects a well-formed checksum manifest for a different pin', () {
    checksums = checksums['variants']['fish_drama3'] as Map<String, dynamic>;
    checksums['revision'] = 'a' * 40;
    checksums['source'] =
        'https://huggingface.co/api/models/${checksums['repo']}/tree/${checksums['revision']}';
    expect(parse, throwsFormatException);
  });
}
