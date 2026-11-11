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

  test('checksums attach only to the exact matching pinned checkpoint', () {
    final catalog = parse();
    final bf16 = catalog.variants['fish_drama3']!;
    final manifest = bf16.integrityManifest!;
    expect(manifest.repository, bf16.repository);
    expect(manifest.revision, bf16.revision);
    expect(manifest.files.keys, containsAll(bf16.requiredFiles));
    final sourceFiles = checksums['files'] as Map;
    for (final entry in manifest.files.entries) {
      final source = sourceFiles[entry.key] as Map;
      expect(entry.value.sizeBytes, source['size']);
      expect(entry.value.algorithm, source['algorithm']);
      expect(entry.value.digest, source['digest']);
    }
    expect(catalog.variants['fish_drama3_8bit']!.integrityManifest, isNull);
    expect(catalog.variants['fish_drama3_4bit']!.integrityManifest, isNull);
  });

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
      entry.value(checksums);
      expect(parse, throwsFormatException);
    });
  }

  test('rejects a well-formed checksum manifest for a different pin', () {
    checksums['revision'] = 'a' * 40;
    checksums['source'] =
        'https://huggingface.co/api/models/${checksums['repo']}/tree/${checksums['revision']}';
    expect(parse, throwsFormatException);
  });
}
