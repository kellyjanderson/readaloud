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

/// A declaration from a validated Fish catalog, not proof of installed bytes,
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
    required this.profile,
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

  /// May be absent when reading a legacy single-checkpoint checksum manifest.
  /// Presence declares expected integrity; it does not verify any local file.
  final FishDramaIntegrityManifest? integrityManifest;
  final FishDramaProfile? profile;

  int? get expectedDiskBytes => integrityManifest == null
      ? null
      : requiredFiles.fold<int>(
          0,
          (total, name) => total + integrityManifest!.files[name]!.sizeBytes,
        );
  FishDramaFileIntegrity? get licenseIntegrity =>
      integrityManifest?.files['LICENSE'];
  FishDramaFileIntegrity? get noticeIntegrity =>
      integrityManifest?.files['NOTICE'];
  FishDramaFileIntegrity? get configIntegrity =>
      integrityManifest?.files['config.json'];

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

/// Typed view of the same validated JSON consumed by the Python model owner.
///
/// Parsing is synchronous and side-effect free: callers own asset loading. This
/// boundary does not replace the downloader, cache or runtime selection.
final class FishDramaCatalog {
  FishDramaCatalog._(Map<String, FishDramaVariantDescriptor> variants)
    : variants = Map.unmodifiable(variants);

  final Map<String, FishDramaVariantDescriptor> variants;

  factory FishDramaCatalog.fromJson({
    required String modelsJson,
    required String checksumsJson,
  }) {
    final models = _object(jsonDecode(modelsJson), 'Fish catalog');
    final checksums = _object(jsonDecode(checksumsJson), 'Fish checksums');
    final Map<String, FishDramaIntegrityManifest>? manifests;
    final FishDramaIntegrityManifest? legacyManifest;
    if (checksums.containsKey('schemaVersion')) {
      _fields(checksums, const {'schemaVersion', 'variants'}, 'Fish checksums');
      if (checksums['schemaVersion'] is! int ||
          checksums['schemaVersion'] != 2) {
        throw const FormatException('Unsupported Fish checksum schema version');
      }
      final entries = _object(checksums['variants'], 'Fish checksum variants');
      _fields(
        entries,
        speechEngineLabels.keys.where(isDramaEngine).toSet(),
        'Fish checksum variants',
      );
      manifests = entries.map(
        (id, value) => MapEntry(id, _parseManifest(value)),
      );
      legacyManifest = null;
    } else {
      manifests = null;
      legacyManifest = _parseManifest(checksums);
    }
    final variants = <String, FishDramaVariantDescriptor>{};
    final identities = <String>{};
    var matchedManifest = false;
    for (final entry in models.entries) {
      final id = entry.key;
      if (!isDramaEngine(id)) {
        throw FormatException('Unknown Fish engine ID: $id');
      }
      final spec = _object(entry.value, id);
      _fields(
        spec,
        const {
          'label',
          'repo',
          'revision',
          'bits',
          'estimatedPeakBytes',
          'requiredFiles',
        },
        id,
        optional: const {'profile'},
      );
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
      final manifest = manifests?[id] ?? legacyManifest!;
      final matches =
          repository == manifest.repository && revision == manifest.revision;
      if (manifests != null && !matches) {
        throw FormatException('Checksum identity does not match $id');
      }
      if (matches) {
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
        profile: spec.containsKey('profile')
            ? FishDramaProfile._parse(spec['profile'], repository, revision)
            : null,
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

void _fields(
  Map<String, dynamic> value,
  Set<String> expected,
  String context, {
  Set<String> optional = const {},
}) {
  if (!value.keys.toSet().containsAll(expected) ||
      !{...expected, ...optional}.containsAll(value.keys)) {
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

/// Data-only checkpoint metadata. These declarations never enable executable
/// capabilities: the installed runtime validates the loaded model independently.
final class FishDramaProfile {
  FishDramaProfile._(
    this.configSource,
    this.configDtype,
    this.defaultBits,
    this.groupSize,
    this.overrides,
    this.nativeScenes,
    this.qualificationState,
    this.evidence,
    this.sourceLineage,
  );
  final String configSource, configDtype, nativeScenes, qualificationState;
  final String? evidence;
  final String sourceLineage;
  final int? defaultBits, groupSize;
  final List<FishDramaQuantizationGroup> overrides;
  String get runtimeId => 'mlx-audio-0.6.3-mlx-0.32.4-complete-v3';
  String get architecture => 'fish_drama3';
  String get platform => 'macos-arm64';
  int get sampleRate => 44100;
  int get channels => 1;
  String get pcm => 'float32';
  String get codecPrecision => 'not-declared';

  static FishDramaProfile _parse(
    Object? raw,
    String repository,
    String revision,
  ) {
    final value = _object(raw, 'Fish profile');
    _fields(value, const {
      'engineFamily',
      'configSource',
      'quantizationLayout',
      'runtime',
      'nativeFormat',
      'capabilities',
      'qualification',
      'sourceLineage',
    }, 'Fish profile');
    final source =
        'https://huggingface.co/$repository/resolve/$revision/config.json';
    if (value['engineFamily'] != 'fish_drama3' ||
        value['configSource'] != source) {
      throw const FormatException('Profile configuration identity mismatch');
    }
    final layout = _object(value['quantizationLayout'], 'quantization layout');
    _fields(layout, const {
      'configDtype',
      'defaultBits',
      'groupSize',
      'overrides',
      'unlistedModules',
      'codecPrecision',
    }, 'quantization layout');
    if (layout['configDtype'] != 'bfloat16' ||
        layout['unlistedModules'] != 'not-asserted' ||
        layout['codecPrecision'] != 'not-declared' ||
        !const [null, 4, 8].contains(layout['defaultBits']) ||
        (layout['defaultBits'] != null && layout['defaultBits'] is! int) ||
        !const [null, 64].contains(layout['groupSize']) ||
        (layout['groupSize'] != null && layout['groupSize'] is! int) ||
        (layout['defaultBits'] == null) != (layout['groupSize'] == null)) {
      throw const FormatException('Unsupported quantization layout');
    }
    final rawGroups = layout['overrides'];
    if (rawGroups is! List || rawGroups.length > 16) {
      throw const FormatException('Invalid quantization groups');
    }
    final groups = <FishDramaQuantizationGroup>[];
    final seen = <String>{};
    for (final raw in rawGroups) {
      final group = _object(raw, 'quantization group');
      _fields(group, const {
        'scope',
        'bits',
        'groupSize',
        'moduleCount',
      }, 'quantization group');
      if (!const {'experts', 'dense', 'tower'}.contains(group['scope']) ||
          !const {4, 8}.contains(group['bits']) ||
          group['bits'] is! int ||
          group['groupSize'] != 64 ||
          !seen.add('${group['scope']}:${group['bits']}')) {
        throw const FormatException('Unsupported quantization group');
      }
      groups.add(
        FishDramaQuantizationGroup._(
          group['scope'] as String,
          group['bits'] as int,
          64,
          _positiveInt(group['moduleCount'], 'moduleCount'),
        ),
      );
    }
    final runtime = _object(value['runtime'], 'runtime');
    _fields(runtime, const {'id', 'architecture', 'platform'}, 'runtime');
    if (runtime['id'] != 'mlx-audio-0.6.3-mlx-0.32.4-complete-v3' ||
        runtime['architecture'] != 'fish_drama3' ||
        runtime['platform'] != 'macos-arm64') {
      throw const FormatException('Profile requires an unsupported runtime');
    }
    final format = _object(value['nativeFormat'], 'native format');
    _fields(format, const {
      'codec',
      'sampleRate',
      'channels',
      'pcm',
    }, 'native format');
    if (format['codec'] != 'checkpoint codec.safetensors' ||
        format['sampleRate'] != 44100 ||
        format['sampleRate'] is! int ||
        format['channels'] != 1 ||
        format['pcm'] != 'float32') {
      throw const FormatException('Unsupported native speech format');
    }
    final caps = _object(value['capabilities'], 'capabilities');
    _fields(caps, const {
      'referenceVoices',
      'nativeScenes',
      'streaming',
      'speed',
    }, 'capabilities');
    // Only the original exact bf16 pin has bounded native-scene evidence. Even
    // this metadata cannot bypass the runtime's own qualification response.
    final original =
        repository == 'mlx-community/fish-audio-drama-3-bf16' &&
        revision == '8c5496f9af370bb9342ab98130b27b5389d1b1cb';
    if (caps['referenceVoices'] != 'supported' ||
        caps['streaming'] != 'runtime-validated' ||
        caps['speed'] != 'post-processing' ||
        !(caps['nativeScenes'] == 'unqualified' ||
            (original && caps['nativeScenes'] == 'bounded-qualified'))) {
      throw const FormatException(
        'Profile exceeds installed capability ceiling',
      );
    }
    final qualification = _object(value['qualification'], 'qualification');
    _fields(qualification, const {
      'state',
      'evidence',
      'memory',
    }, 'qualification');
    final state = qualification['state'];
    final evidence = qualification['evidence'];
    if (qualification['memory'] !=
            'requires-measured-runtime-device-envelope' ||
        !(state == 'requires-qualification' ||
            (original && state == 'bounded-native-evidence')) ||
        (state == 'bounded-native-evidence' && evidence == null) ||
        (evidence != null &&
            (evidence is! String ||
                !evidence.startsWith(
                  'https://github.com/kellyjanderson/readaloud/',
                )))) {
      throw const FormatException('Invalid qualification declaration');
    }
    return FishDramaProfile._(
      source,
      layout['configDtype'] as String,
      layout['defaultBits'] as int?,
      layout['groupSize'] as int?,
      List.unmodifiable(groups),
      caps['nativeScenes'] as String,
      state as String,
      evidence as String?,
      _nonempty(value['sourceLineage'], 'source lineage'),
    );
  }
}

final class FishDramaQuantizationGroup {
  const FishDramaQuantizationGroup._(
    this.scope,
    this.bits,
    this.groupSize,
    this.moduleCount,
  );
  final String scope;
  final int bits, groupSize, moduleCount;
}
