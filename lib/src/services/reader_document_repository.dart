import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../models/document_preparation.dart';
import 'reader_document_serialization_service.dart';

/// Single main-isolate admission owner. Each cache key has one active writer;
/// replacement revokes older writers before IO. Immutable generations keep old
/// readers consistent. One outstanding operation per session, no queued writes.
/// File IO/codec/hash work runs in short-lived workers. Cancellation revokes a
/// writer; in-flight immutable chunk output is an orphan, never a new manifest.
class ReaderDocumentRepository {
  ReaderDocumentRepository(this.rootPath);
  final String rootPath;
  static const schemaVersion = 1;
  static const dependencyVersion = 'rc2-prepared-ranges-v1';
  final Map<String, Object> _writers = {};
  int _generation = 0;
  final Map<String, Future<void>> _manifestRenames = {};

  String _key(String sourceKey) =>
      sha256.convert(utf8.encode(sourceKey)).toString();

  Future<ReaderDocumentCache?> open({
    required String sourceKey,
    required String sourceRevision,
    String dependencies = dependencyVersion,
  }) async {
    final path = '$rootPath/${_key(sourceKey)}';
    return Isolate.run(() async {
      try {
        final file = File('$path/manifest.json');
        if (await file.length() > 65536) return null;
        final envelope = (jsonDecode(await file.readAsString()) as Map)
            .cast<String, dynamic>();
        final payload = envelope['payload'] as String;
        if (sha256.convert(utf8.encode(payload)).toString() !=
            envelope['sha256']) {
          return null;
        }
        final m = (jsonDecode(payload) as Map).cast<String, dynamic>();
        if (m['schema'] != schemaVersion ||
            m['sourceRevision'] != sourceRevision ||
            m['dependencies'] != dependencies) {
          return null;
        }
        final generation = m['generation'] as String;
        if (!RegExp(r'^[0-9]+-[0-9]+$').hasMatch(generation)) return null;
        if (await File('$path/$generation/invalidated').exists()) return null;
        final count = m['count'] as int;
        if (count < 0 ||
            m['sourceEnd'] is! int ||
            m['wordEnd'] is! int ||
            m['segmentEnd'] is! int ||
            m['complete'] is! bool) {
          return null;
        }
        return ReaderDocumentCache._('$path/$generation', Map.unmodifiable(m));
      } catch (_) {
        return null; // Missing, corrupt and incompatible manifests are misses.
      }
    });
  }

  Future<ReaderDocumentCheckpoint> begin({
    required String sourceKey,
    required DocumentPreparationRequest request,
    String dependencies = dependencyVersion,
  }) async {
    final key = _key(sourceKey);
    final token = Object();
    _writers[key] = token;
    await _manifestRenames[key];
    if (!identical(_writers[key], token)) {
      throw StateError('Writer replaced during admission');
    }
    final generation =
        '${DateTime.now().microsecondsSinceEpoch}-${++_generation}';
    final checkpoint = ReaderDocumentCheckpoint._(
      this,
      key,
      token,
      generation,
      request.identityOnly,
      dependencies,
    );
    await Directory(checkpoint.path).create(recursive: true);
    return checkpoint;
  }
}

/// A bounded manifest lookup is independent of book size. readRange validates
/// exactly one immutable file; errors are FormatException, never EOF. A partial
/// cache may offer valid committed ranges but is never an exportable full book.
class ReaderDocumentCache {
  ReaderDocumentCache._(this.path, this.manifest);
  final String path;
  final Map<String, dynamic> manifest;
  int get rangeCount => manifest['count'] as int;
  bool get isComplete => manifest['complete'] as bool;
  DocumentIdentityMigration? identityMigration(
    DocumentPreparationRequest request,
  ) {
    final proof = manifest['acquisition'];
    if (!isComplete ||
        proof is! Map ||
        request.effectiveSourceRevision != sourceRevision ||
        (proof['byteCount'] as int) <= 8192) {
      return null;
    }
    return DocumentIdentityMigration(
      ownerId: request.ownerId,
      documentRevision: request.revision,
      sourceRevision: request.effectiveSourceRevision,
      watchSession: request.watchSession ?? 0,
      provisionalDocumentId: proof['provisionalDocumentId'] as String,
      canonicalDocumentId: 'doc_acquired_${proof['sha256']}',
      integrityBasis: DocumentIdentityIntegrityBasis.values.byName(
        proof['basis'] as String,
      ),
    );
  }

  String get sourceRevision => manifest['sourceRevision'] as String;

  /// Revokes only this immutable generation. A stale reader cannot remove a
  /// newer manifest: each generation has its own persistent invalidation marker.
  /// Recovery deliberately rebuilds from source, rather than resuming a prefix.
  Future<void> invalidate() async {
    await File('$path/invalidated').writeAsString('invalid', flush: true);
  }

  bool _reading = false;

  Future<DocumentPreparationPublication> readRange(
    int sequence, {
    required DocumentPreparationRequest request,
  }) async {
    if (_reading) {
      throw StateError('Only one cache range read may be in flight');
    }
    _reading = true;
    try {
      return await _readRange(sequence, request: request);
    } finally {
      _reading = false;
    }
  }

  Future<DocumentPreparationPublication> _readRange(
    int sequence, {
    required DocumentPreparationRequest request,
  }) async {
    if (sequence < 1 || sequence > rangeCount) {
      throw RangeError.range(sequence, 1, rangeCount);
    }
    if (request.effectiveSourceRevision != sourceRevision) {
      throw const FormatException('Stale source revision');
    }
    final identity = request.identityOnly;
    return Isolate.run(() async {
      try {
        if (await File('$path/invalidated').exists()) {
          throw const FormatException('Cache generation was invalidated');
        }
        final f = File('$path/$sequence.json');
        if (await f.length() > ReaderDocumentCheckpoint.maxChunkBytes) {
          throw const FormatException('Oversized cache range');
        }
        final e = (jsonDecode(await f.readAsString()) as Map)
            .cast<String, dynamic>();
        final payload = e['payload'] as String;
        if (sha256.convert(utf8.encode(payload)).toString() != e['sha256']) {
          throw const FormatException('Corrupt cache range');
        }
        final m = (jsonDecode(payload) as Map).cast<String, dynamic>();
        if (m['sequence'] != sequence ||
            m['sourceRevision'] != sourceRevision) {
          throw const FormatException('Stale cache range');
        }
        final r = (m['range'] as Map).cast<String, dynamic>();
        final coverage = (m['coverage'] as List)
            .map((v) => PreparationStage.values.byName(v as String))
            .toSet();
        final document = const ReaderDocumentSerializationService()
            .deserializeFromJsonString(m['document'] as String);
        final range = PreparedDocumentRange(
          sourceStart: r['sourceStart'],
          sourceEnd: r['sourceEnd'],
          wordStart: r['wordStart'],
          wordEnd: r['wordEnd'],
          segmentStart: r['segmentStart'],
          segmentEnd: r['segmentEnd'],
          sourceUnit: r['sourceUnit'],
          sourceLocator: r['sourceLocator'],
        );
        if (range.sourceStart < 0 ||
            range.sourceEnd < range.sourceStart ||
            range.wordEnd - range.wordStart != document.wordCount ||
            range.segmentEnd - range.segmentStart !=
                document.speechDocument.segments.length) {
          throw const FormatException('Invalid range coverage');
        }
        return DocumentPreparationPublication(
          request: identity,
          sequence: sequence,
          range: range,
          fragment: document,
          coverage: coverage,
          progress: [
            PreparationProgress(
              stage: PreparationStage.persistence,
              state: PreparationWorkState.complete,
              completed: sequence,
              total: rangeCount,
              unit: 'ranges',
              scope: 'cache',
            ),
          ],
          isLast: isComplete && sequence == rangeCount,
        );
      } catch (error) {
        throw FormatException('Unreadable cache range $sequence: $error');
      }
    });
  }
}

class ReaderDocumentCheckpoint {
  ReaderDocumentCheckpoint._(
    this._repository,
    this._key,
    this._token,
    this._generation,
    this.request,
    this.dependencies,
  );
  static const maxChunkBytes = 4 * 1024 * 1024;
  final ReaderDocumentRepository _repository;
  final String _key;
  final Object _token;
  final String _generation;
  final DocumentPreparationRequest request;
  final String dependencies;
  int _count = 0;
  int get committedRangeCount => _count;
  int _sourceEnd = 0;
  int _wordEnd = 0;
  int _segmentEnd = 0;
  bool _busy = false;
  Map<String, Object?>? _acquisition;
  bool _closed = false;
  String get path => '${_repository.rootPath}/$_key/$_generation';
  bool get isCurrent =>
      !_closed && identical(_repository._writers[_key], _token);
  void cancel() {
    _closed = true;
  }

  /// Called before granting the producer its next credit. Partial checkpoints
  /// commit after each immutable range; publication never rewrites a prefix.
  Future<void> commit(DocumentPreparationPublication publication) async {
    _enter();
    try {
      final r = publication.range;
      final q = publication.request;
      if (q.ownerId != request.ownerId ||
          q.revision != request.revision ||
          q.watchSession != request.watchSession ||
          q.effectiveSourceRevision != request.effectiveSourceRevision ||
          publication.sequence != _count + 1 ||
          r.sourceStart != _sourceEnd ||
          r.wordStart != _wordEnd ||
          r.segmentStart != _segmentEnd ||
          r.sourceEnd < r.sourceStart ||
          r.wordEnd - r.wordStart != publication.fragment.wordCount ||
          r.segmentEnd - r.segmentStart !=
              publication.fragment.speechDocument.segments.length ||
          !publication.isPreparationReady) {
        throw const FormatException('Non-contiguous or stale checkpoint');
      }
      final target = '$path/${publication.sequence}.json';
      final sourceRevision = request.effectiveSourceRevision;
      await Isolate.run(() async {
        final payload = jsonEncode({
          'sequence': publication.sequence,
          'sourceRevision': sourceRevision,
          'range': {
            'sourceStart': r.sourceStart,
            'sourceEnd': r.sourceEnd,
            'wordStart': r.wordStart,
            'wordEnd': r.wordEnd,
            'segmentStart': r.segmentStart,
            'segmentEnd': r.segmentEnd,
            'sourceUnit': r.sourceUnit,
            'sourceLocator': r.sourceLocator,
          },
          'coverage': publication.coverage.map((v) => v.name).toList(),
          'document': const ReaderDocumentSerializationService()
              .serializeToJsonString(publication.fragment),
        });
        final content = jsonEncode({
          'sha256': sha256.convert(utf8.encode(payload)).toString(),
          'payload': payload,
        });
        if (utf8.encode(content).length > maxChunkBytes) {
          throw const FormatException('Checkpoint range exceeds bounded size');
        }
        await _atomicWrite(target, content);
      });
      if (!isCurrent) throw StateError('Checkpoint was replaced');
      _count++;
      _sourceEnd = r.sourceEnd;
      _wordEnd = r.wordEnd;
      _segmentEnd = r.segmentEnd;
      await _manifest(false);
    } finally {
      _busy = false;
    }
  }

  /// Only successful producer EOF may call this. Last fragment alone is not EOF.
  Future<void> complete({
    SourceAcquisitionReceipt? receipt,
    String? provisionalDocumentId,
  }) async {
    _enter();
    try {
      if (_count == 0) throw StateError('Cannot complete an empty checkpoint');
      if (receipt != null) {
        if (receipt.ownerId != request.ownerId ||
            receipt.documentRevision != request.revision ||
            receipt.sourceRevision != request.effectiveSourceRevision ||
            receipt.watchSession != request.watchSession ||
            provisionalDocumentId == null ||
            receipt.byteCount < 0 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(receipt.sha256)) {
          throw const FormatException('Invalid acquisition receipt');
        }
        _acquisition = {
          'byteCount': receipt.byteCount,
          'sha256': receipt.sha256,
          'basis': receipt.integrityBasis.name,
          'provisionalDocumentId': provisionalDocumentId,
        };
      }
      await _manifest(true);
      _closed = true;
    } finally {
      _busy = false;
    }
  }

  void _enter() {
    if (!isCurrent) throw StateError('Checkpoint was cancelled or replaced');
    if (_busy) {
      throw StateError('Only one checkpoint operation may be in flight');
    }
    _busy = true;
  }

  Future<void> _manifest(bool complete) async {
    final contents = jsonEncode({
      'schema': ReaderDocumentRepository.schemaVersion,
      'dependencies': dependencies,
      'sourceRevision': request.effectiveSourceRevision,
      'generation': _generation,
      'count': _count,
      'sourceEnd': _sourceEnd,
      'wordEnd': _wordEnd,
      'segmentEnd': _segmentEnd,
      'complete': complete,
      'acquisition': _acquisition,
    });
    final temp = File(
      '${_repository.rootPath}/$_key/manifest.$_generation.tmp',
    );
    final envelope = jsonEncode({
      'sha256': sha256.convert(utf8.encode(contents)).toString(),
      'payload': contents,
    });
    await temp.writeAsString(envelope, flush: true);
    if (!isCurrent) {
      await temp.delete();
      throw StateError('Checkpoint was replaced');
    }
    // No await between generation check and initiating atomic rename.
    final rename = temp
        .rename('${_repository.rootPath}/$_key/manifest.json')
        .then<void>((_) {});
    _repository._manifestRenames[_key] = rename;
    try {
      await rename;
    } finally {
      if (identical(_repository._manifestRenames[_key], rename)) {
        _repository._manifestRenames.remove(_key);
      }
    }
  }
}

Future<void> _atomicWrite(String path, String contents) async {
  final temporary = File('$path.tmp');
  await temporary.writeAsString(contents, flush: true);
  await temporary.rename(path);
}
