import 'dart:convert';

/// Stable IDs used by preferences, factories and UI. Checkpoint revisions and
/// downloaded precision are in assets/fish_drama_models.json.
const speechEngineLabels = <String, String>{
  'kokoro': 'Kokoro',
  'fish_drama3': 'Fish Audio Drama 3 · bf16',
  'fish_drama3_8bit': 'Fish Audio Drama 3 · 8-bit',
  'fish_drama3_4bit': 'Fish Audio Drama 3 · 4-bit',
  'qwen3_tts_base_1_7b': 'Qwen3-TTS 1.7B Base',
  'qwen3_tts_1_7b': 'Qwen3-TTS 1.7B CustomVoice',
  'voxtral_4b': 'Voxtral TTS 4B',
  'moss_tts_8b': 'MOSS-TTS v1.5 8B',
};
bool isDramaEngine(String id) =>
    const {'fish_drama3', 'fish_drama3_8bit', 'fish_drama3_4bit'}.contains(id);
bool isMlxEngine(String? id) =>
    id != 'kokoro' && speechEngineLabels.containsKey(id);

/// A declaration from the bundled Fish catalog, not proof of installed bytes,
/// runtime compatibility, acoustic capabilities or measured memory use.
final class FishDramaVariantDescriptor {
  FishDramaVariantDescriptor._({
    required this.engineId,
    required this.label,
    required this.repository,
    required this.revision,
    required this.quantizationBits,
    required this.estimatedPeakBytes,
    required List<String> requiredFiles,
    required this.integrityManifest,
  }) : requiredFiles = List.unmodifiable(requiredFiles);

  final String engineId;
  final String label;
  final String repository;
  final String revision;

  /// Zero denotes the catalog's original bf16 checkpoint, not runtime conversion.
  final int quantizationBits;

  /// Existing estimate only; never a measured or qualified admission envelope.
  final int estimatedPeakBytes;
  final List<String> requiredFiles;

  /// Absent where no matching bundled checksums exist (currently 8-bit/4-bit).
  /// Presence declares expected integrity; it does not verify any local file.
  final FishDramaIntegrityManifest? integrityManifest;

  String get pinnedIdentity => '$repository@$revision';
}

final class FishDramaFileIntegrity {
  const FishDramaFileIntegrity._(this.sizeBytes, this.algorithm, this.digest);

  final int sizeBytes;
  final String algorithm;
  final String digest;
}

final class FishDramaIntegrityManifest {
  FishDramaIntegrityManifest._({
    required this.repository,
    required this.revision,
    required Map<String, FishDramaFileIntegrity> files,
  }) : files = Map.unmodifiable(files);

  final String repository;
  final String revision;
  final Map<String, FishDramaFileIntegrity> files;
}

/// Typed view of the same bundled JSON consumed by the Python model owner.
///
/// Parsing is synchronous and side-effect free: callers own asset loading. This
/// initial boundary does not replace the downloader, cache or runtime selection.
final class FishDramaCatalog {
  FishDramaCatalog._(Map<String, FishDramaVariantDescriptor> variants)
    : variants = Map.unmodifiable(variants);

  final Map<String, FishDramaVariantDescriptor> variants;

  factory FishDramaCatalog.fromJson({
    required String modelsJson,
    required String checksumsJson,
  }) {
    final models = _object(jsonDecode(modelsJson), 'Fish catalog');
    final manifest = _parseManifest(jsonDecode(checksumsJson));
    final variants = <String, FishDramaVariantDescriptor>{};
    final identities = <String>{};
    var matchedManifest = false;
    for (final entry in models.entries) {
      final id = entry.key;
      if (!isDramaEngine(id)) {
        throw FormatException('Unknown Fish engine ID: $id');
      }
      final spec = _object(entry.value, id);
      _fields(spec, const {
        'label',
        'repo',
        'revision',
        'bits',
        'estimatedPeakBytes',
        'requiredFiles',
      }, id);
      final label = _nonempty(spec['label'], '$id.label');
      final repository = _repository(spec['repo']);
      final revision = _revision(spec['revision']);
      final bits = spec['bits'];
      final expectedBits = switch (id) {
        'fish_drama3' => 0,
        'fish_drama3_8bit' => 8,
        'fish_drama3_4bit' => 4,
        _ => throw FormatException('Unknown Fish engine ID: $id'),
      };
      if (bits is! int || bits != expectedBits) {
        throw FormatException('Invalid checkpoint precision for $id');
      }
      final peakBytes = _positiveInt(
        spec['estimatedPeakBytes'],
        '$id.estimatedPeakBytes',
      );
      final rawFiles = spec['requiredFiles'];
      if (rawFiles is! List || rawFiles.isEmpty) {
        throw FormatException('Missing required files for $id');
      }
      final files = rawFiles.map(_fileName).toList();
      if (files.toSet().length != files.length ||
          !files.toSet().containsAll(const {
            'LICENSE',
            'NOTICE',
            'config.json',
            'codec.safetensors',
            'tokenizer.json',
            'tokenizer_config.json',
          }) ||
          !files.any(
            (name) =>
                name.startsWith('model-') && name.endsWith('.safetensors'),
          )) {
        throw FormatException('Incomplete or duplicate required files for $id');
      }
      if (!identities.add('$repository@$revision')) {
        throw FormatException('Duplicate pinned checkpoint identity for $id');
      }
      FishDramaIntegrityManifest? integrity;
      if (repository == manifest.repository && revision == manifest.revision) {
        if (!manifest.files.keys.toSet().containsAll(files)) {
          throw FormatException(
            'Checksum manifest does not cover $id required files',
          );
        }
        integrity = manifest;
        matchedManifest = true;
      }
      variants[id] = FishDramaVariantDescriptor._(
        engineId: id,
        label: label,
        repository: repository,
        revision: revision,
        quantizationBits: bits,
        estimatedPeakBytes: peakBytes,
        requiredFiles: files,
        integrityManifest: integrity,
      );
    }
    if (!variants.keys.toSet().containsAll(
      speechEngineLabels.keys.where(isDramaEngine),
    )) {
      throw const FormatException('Missing saved Fish engine ID');
    }
    if (!matchedManifest) {
      throw const FormatException(
        'Checksum manifest has no matching pinned variant',
      );
    }
    return FishDramaCatalog._(variants);
  }
}

FishDramaIntegrityManifest _parseManifest(Object? value) {
  final manifest = _object(value, 'Fish checksums');
  _fields(manifest, const {
    'repo',
    'revision',
    'source',
    'files',
  }, 'Fish checksums');
  final repository = _repository(manifest['repo']);
  final revision = _revision(manifest['revision']);
  if (manifest['source'] !=
      'https://huggingface.co/api/models/$repository/tree/$revision') {
    throw const FormatException(
      'Checksum source does not match pinned Hugging Face identity',
    );
  }
  final entries = _object(manifest['files'], 'Fish checksum files');
  final files = <String, FishDramaFileIntegrity>{};
  for (final entry in entries.entries) {
    final name = _fileName(entry.key);
    final spec = _object(entry.value, name);
    _fields(spec, const {'size', 'algorithm', 'digest'}, name);
    final size = _positiveInt(spec['size'], '$name.size');
    final algorithm = spec['algorithm'];
    final length = switch (algorithm) {
      'git-sha1' => 40,
      'sha256' => 64,
      _ => throw FormatException('Unsupported checksum algorithm for $name'),
    };
    final digest = spec['digest'];
    if (digest is! String || !RegExp('^[a-f0-9]{$length}\$').hasMatch(digest)) {
      throw FormatException('Invalid checksum digest for $name');
    }
    files[name] = FishDramaFileIntegrity._(size, algorithm as String, digest);
  }
  return FishDramaIntegrityManifest._(
    repository: repository,
    revision: revision,
    files: files,
  );
}

Map<String, dynamic> _object(Object? value, String context) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('Expected object for $context');
  }
  return value;
}

void _fields(Map<String, dynamic> value, Set<String> expected, String context) {
  if (value.length != expected.length || !expected.containsAll(value.keys)) {
    throw FormatException('Unsupported or missing fields for $context');
  }
}

String _nonempty(Object? value, String context) {
  if (value is! String || value.trim().isEmpty || value != value.trim()) {
    throw FormatException('Invalid string for $context');
  }
  return value;
}

String _repository(Object? value) {
  final repository = _nonempty(value, 'repository');
  if (!RegExp(
    r'^mlx-community/[a-zA-Z0-9][a-zA-Z0-9_-]*$',
  ).hasMatch(repository)) {
    throw const FormatException('Unsupported Fish repository');
  }
  return repository;
}

String _revision(Object? value) {
  final revision = _nonempty(value, 'revision');
  if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(revision)) {
    throw const FormatException('Fish revision must be a pinned commit');
  }
  return revision;
}

int _positiveInt(Object? value, String context) {
  if (value is! int || value <= 0) {
    throw FormatException('Expected positive integer for $context');
  }
  return value;
}

String _fileName(Object? value) {
  final name = _nonempty(value, 'file name');
  if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name) ||
      name == '.' ||
      name == '..') {
    throw const FormatException('Expected a safe snapshot file name');
  }
  return name;
}
