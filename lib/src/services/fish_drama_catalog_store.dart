import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../models/speech_engine_catalog.dart';

/// The installed code's ceiling. A catalog cannot install code, dependencies or
/// expand synthesis capabilities. A different runtime needs an application update.
const fishDramaCatalogRuntime = 'mlx-audio-0.6.3-mlx-0.32.4-complete-v3';
const _maximumDocumentBytes = 256 * 1024;
const _manifestName = 'fish_drama_catalog_update.json';
const _modelsName = 'fish_drama_models.json';
const _checksumsName = 'fish_drama_model_checksums.json';
const _origin = 'https://raw.githubusercontent.com/kellyjanderson/readaloud';

/// Immutable input shared by Dart lookup and the managed Python asset owner.
/// Current sessions retain this snapshot even if a refresh publishes a successor.
final class FishDramaCatalogSnapshot {
  FishDramaCatalogSnapshot._({
    required this.catalog,
    required this.modelsJson,
    required this.checksumsJson,
    required this.catalogVersion,
    required this.manifestJson,
  }) : identity = sha256
           .convert(
             utf8.encode(jsonEncode([manifestJson, modelsJson, checksumsJson])),
           )
           .toString();

  final FishDramaCatalog catalog;
  final String modelsJson;
  final String checksumsJson;
  final int catalogVersion;
  final String? manifestJson;
  final String identity;

  String get _envelope => jsonEncode({
    'manifest': manifestJson,
    'models': modelsJson,
    'checksums': checksumsJson,
  });
}

final class FishDramaCatalogRefreshResult {
  const FishDramaCatalogRefreshResult(this.snapshot, this.error);
  final FishDramaCatalogSnapshot snapshot;
  final Object? error;
  bool get succeeded => error == null;
}

/// Injectable byte transport for deterministic tests; production uses the Dart
/// platform HTTP client, with redirects disabled and no downloaded dependencies.
typedef FishDramaCatalogTransport = Future<List<int>> Function(Uri uri);

/// One session owns this store, one active refresh, its HTTP connection and its
/// cancellation signal. No queue or timer retry exists. Concurrent refresh calls
/// coalesce; close cancels I/O, fences validation/publication, and drains cleanup.
/// The orchestrator must drain the retiring session before creating its successor.
/// Parsing/hashing happens in a short-lived isolate; filesystem I/O is asynchronous.
/// A failed refresh returns a reason and preserves the captured last valid value.
final class FishDramaCatalogStore {
  FishDramaCatalogStore({
    required this.root,
    required this.bundledModelsJson,
    required this.bundledChecksumsJson,
    this.transport,
    this.timeout = const Duration(seconds: 8),
  });

  final Directory root;
  final String bundledModelsJson;
  final String bundledChecksumsJson;
  final FishDramaCatalogTransport? transport;
  final Duration timeout;
  Future<FishDramaCatalogSnapshot>? _loading;
  Future<FishDramaCatalogRefreshResult>? _refreshing;
  FishDramaCatalogSnapshot? _current;
  final _closedSignal = Completer<void>();
  HttpClient? _client;
  void Function()? _cancelActive;
  bool get _closed => _closedSignal.isCompleted;
  File get _persisted => File('${root.path}/catalog/last-valid.json');

  Future<FishDramaCatalogSnapshot> load() => _loading ??= _load();

  Future<FishDramaCatalogSnapshot> _load() async {
    _checkOpen();
    // Invalid bundled data is a packaging error, never hidden by a disk cache.
    final bundled = await _parseSnapshotOffThread(
      null,
      bundledModelsJson,
      bundledChecksumsJson,
    );
    var selected = bundled;
    try {
      if (await _persisted.length() > _maximumDocumentBytes * 3) {
        throw const FormatException('Oversized saved Fish catalog');
      }
      final envelope = await _persisted.readAsString();
      selected = await _parseEnvelopeOffThread(envelope);
    } on FileSystemException {
      // No saved catalog, unreadable cache or interrupted first publication.
    } on FormatException {
      // Corrupt/incompatible saved data never replaces the trusted bundle.
    }
    _checkOpen();
    return _current = selected;
  }

  /// Production follows the one fixed first-party manifest. Qualification may
  /// pin that same path to an immutable commit, never another host/repository.
  Future<FishDramaCatalogRefreshResult> refresh({String? manifestRevision}) {
    _checkOpen();
    if (manifestRevision != null && !_commit.hasMatch(manifestRevision)) {
      throw const FormatException('Catalog source must be an immutable commit');
    }
    return _refreshing ??= _refresh(manifestRevision).whenComplete(() {
      _refreshing = null;
    });
  }

  Future<FishDramaCatalogRefreshResult> _refresh(String? source) async {
    final previous = await load();
    final cancelled = Completer<void>();
    void cancel() {
      if (!cancelled.isCompleted) cancelled.complete();
      _client?.close(force: true);
    }

    final deadline = Timer(timeout, cancel);
    _cancelActive = cancel;
    _client = transport == null
        ? (HttpClient()..connectionTimeout = timeout)
        : null;
    try {
      final manifestJson = await _get(
        Uri.parse('$_origin/${source ?? 'main'}/assets/$_manifestName'),
        cancelled.future,
      );
      final metadata = await _parseMetadataOffThread(manifestJson);
      final revision = metadata['sourceRevision'] as String;
      final modelsJson = await _get(
        Uri.parse('$_origin/$revision/assets/$_modelsName'),
        cancelled.future,
      );
      final checksumsJson = await _get(
        Uri.parse('$_origin/$revision/assets/$_checksumsName'),
        cancelled.future,
      );
      final candidate = await _parseSnapshotOffThread(
        manifestJson,
        modelsJson,
        checksumsJson,
      );
      _checkAttempt(cancelled);
      if (candidate.catalogVersion < previous.catalogVersion ||
          (candidate.catalogVersion == previous.catalogVersion &&
              candidate.identity != previous.identity)) {
        throw const FormatException('Catalog rollback or version collision');
      }
      // Publish one envelope, never independently replace models/checksums.
      await _persisted.parent.create(recursive: true);
      final stage = await _persisted.parent.createTemp('.refresh-');
      try {
        final file = File('${stage.path}/catalog.json');
        await file.writeAsString(candidate._envelope, flush: true);
        _checkAttempt(cancelled);
        // Atomic rename is the commit boundary. Once issued it cannot be
        // cancelled; close drains it and the result describes committed disk
        // state even if the session retires while the syscall completes.
        await file.rename(_persisted.path);
      } finally {
        await stage.delete(recursive: true);
      }
      _current = candidate;
      _loading = Future.value(candidate);
      return FishDramaCatalogRefreshResult(candidate, null);
    } catch (error) {
      return FishDramaCatalogRefreshResult(_current ?? previous, error);
    } finally {
      deadline.cancel();
      _client?.close(force: true);
      _client = null;
      _cancelActive = null;
    }
  }

  Future<String> _get(Uri uri, Future<void> cancelled) async {
    Future<List<int>> fetch() async {
      if (transport case final substitute?) {
        return substitute(uri);
      }
      final request = await _client!.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > _maximumDocumentBytes) {
        throw HttpException(
          'Catalog HTTP ${response.statusCode} or oversized body',
          uri: uri,
        );
      }
      final bytes = <int>[];
      await for (final part in response) {
        if (bytes.length + part.length > _maximumDocumentBytes) {
          throw const FormatException('Oversized Fish catalog response');
        }
        bytes.addAll(part);
      }
      return bytes;
    }

    final bytes = await Future.any([
      fetch(),
      cancelled.then<List<int>>(
        (_) => throw StateError('Fish catalog refresh cancelled or timed out'),
      ),
    ]);
    if (bytes.length > _maximumDocumentBytes) {
      throw const FormatException('Oversized Fish catalog response');
    }
    return utf8.decode(bytes);
  }

  void _checkOpen() {
    if (_closed) throw StateError('Fish catalog store is closed');
  }

  void _checkAttempt(Completer<void> cancelled) {
    _checkOpen();
    if (cancelled.isCompleted) {
      throw StateError('Fish catalog refresh timed out');
    }
  }

  Future<void> close() async {
    if (!_closed) _closedSignal.complete();
    _cancelActive?.call();
    _client?.close(force: true);
    await _refreshing;
  }
}

final _commit = RegExp(r'^[a-f0-9]{40}$');
final _digest = RegExp(r'^[a-f0-9]{64}$');

// Top-level wrappers prevent isolate closures retaining unsendable store/HTTP
// state from the calling session's method context.
Future<FishDramaCatalogSnapshot> _parseSnapshotOffThread(
  String? manifest,
  String models,
  String checksums,
) => Isolate.run(() => _parseSnapshot(manifest, models, checksums));
Future<FishDramaCatalogSnapshot> _parseEnvelopeOffThread(String envelope) =>
    Isolate.run(() => _parseEnvelope(envelope));
Future<Map<String, dynamic>> _parseMetadataOffThread(String manifest) =>
    Isolate.run(() => _parseMetadata(manifest));

Map<String, dynamic> _object(Object? value, Set<String> fields) {
  if (value is! Map<String, dynamic> ||
      value.length != fields.length ||
      !fields.containsAll(value.keys)) {
    throw const FormatException('Unsupported Fish catalog metadata fields');
  }
  return value;
}

Map<String, dynamic> _parseMetadata(String json) {
  final metadata = _object(jsonDecode(json), const {
    'schemaVersion',
    'catalogVersion',
    'sourceRevision',
    'runtime',
    'files',
  });
  if (metadata['schemaVersion'] != 1 ||
      metadata['schemaVersion'] is! int ||
      metadata['catalogVersion'] is! int ||
      metadata['catalogVersion'] <= 0 ||
      metadata['sourceRevision'] is! String ||
      !_commit.hasMatch(metadata['sourceRevision'])) {
    throw const FormatException('Unsupported Fish catalog schema or revision');
  }
  final runtime = _object(metadata['runtime'], const {
    'id',
    'architecture',
    'platform',
    'capabilities',
  });
  if (runtime['id'] != fishDramaCatalogRuntime ||
      runtime['architecture'] != 'fish_drama3' ||
      runtime['platform'] != 'macos-arm64' ||
      runtime['capabilities'] != 'installed-code-only') {
    throw const FormatException('Fish catalog requires an unsupported runtime');
  }
  final files = _object(metadata['files'], const {_modelsName, _checksumsName});
  for (final digest in files.values) {
    if (digest is! String || !_digest.hasMatch(digest)) {
      throw const FormatException('Catalog assets require SHA-256 digests');
    }
  }
  return metadata;
}

FishDramaCatalogSnapshot _parseSnapshot(
  String? manifest,
  String models,
  String checksums,
) {
  Map<String, dynamic>? metadata;
  if (manifest != null) {
    metadata = _parseMetadata(manifest);
    final hashes = metadata['files'] as Map;
    if (sha256.convert(utf8.encode(models)).toString() != hashes[_modelsName] ||
        sha256.convert(utf8.encode(checksums)).toString() !=
            hashes[_checksumsName]) {
      throw const FormatException('Fish catalog asset digest mismatch');
    }
  }
  final catalog = FishDramaCatalog.fromJson(
    modelsJson: models,
    checksumsJson: checksums,
  );
  if (manifest != null) {
    for (final variant in catalog.variants.values) {
      if (variant.integrityManifest == null ||
          variant.requiredFiles.any(
            (file) =>
                !const {
                  'LICENSE',
                  'NOTICE',
                  'chat_template.jinja',
                }.contains(file) &&
                !file.endsWith('.json') &&
                !file.endsWith('.safetensors'),
          )) {
        throw const FormatException(
          'Refreshed catalog must contain verified data only',
        );
      }
    }
  }
  return FishDramaCatalogSnapshot._(
    catalog: catalog,
    modelsJson: models,
    checksumsJson: checksums,
    catalogVersion: metadata?['catalogVersion'] as int? ?? 0,
    manifestJson: manifest,
  );
}

FishDramaCatalogSnapshot _parseEnvelope(String envelope) {
  final data = _object(jsonDecode(envelope), const {
    'manifest',
    'models',
    'checksums',
  });
  if (data['manifest'] is! String ||
      data['models'] is! String ||
      data['checksums'] is! String) {
    throw const FormatException('Invalid saved Fish catalog');
  }
  return _parseSnapshot(data['manifest'], data['models'], data['checksums']);
}
