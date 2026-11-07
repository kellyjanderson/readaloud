import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show ZLibDecoder;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../models/radoc_audio_manifest.dart';

/// Finite limits also bound one synchronous archive-encoder step. Larger books
/// need an explicit policy change; ZIP64 and multi-volume archives are refused.
class RadocPackageLimits {
  const RadocPackageLimits({
    this.maxArchiveBytes = 2 * 1024 * 1024 * 1024,
    this.maxDirectoryBytes = 8 * 1024 * 1024,
    this.maxMembers = 10000,
    this.maxManifestBytes = 2 * 1024 * 1024,
    this.maxMemberBytes = 64 * 1024 * 1024,
    this.maxTotalMemberBytes = 2 * 1024 * 1024 * 1024,
    this.operationTimeout = const Duration(minutes: 5),
  });
  final int maxArchiveBytes;
  final int maxDirectoryBytes;
  final int maxMembers;
  final int maxManifestBytes;
  final int maxMemberBytes;
  final int maxTotalMemberBytes;
  final Duration operationTimeout;
}

class RadocPackageException implements Exception {
  const RadocPackageException(this.message);
  final String message;
  @override
  String toString() => 'RadocPackageException: $message';
}

class RadocPackageCancelled extends RadocPackageException {
  const RadocPackageCancelled()
    : super('Package operation canceled or obsolete.');
}

/// Stage-local work accounting, never a fabricated whole-operation percentage.
/// A null total denotes a wait/flush stage. Publication is not complete until
/// the operation's future succeeds, even when a copying stage reaches its total.
class RadocPackageProgress {
  const RadocPackageProgress({
    required this.stage,
    required this.completed,
    required this.total,
    required this.unit,
    this.member,
  });
  final String stage;
  final int completed;
  final int? total;
  final String unit;
  final String? member;
}

/// A validated, bounded index. No prepared JSON or PCM is retained here.
/// This handle belongs to its creating service and becomes unusable on dispose.
class RadocAudioBook {
  const RadocAudioBook._({
    required this.manifest,
    required this.manifestDigest,
    required this.packagePath,
    required String cachePath,
  }) : _cachePath = cachePath;
  final RadocAudioManifest manifest;

  /// SHA-256 of the exact manifest bytes, rechecked before lazy reads.
  final String manifestDigest;
  final String packagePath;
  final String _cachePath;
}

/// One active request, zero waiting queue. All archive, JSON, hash and bulk I/O
/// run in a short-lived isolate; immutable DTOs/path results cross its port.
/// The caller owns document/playback revisions via [isCurrent] callbacks.
///
/// A temporary private directory is created per open under [cacheDirectory]
/// (system temporary directory by default). Only generated hash filenames are
/// used there. [dispose] removes these caches after draining the active worker.
/// Callers must retain the service while admitted players use those files.
class RadocAudioPackage {
  RadocAudioPackage({
    this.limits = const RadocPackageLimits(),
    this.onProgress,
    this.createExportStage,
    Directory? cacheDirectory,
  }) : _cacheDirectory = cacheDirectory?.absolute.path;

  final RadocPackageLimits limits;
  final void Function(RadocPackageProgress)? onProgress;

  /// Supplies a fresh, exclusively owned directory on the destination volume.
  /// macOS sandbox callers use the platform item-replacement directory: a save
  /// panel's file grant does not permit creating arbitrary sibling directories.
  /// The service owns cleanup, including cancellation while this future waits.
  /// This factory must perform filesystem work off the UI thread and must not
  /// alter the destination. A cross-volume stage fails at rename, without copy.
  final Future<Directory> Function(File destination)? createExportStage;
  final String? _cacheDirectory;
  final Set<String> _caches = {};
  _Active? _active;
  bool _closed = false;
  Future<void>? _disposal;

  /// Reads four bytes only. Legacy JSON .radoc stays on its existing route.
  static Future<bool> isPackage(File file) async {
    final handle = await file.open();
    try {
      final bytes = await handle.read(4);
      return bytes.length == 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4b &&
          bytes[2] == 3 &&
          bytes[3] == 4;
    } finally {
      await handle.close();
    }
  }

  Future<RadocAudioBook> open(File file, {bool Function()? isCurrent}) async {
    final book = await _run<RadocAudioBook>('open', {
      'path': file.absolute.path,
      'cacheRoot': _cacheDirectory,
    }, isCurrent);
    _caches.add(book._cachePath);
    return book;
  }

  /// Member files contain the existing prepared/analysis codecs or native WAVs.
  /// Caller pins source artifacts until this future drains. Hashes and sizes
  /// are filled from staged copies; supplied stale checksum metadata is ignored.
  Future<RadocAudioManifest> export({
    required File destination,
    required RadocAudioManifest manifest,
    required Map<String, File> members,
    bool Function()? isCurrent,
  }) => _run<RadocAudioManifest>('export', {
    'path': destination.absolute.path,
    'manifest': manifest,
    'members': Map<String, String>.unmodifiable(
      members.map((name, file) => MapEntry(name, file.absolute.path)),
    ),
  }, isCurrent);

  /// Accepts only a name from this book's validated manifest. Later corruption
  /// fails here, never as EOF or silently completed coverage.
  Future<File> materializeMember(
    RadocAudioBook book,
    String member, {
    bool Function()? isCurrent,
  }) async {
    if (!_caches.contains(book._cachePath) ||
        !book.manifest.referencedMembers.contains(member)) {
      throw const RadocPackageException('Unowned book or unapproved member.');
    }
    final path = await _run<String>('materialize', {
      'book': book,
      'member': member,
    }, isCurrent);
    return File(path);
  }

  Future<void> cancelAndDrain() async {
    final active = _active;
    if (active == null) return;
    active.cancel();
    await active.drained.future;
  }

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _closed = true;
    await cancelAndDrain();
    final caches = _caches.toList();
    _caches.clear();
    await Isolate.run(() async {
      for (final path in caches) {
        final directory = Directory(path);
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    });
  }

  Future<T> _run<T>(
    String operation,
    Map<String, Object?> payload,
    bool Function()? isCurrent,
  ) async {
    if (_closed) throw StateError('RadocAudioPackage is disposed.');
    if (_active != null) throw StateError('Package operation already active.');
    if (!(isCurrent?.call() ?? true)) throw const RadocPackageCancelled();
    final active = _Active();
    _active = active;
    final receive = ReceivePort();
    final result = Completer<T>();
    Object? outcome;
    Object? failure;
    var receivedResult = false;
    var admitted = false;
    final subscription = receive.listen((message) {
      if (message == null) {
        // onExit arrives after the worker's final result on this same port.
        if (!result.isCompleted) {
          if (!receivedResult) {
            result.completeError(
              const RadocPackageException('Package worker exited.'),
            );
          } else if (!admitted && (active.cancelled || !_current(isCurrent))) {
            result.completeError(const RadocPackageCancelled());
          } else if (failure != null) {
            result.completeError(failure!);
          } else {
            result.complete(outcome as T);
          }
        }
        return;
      }
      if (message is List &&
          message.length == 2 &&
          message[0] is String &&
          message[0] != 'port' &&
          message[0] != 'admit' &&
          message[0] != 'ok' &&
          message[0] != 'error' &&
          message[0] != 'progress') {
        failure = RadocPackageException('Package worker failed: ${message[0]}');
        receivedResult = true;
        return;
      }
      final event = message as List;
      switch (event[0]) {
        case 'port':
          active.port = event[1] as SendPort;
          if (active.cancelled) active.port!.send('cancel');
        case 'admit':
          bool current;
          try {
            current = !active.cancelled && (isCurrent?.call() ?? true);
          } catch (_) {
            current = false;
          }
          // This synchronous check is publication's linearization point.
          // A later cancel cannot revoke an already-authorized atomic rename.
          admitted = current && operation == 'export';
          active.port!.send(current ? 'commit' : 'cancel');
        case 'progress':
          if (!active.cancelled && _current(isCurrent)) {
            try {
              onProgress?.call(event[1] as RadocPackageProgress);
            } catch (_) {
              active.cancel();
            }
          } else {
            active.cancel();
          }
          active.port!.send('progress-ack');
        case 'ok':
          outcome = event[1];
          if (outcome case RadocAudioBook book) _caches.add(book._cachePath);
          receivedResult = true;
        case 'error':
          failure = event[1] == 'cancelled'
              ? const RadocPackageCancelled()
              : RadocPackageException(event[1] as String);
          receivedResult = true;
      }
    });
    final timer = Timer(limits.operationTimeout, active.cancel);
    Directory? exportStage;
    try {
      if (operation == 'export' && createExportStage != null) {
        exportStage = await createExportStage!(File(payload['path'] as String));
        if (active.cancelled || !_current(isCurrent)) {
          throw const RadocPackageCancelled();
        }
        payload = {...payload, 'exportStage': exportStage.absolute.path};
      }
      await Isolate.spawn(
        _packageWorker,
        _Work(receive.sendPort, operation, payload, limits),
        onError: receive.sendPort,
        onExit: receive.sendPort,
        errorsAreFatal: true,
        debugName: 'radoc-package-$operation',
      );
      return await result.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
      receive.close();
      try {
        // The worker normally removes this directory. Retain ownership here
        // too, for cancellation during native allocation or a spawn failure.
        final stagePath = exportStage?.path;
        if (stagePath != null) {
          await _removeExportStage(stagePath);
        }
      } finally {
        _active = null;
        active.drained.complete();
      }
    }
  }
}

// Keep the cleanup isolate's closure out of _run's context, which also owns
// unsendable ReceivePorts/completers. Only this immutable path crosses over.
Future<void> _removeExportStage(String path) => Isolate.run(() async {
  final stage = Directory(path);
  if (await stage.exists()) await stage.delete(recursive: true);
});

class _Active {
  SendPort? port;
  bool cancelled = false;
  final drained = Completer<void>();
  void cancel() {
    cancelled = true;
    port?.send('cancel');
  }
}

class _Work {
  const _Work(this.port, this.operation, this.payload, this.limits);
  final SendPort port;
  final String operation;
  final Map<String, Object?> payload;
  final RadocPackageLimits limits;
}

class _Worker {
  _Worker(this.work);
  final _Work work;
  bool cancelled = false;
  final admission = Completer<bool>();
  Completer<void>? progressAck;

  void check() {
    if (cancelled) throw const RadocPackageCancelled();
  }

  Future<void> checkpoint() async {
    await Future<void>.delayed(Duration.zero);
    check();
  }

  Future<void> admit() async {
    await checkpoint();
    work.port.send(['admit', null]);
    if (!await admission.future) throw const RadocPackageCancelled();
    // No await between permission and the following synchronous atomic rename.
    check();
  }

  Future<void> progress(
    String stage,
    int completed,
    int? total, {
    String unit = 'bytes',
    String? member,
  }) async {
    check();
    final ack = Completer<void>();
    progressAck = ack;
    work.port.send([
      'progress',
      RadocPackageProgress(
        stage: stage,
        completed: completed,
        total: total,
        unit: unit,
        member: member,
      ),
    ]);
    // Exactly one outstanding progress message; the UI port cannot accumulate
    // an unbounded backlog while a worker copies/decompresses a large member.
    await ack.future;
    progressAck = null;
    check();
  }
}

Future<void> _packageWorker(_Work work) async {
  final commands = ReceivePort();
  final owner = _Worker(work);
  final subscription = commands.listen((message) {
    if (message == 'cancel') {
      owner.cancelled = true;
      if (!owner.admission.isCompleted) owner.admission.complete(false);
      if (owner.progressAck case final ack? when !ack.isCompleted) {
        ack.complete();
      }
    } else if (message == 'commit' && !owner.admission.isCompleted) {
      owner.admission.complete(true);
    } else if (message == 'progress-ack') {
      if (owner.progressAck case final ack? when !ack.isCompleted) {
        ack.complete();
      }
    }
  });
  work.port.send(['port', commands.sendPort]);
  try {
    final Object result;
    switch (work.operation) {
      case 'open':
        final index = await _openIndex(work.payload['path'] as String, owner);
        try {
          final root = work.payload['cacheRoot'] as String?;
          final parent = root == null ? Directory.systemTemp : Directory(root);
          await parent.create(recursive: true);
          final cache = await parent.createTemp('radoc-audio-');
          try {
            await owner.checkpoint();
            result = RadocAudioBook._(
              manifest: index.manifest,
              manifestDigest: index.digest,
              packagePath: work.payload['path'] as String,
              cachePath: cache.path,
            );
          } catch (_) {
            await cache.delete(recursive: true);
            rethrow;
          }
        } finally {
          await index.input.close();
        }
      case 'export':
        result = await _export(owner);
      case 'materialize':
        result = await _materialize(owner);
      default:
        throw const RadocPackageException('Unknown package operation.');
    }
    work.port.send(['ok', result]);
  } catch (error) {
    work.port.send([
      'error',
      error is RadocPackageCancelled ? 'cancelled' : error.toString(),
    ]);
  } finally {
    await subscription.cancel();
    commands.close();
  }
}

Future<RadocAudioManifest> _export(_Worker owner) async {
  final payload = owner.work.payload;
  final limits = owner.work.limits;
  final destination = File(payload['path'] as String);
  final draft = payload['manifest'] as RadocAudioManifest;
  final sources = payload['members'] as Map<String, String>;
  draft.validate(requireMembers: false);
  final refs = draft.referencedMembers;
  if (sources.length != refs.length ||
      !sources.keys.toSet().containsAll(refs)) {
    throw const RadocPackageException(
      'Export files differ from manifest references.',
    );
  }
  _bound(sources.length + 1, limits.maxMembers, 'member count');
  final suppliedStage = payload['exportStage'] as String?;
  final stage = suppliedStage == null
      ? await destination.parent.createTemp('.radoc-stage-')
      : Directory(suppliedStage);
  try {
    final members = <RadocAudioMember>[];
    final staged = <String, File>{};
    var total = 0;
    for (final name in refs) {
      await owner.checkpoint();
      final source = File(sources[name]!);
      if (source.absolute.path == destination.absolute.path ||
          await FileSystemEntity.type(source.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const RadocPackageException(
          'Export source must be a regular input file.',
        );
      }
      final size = await source.length();
      _bound(size, limits.maxMemberBytes, 'member size');
      total += size;
      _bound(total, limits.maxTotalMemberBytes, 'total member size');
      final copy = File('${stage.path}/member-${members.length}');
      final digest = await _copyAndHash(source, copy, size, owner, name);
      members.add(
        RadocAudioMember(name: name, sizeBytes: size, sha256: digest),
      );
      staged[name] = copy;
    }
    final manifest = draft.withMembers(members)..validate();
    for (final scene in manifest.scenes) {
      await _validateAudio(staged[scene.audioMember]!, scene, owner);
      if (scene.rawAudioMember != null) {
        await _validateAudio(
          staged[scene.rawAudioMember]!,
          scene,
          owner,
          compareFrames: false,
        );
      }
    }
    final bytes = utf8.encode(jsonEncode(manifest.toJson()));
    _bound(bytes.length, limits.maxManifestBytes, 'manifest size');
    final outputPath = '${stage.path}/book.radoc';
    final output = OutputFileStream(outputPath);
    try {
      final encoder = ZipEncoder()..startEncode(output);
      encoder.add(
        ArchiveFile.bytes(RadocAudioManifest.manifestMember, bytes)
          ..compression = CompressionType.none,
      );
      var encoded = 0;
      for (final member in members) {
        await owner.checkpoint();
        final stream = InputFileStream(staged[member.name]!.path);
        try {
          // STORE prevents ZipEncoder's whole-member compression buffer. Its
          // CRC and bounded streaming copy stay worker-owned, one file at a time.
          encoder.add(
            ArchiveFile.stream(member.name, stream)
              ..compression = CompressionType.none,
          );
        } finally {
          await stream.close();
        }
        _bound(output.length, limits.maxArchiveBytes, 'archive size');
        await owner.progress(
          'encode',
          ++encoded,
          members.length,
          unit: 'members',
        );
      }
      encoder.endEncode();
    } finally {
      await output.close();
    }
    // OutputFileStream flushes its Dart buffer; explicitly fsync before admission.
    await owner.progress('flush', 0, null, unit: 'operations');
    final flushed = await File(outputPath).open(mode: FileMode.append);
    try {
      await flushed.flush();
    } finally {
      await flushed.close();
    }
    _bound(
      await File(outputPath).length(),
      limits.maxArchiveBytes,
      'archive size',
    );
    await _preflight(File(outputPath), limits, owner: owner);
    await owner.progress('publication', 0, null, unit: 'operations');
    await owner.admit();
    File(outputPath).renameSync(destination.path);
    return manifest;
  } finally {
    await stage.delete(recursive: true);
  }
}

Future<String> _copyAndHash(
  File source,
  File target,
  int expectedSize,
  _Worker owner,
  String memberName,
) async {
  final input = await source.open();
  final output = await target.open(mode: FileMode.write);
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  var count = 0;
  var reported = 0;
  try {
    await owner.progress('copy', 0, expectedSize, member: memberName);
    while (true) {
      await owner.checkpoint();
      final bytes = await input.read(65536);
      if (bytes.isEmpty) break;
      count += bytes.length;
      _bound(count, expectedSize, 'changed source size');
      hash.add(bytes);
      await output.writeFrom(bytes);
      if (count - reported >= 1024 * 1024 || count == expectedSize) {
        await owner.progress('copy', count, expectedSize, member: memberName);
        reported = count;
      }
    }
    if (count != expectedSize) {
      throw const RadocPackageException('Source changed during export.');
    }
    hash.close();
    await output.flush();
    return digest.value.toString();
  } finally {
    await input.close();
    await output.close();
  }
}

class _Index {
  const _Index(this.input, this.headers, this.manifest, this.digest);
  final InputFileStream input;
  final Map<String, ZipFileHeader> headers;
  final RadocAudioManifest manifest;
  final String digest;
}

Future<_Index> _openIndex(String path, _Worker owner) async {
  final limits = owner.work.limits;
  await owner.checkpoint();
  final count = await _preflight(File(path), limits, owner: owner);
  final input = InputFileStream(path);
  try {
    // ZipDirectory keeps duplicates, unlike ZipDecoder which silently coalesces
    // them and eagerly decompresses symlinks before callers can reject them.
    final directory = ZipDirectory()..read(input);
    if (directory.fileHeaders.length != count) {
      throw const RadocPackageException('Incomplete ZIP central directory.');
    }
    final headers = <String, ZipFileHeader>{};
    var total = 0;
    for (final header in directory.fileHeaders) {
      final name = header.filename;
      final local = header.file;
      final mode = (header.externalFileAttributes >> 16) & 0xf000;
      if (!isRadocMemberName(name) ||
          headers.containsKey(name) ||
          mode != 0 && mode != 0x8000 ||
          (header.externalFileAttributes & 0x10) != 0 ||
          header.diskNumberStart != 0 ||
          (header.generalPurposeBitFlag & 1) != 0 ||
          local == null ||
          local.filename != name ||
          (local.flags & 1) != 0 ||
          header.compressionMethod != 0 && header.compressionMethod != 8 ||
          local.compressionMethod !=
              (header.compressionMethod == 8
                  ? CompressionType.deflate
                  : CompressionType.none) ||
          local.uncompressedSize != header.uncompressedSize ||
          local.compressedSize != header.compressedSize ||
          local.crc32 != header.crc32) {
        throw RadocPackageException('Unsafe/duplicate ZIP member: $name');
      }
      _bound(
        header.uncompressedSize,
        name == RadocAudioManifest.manifestMember
            ? limits.maxManifestBytes
            : limits.maxMemberBytes,
        'member size',
      );
      _bound(
        header.compressedSize,
        limits.maxArchiveBytes,
        'compressed member size',
      );
      total += header.uncompressedSize;
      _bound(total, limits.maxTotalMemberBytes, 'total member size');
      headers[name] = header;
    }
    final manifestHeader = headers[RadocAudioManifest.manifestMember];
    if (manifestHeader == null) {
      throw const RadocPackageException('Missing audio-book manifest.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in _verifiedBytes(manifestHeader, owner)) {
      bytes.add(chunk);
    }
    final encoded = bytes.takeBytes();
    final manifest = RadocAudioManifest.fromJson(
      jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>,
    );
    final refs = manifest.referencedMembers;
    _bound(
      manifest.members.length + 1,
      limits.maxMembers,
      'indexed member count',
    );
    // Extra ZIP members are refused. Referenced missing members remain explicit
    // demand-time errors, allowing intact earlier coverage to open and play.
    if (headers.keys.any(
      (name) =>
          name != RadocAudioManifest.manifestMember && !refs.contains(name),
    )) {
      throw const RadocPackageException('Unreferenced ZIP member.');
    }
    var indexedTotal = 0;
    for (final member in manifest.members) {
      _bound(member.sizeBytes, limits.maxMemberBytes, 'indexed member size');
      indexedTotal += member.sizeBytes;
      _bound(indexedTotal, limits.maxTotalMemberBytes, 'indexed total size');
      final header = headers[member.name];
      if (header != null && header.uncompressedSize != member.sizeBytes) {
        throw RadocPackageException('Indexed size mismatch: ${member.name}');
      }
    }
    await owner.checkpoint();
    return _Index(input, headers, manifest, sha256.convert(encoded).toString());
  } catch (_) {
    await input.close();
    rethrow;
  }
}

/// Preflight only the fixed EOCD fields before archive allocates directory
/// metadata. ZIP parsing/encoding itself remains archive's responsibility.
/// Classic ZIP is deliberate: unsupported ZIP64 never bypasses these limits.
Future<int> _preflight(
  File file,
  RadocPackageLimits limits, {
  _Worker? owner,
}) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const RadocPackageException('Package must be a regular file.');
  }
  final size = await file.length();
  _bound(size, limits.maxArchiveBytes, 'archive size');
  if (size < 22) throw const RadocPackageException('Truncated ZIP.');
  final handle = await file.open();
  try {
    final length = math.min(size, 65557);
    await handle.setPosition(size - length);
    final tail = await handle.read(length);
    final data = ByteData.sublistView(tail);
    var offset = -1;
    for (var at = tail.length - 22; at >= 0; at--) {
      if (data.getUint32(at, Endian.little) == 0x06054b50 &&
          at + 22 + data.getUint16(at + 20, Endian.little) == tail.length) {
        offset = at;
        break;
      }
    }
    if (offset < 0) throw const RadocPackageException('Missing ZIP directory.');
    final count = data.getUint16(offset + 10, Endian.little);
    final directorySize = data.getUint32(offset + 12, Endian.little);
    final directoryOffset = data.getUint32(offset + 16, Endian.little);
    final absolute = size - length + offset;
    if (data.getUint16(offset + 4, Endian.little) != 0 ||
        data.getUint16(offset + 6, Endian.little) != 0 ||
        data.getUint16(offset + 8, Endian.little) != count ||
        count == 0xffff ||
        directorySize == 0xffffffff ||
        directoryOffset == 0xffffffff ||
        offset >= 20 &&
            data.getUint32(offset - 20, Endian.little) == 0x07064b50 ||
        directoryOffset + directorySize != absolute) {
      throw const RadocPackageException(
        'Unsupported multi-volume/ZIP64/directory layout.',
      );
    }
    _bound(count, limits.maxMembers, 'member count');
    _bound(directorySize, limits.maxDirectoryBytes, 'directory size');
    // Guard the actual metadata walk too: a forged small EOCD count must not
    // let ZipDirectory allocate an unbounded number of headers first.
    var position = directoryOffset;
    var actual = 0;
    while (position < absolute) {
      if (actual % 64 == 0) await owner?.checkpoint();
      if (++actual > count || position + 46 > absolute) {
        throw const RadocPackageException('Invalid ZIP directory entry count.');
      }
      await handle.setPosition(position);
      final fixed = await handle.read(46);
      if (fixed.length != 46) {
        throw const RadocPackageException('Truncated ZIP directory.');
      }
      final fields = ByteData.sublistView(fixed);
      if (fields.getUint32(0, Endian.little) != 0x02014b50) {
        throw const RadocPackageException('Invalid ZIP directory header.');
      }
      final localOffset = fields.getUint32(42, Endian.little);
      final compressedSize = fields.getUint32(20, Endian.little);
      if (localOffset + 30 + compressedSize > directoryOffset) {
        throw const RadocPackageException(
          'ZIP member lies outside data region.',
        );
      }
      position +=
          46 +
          fields.getUint16(28, Endian.little) +
          fields.getUint16(30, Endian.little) +
          fields.getUint16(32, Endian.little);
      if (actual % 64 == 0 || actual == count) {
        await owner?.progress('directory', actual, count, unit: 'members');
      }
    }
    if (actual != count || position != absolute) {
      throw const RadocPackageException('Invalid ZIP directory bounds.');
    }
    return count;
  } finally {
    await handle.close();
  }
}

Stream<List<int>> _verifiedBytes(ZipFileHeader header, _Worker owner) async* {
  final raw = header.file!.getStream(decompress: false);
  Stream<List<int>> compressed() async* {
    while (!raw.isEOS) {
      await owner.checkpoint();
      yield raw.readBytes(math.min(8192, raw.length)).toUint8List();
    }
  }

  final stream = header.compressionMethod == 8
      ? compressed().transform(io.ZLibDecoder(raw: true))
      : compressed();
  var crc = 0;
  var count = 0;
  var reported = 0;
  await owner.progress(
    'read',
    0,
    header.uncompressedSize,
    member: header.filename,
  );
  await for (final bytes in stream) {
    owner.check();
    count += bytes.length;
    _bound(count, header.uncompressedSize, 'emitted member size');
    crc = getCrc32(bytes, crc);
    yield bytes;
    if (count - reported >= 1024 * 1024 || count == header.uncompressedSize) {
      await owner.progress(
        'read',
        count,
        header.uncompressedSize,
        member: header.filename,
      );
      reported = count;
    }
  }
  if (count != header.uncompressedSize || crc != header.crc32) {
    throw RadocPackageException(
      'ZIP member integrity failed: ${header.filename}',
    );
  }
}

Future<String> _materialize(_Worker owner) async {
  final book = owner.work.payload['book'] as RadocAudioBook;
  final name = owner.work.payload['member'] as String;
  final index = await _openIndex(book.packagePath, owner);
  Directory? stage;
  try {
    if (index.digest != book.manifestDigest) {
      throw const RadocPackageException('Package manifest changed after open.');
    }
    final descriptor = index.manifest.members.firstWhere((m) => m.name == name);
    final header = index.headers[name];
    if (header == null) {
      throw RadocPackageException('Missing package member: $name');
    }
    stage = await Directory(book._cachePath).createTemp('pending-');
    final target = File('${stage.path}/member');
    final output = await target.open(mode: FileMode.write);
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    try {
      await for (final bytes in _verifiedBytes(header, owner)) {
        hash.add(bytes);
        await output.writeFrom(bytes);
      }
      hash.close();
      if (digest.value.toString() != descriptor.sha256) {
        throw RadocPackageException('SHA-256 mismatch: $name');
      }
      await output.flush();
    } finally {
      await output.close();
    }
    for (final scene in index.manifest.scenes.where(
      (s) => s.audioMember == name || s.rawAudioMember == name,
    )) {
      await _validateAudio(
        target,
        scene,
        owner,
        compareFrames: scene.audioMember == name,
      );
    }
    final audio = index.manifest.scenes.any(
      (scene) => scene.audioMember == name || scene.rawAudioMember == name,
    );
    final finalPath =
        '${book._cachePath}/${descriptor.sha256}.${audio ? 'wav' : 'json'}';
    await owner.admit();
    target.renameSync(finalPath);
    return finalPath;
  } finally {
    await index.input.close();
    if (stage != null) await stage.delete(recursive: true);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Native scene WAVs use the existing canonical PCM16 layout. Read only its
/// fixed header, matching AudioArtifactStore.validateWav without loading PCM.
Future<void> _validateAudio(
  File file,
  RadocAudioScene scene,
  _Worker owner, {
  bool compareFrames = true,
}) async {
  await owner.checkpoint();
  final handle = await file.open();
  try {
    final size = await handle.length();
    final bytes = await handle.read(44);
    if (bytes.length != 44) {
      throw const RadocPackageException('Truncated scene WAV.');
    }
    final b = ByteData.sublistView(bytes);
    String tag(int offset) => ascii.decode(bytes.sublist(offset, offset + 4));
    final align = scene.channels * 2;
    if (tag(0) != 'RIFF' ||
        tag(8) != 'WAVE' ||
        tag(12) != 'fmt ' ||
        tag(36) != 'data' ||
        b.getUint32(4, Endian.little) != size - 8 ||
        b.getUint32(16, Endian.little) != 16 ||
        b.getUint16(20, Endian.little) != 1 ||
        b.getUint16(22, Endian.little) != scene.channels ||
        b.getUint32(24, Endian.little) != scene.sampleRate ||
        b.getUint32(28, Endian.little) != scene.sampleRate * align ||
        b.getUint16(32, Endian.little) != align ||
        b.getUint16(34, Endian.little) != 16 ||
        b.getUint32(40, Endian.little) != size - 44 ||
        size <= 44 ||
        (size - 44) % align != 0 ||
        compareFrames && size - 44 != scene.frameCount * align) {
      throw const RadocPackageException(
        'Scene WAV format/frame count differs from manifest.',
      );
    }
  } finally {
    await handle.close();
  }
}

void _bound(int value, int maximum, String label) {
  if (value < 0 || value > maximum) {
    throw RadocPackageException('Radoc $label exceeds limit ($maximum).');
  }
}

bool _current(bool Function()? callback) {
  try {
    return callback?.call() ?? true;
  } catch (_) {
    return false;
  }
}
