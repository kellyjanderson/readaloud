import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

const _policy = 'bundled-native-data-view-v2';
const _runtimeIds = {'mlx', 'modernbooknlp'};

/// Exact packaged code and its immutable data view. Only the owning Python
/// child receives [pythonHome]; this never changes the application environment.
class VerifiedPythonRuntime {
  const VerifiedPythonRuntime({
    required this.executable,
    required this.pythonHome,
  });
  final String executable;
  final String pythonHome;
}

class PackagedRuntimeCancelled implements Exception {
  const PackagedRuntimeCancelled();
}

/// One consumer interest. Cancellation settles the consumer immediately; drain
/// waits for owned extraction/validation cleanup if this was the last interest.
class PackagedRuntimeLease {
  PackagedRuntimeLease._(this.runtime, this._release);
  final Future<VerifiedPythonRuntime> runtime;
  Future<String> get executable => runtime.then((value) => value.executable);
  final Future<void> Function() _release;
  Future<void>? _released;
  Future<void> cancelAndDrain() => _released ??= _release();
}

/// Main-isolate projection only. At most the two known runtime IDs are active;
/// no pending queue. Same-resource consumers share one attempt, each with its
/// own revision callback and independently cancellable result. Heavy filesystem,
/// manifest, ZIP and tree work belongs exclusively to the attempt isolate.
class PackagedPythonRuntimeOwner {
  static final shared = PackagedPythonRuntimeOwner();
  final Map<String, _Attempt> _active = {};
  bool _closed = false;

  PackagedRuntimeLease acquire({
    required String runtimeId,
    required Directory resources,
    required Directory support,
    required String consumerRevision,
    void Function(Map<String, dynamic>)? onProgress,
    // Test-only verifier substitute: production always checks codesign + arm64.
    bool verifyExecutable = true,
    Duration timeout = const Duration(minutes: 10),
  }) {
    if (_closed || !_runtimeIds.contains(runtimeId)) {
      throw StateError('Packaged runtime owner closed or unknown runtime.');
    }
    final key = '${resources.absolute.path}|${support.absolute.path}';
    var attempt = _active[runtimeId];
    if (attempt != null && attempt.key != key) {
      throw StateError(
        'Another immutable resource identity is installing $runtimeId. Retry after it drains.',
      );
    }
    attempt ??= _active[runtimeId] = _Attempt(key);
    final selected = attempt;
    if (selected.cancelled || selected.interests.length >= 16) {
      throw StateError(
        'Runtime installer is draining or consumer limit reached. Retry.',
      );
    }
    final result = Completer<VerifiedPythonRuntime>();
    final interest = _Interest(consumerRevision, result, onProgress);
    selected.interests.add(interest);
    // Consume errors even when the caller cancels before awaiting the result.
    unawaited(
      result.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    if (!selected.started) {
      selected.started = true;
      unawaited(
        _start(
          selected,
          runtimeId,
          resources,
          support,
          verifyExecutable,
          timeout,
        ),
      );
    } else if (selected.progress != null) {
      scheduleMicrotask(() {
        if (selected.interests.contains(interest)) {
          _project(selected, interest);
        }
      });
    }
    return PackagedRuntimeLease._(result.future, () async {
      selected.interests.remove(interest);
      if (!result.isCompleted) {
        result.completeError(const PackagedRuntimeCancelled());
      }
      if (selected.interests.isEmpty) {
        selected.cancel();
        await selected.drained.future;
      }
    });
  }

  void _project(_Attempt attempt, _Interest interest) {
    if (!attempt.interests.contains(interest) || interest.result.isCompleted) {
      return;
    }
    try {
      interest.onProgress?.call({
        ...attempt.progress!,
        'consumerRevision': interest.revision,
      });
    } catch (error, stack) {
      // An observer failure must not kill an isolate with an owned extractor.
      attempt.interests.remove(interest);
      interest.result.completeError(error, stack);
      if (attempt.interests.isEmpty) attempt.cancel();
    }
  }

  Future<void> _start(
    _Attempt attempt,
    String id,
    Directory resources,
    Directory support,
    bool verifyExecutable,
    Duration timeout,
  ) async {
    final events = ReceivePort();
    Isolate? isolate;
    final timer = Timer(
      timeout,
      () => attempt.cancel(
        'Runtime installation exceeded its ${timeout.inSeconds}-second deadline. Retry.',
      ),
    );
    try {
      isolate = await Isolate.spawn(
        _installRuntime,
        {
          'events': events.sendPort,
          'runtimeId': id,
          'resources': resources.path,
          'support': support.path,
          'verifyExecutable': verifyExecutable,
        },
        onError: events.sendPort,
        onExit: events.sendPort,
      );
      await for (final event in events) {
        if (event is SendPort) {
          attempt.control = event;
          if (attempt.cancelled) event.send(attempt.cancelReason);
        } else if (event is Map && event['progress'] is Map) {
          attempt.progress = Map<String, dynamic>.from(
            event['progress'] as Map,
          );
          for (final interest in List<_Interest>.of(attempt.interests)) {
            _project(attempt, interest);
          }
        } else if (event is Map && event['result'] is Map) {
          for (final interest in attempt.interests) {
            if (!interest.result.isCompleted) {
              final value = event['result'] as Map;
              interest.result.complete(
                VerifiedPythonRuntime(
                  executable: value['executable'] as String,
                  pythonHome: value['pythonHome'] as String,
                ),
              );
            }
          }
          break;
        } else if (event is Map && event['error'] != null) {
          throw StateError(event['error'] as String);
        } else if (event == null || event is List) {
          throw StateError(
            'Runtime validation worker exited unexpectedly: $event',
          );
        }
      }
    } catch (error, stack) {
      for (final interest in attempt.interests) {
        if (!interest.result.isCompleted) {
          interest.result.completeError(error, stack);
        }
      }
    } finally {
      timer.cancel();
      events.close();
      // Worker sends its final result only after owned processes and staging
      // cleanup have drained. Killing here merely releases the idle isolate.
      isolate?.kill(priority: Isolate.immediate);
      if (identical(_active[id], attempt)) _active.remove(id);
      attempt.drained.complete();
    }
  }

  Future<void> shutdown() async {
    _closed = true;
    final attempts = _active.values.toList();
    for (final attempt in attempts) {
      for (final interest in attempt.interests) {
        if (!interest.result.isCompleted) {
          interest.result.completeError(const PackagedRuntimeCancelled());
        }
      }
      attempt.interests.clear();
      attempt.cancel();
    }
    await Future.wait(attempts.map((a) => a.drained.future));
  }
}

class _Interest {
  _Interest(this.revision, this.result, this.onProgress);
  final String revision;
  final Completer<VerifiedPythonRuntime> result;
  final void Function(Map<String, dynamic>)? onProgress;
}

class _Attempt {
  _Attempt(this.key);
  final String key;
  final interests = <_Interest>{};
  final drained = Completer<void>();
  SendPort? control;
  Map<String, dynamic>? progress;
  bool started = false, cancelled = false;
  String cancelReason = 'Runtime installation cancelled.';
  void cancel([String? reason]) {
    cancelled = true;
    cancelReason = reason ?? cancelReason;
    control?.send(cancelReason);
  }
}

/// Attempt-local publication policy, exposed only for deterministic timing tests.
///
/// Dart's maintained Timer/Stopwatch provide scheduling and monotonic time. The
/// application policy needs just one immutable latest value, not a stream
/// scheduler or work queue. The installer isolate owns this publisher, closes it
/// on cancellation and before terminal cleanup, and alone produces real counts.
@visibleForTesting
class RuntimeProgressPublisher {
  RuntimeProgressPublisher({
    required void Function(Map<String, dynamic>) publish,
    Duration Function()? elapsed,
  }) : _publish = publish,
       _elapsed = elapsed;

  static const _interval = Duration(milliseconds: 100);
  final void Function(Map<String, dynamic>) _publish;
  final Duration Function()? _elapsed;
  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastPublished = Duration.zero;
  String? _stage;
  String? _unit;
  int? _completed, _total;
  Timer? _timer;
  Map<String, dynamic>? _pending;
  bool _closed = false;

  Duration get _now => _elapsed?.call() ?? _clock.elapsed;

  void add(Map<String, dynamic> progress) {
    if (_closed) return;
    final value = Map<String, dynamic>.unmodifiable(progress);
    final completed = value['completed'] as int?;
    final total = value['total'] as int?;
    final boundary =
        _stage != value['stage'] ||
        _unit != value['unit'] ||
        _total != total ||
        (_completed == null) != (completed == null) ||
        (completed != null && _completed != null && completed < _completed!);
    _completed = completed;
    _total = total;
    _unit = value['unit'] as String?;
    if (boundary ||
        (completed != null &&
            completed >= 0 &&
            total != null &&
            completed == total) ||
        _now - _lastPublished >= _interval) {
      _send(value);
      return;
    }
    _pending = value;
    // The deadline follows the last publication, not the latest producer event:
    // a quiet producer's last actual count is delivered within 100 ms too.
    _timer ??= Timer(_interval - (_now - _lastPublished), () {
      _timer = null;
      final latest = _pending;
      if (!_closed && latest != null) _send(latest);
    });
  }

  void _send(Map<String, dynamic> value) {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _stage = value['stage'] as String;
    _lastPublished = _now;
    _publish(value);
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _clock.stop();
  }
}

class _Installer {
  _Installer(this.events, this.runtimeId) {
    _progress = RuntimeProgressPublisher(
      publish: (value) => events.send({'progress': value}),
    );
  }
  final String runtimeId;
  final String attemptId =
      '$pid/${DateTime.now().microsecondsSinceEpoch}/${Isolate.current.hashCode}';
  String? signedTreeDigest;
  final SendPort events;
  late final RuntimeProgressPublisher _progress;
  bool cancelled = false;
  String cancelReason = 'Runtime installation cancelled.';
  Process? child;
  void cancel(String reason) {
    cancelled = true;
    cancelReason = reason;
    _progress.close();
    child?.kill(ProcessSignal.sigkill);
  }

  void closeProgress() => _progress.close();

  void check() {
    if (cancelled) throw StateError(cancelReason);
  }

  void progress(
    String stage,
    String message, {
    int? completed,
    int? total,
    String unit = 'bytes',
  }) {
    check();
    _progress.add({
      'runtimeId': runtimeId,
      'attemptId': attemptId,
      'signedTreeDigest': signedTreeDigest,
      'stage': stage,
      'message': message,
      'completed': completed,
      'total': total,
      'unit': unit,
    });
  }

  Future<String> hash(
    File file, {
    bool archive = false,
    String? nativeLabel,
  }) async {
    // Serial pure-Dart SHA-256 was a measured installed-runtime startup cost.
    // Use macOS CommonCrypto instead of custom crypto or per-file subprocesses;
    // the manifest algorithm and exact byte coverage remain unchanged. Each
    // file owns its context/buffer, freed on success, failure or cancellation.
    final digest = Platform.isMacOS ? _PlatformSha256() : null;
    final output = _DigestSink();
    final sink = digest == null ? sha256.startChunkedConversion(output) : null;
    try {
      var completed = 0;
      final total = await file.length();
      var last = DateTime.now();
      await for (final bytes in file.openRead()) {
        check();
        if (digest != null) {
          digest.add(bytes);
        } else {
          sink!.add(bytes);
        }
        completed += bytes.length;
        if ((archive || nativeLabel != null) &&
            DateTime.now().difference(last).inMilliseconds >= 100) {
          progress(
            archive ? 'runtimeArchive' : 'runtimeNativeFile',
            archive
                ? 'Verifying packaged runtime archive'
                : 'Verifying bundled native $nativeLabel',
            completed: completed,
            total: total,
          );
          last = DateTime.now();
        }
      }
      sink?.close();
      check();
      if (archive) {
        progress(
          'runtimeArchive',
          'Packaged runtime archive verified',
          completed: completed,
          total: total,
        );
      }
      return digest?.finish() ?? output.value.toString();
    } finally {
      digest?.dispose();
    }
  }

  // Finite batches use the existing async filesystem API, rather than a custom
  // scheduler/pool. At most 16 files/contexts are live per runtime attempt (two
  // known runtimes). Future.wait drains the whole batch even after a failure;
  // no verification result, cleanup or next batch can outlive its owner.
  Future<void> verifyEntries<T>(
    List<T> entries,
    Future<void> Function(T) verify,
  ) async {
    for (var start = 0; start < entries.length; start += 16) {
      check();
      final end = start + 16 < entries.length ? start + 16 : entries.length;
      await Future.wait(
        entries.sublist(start, end).map((entry) async {
          check();
          await verify(entry);
          check();
        }),
      );
    }
    check();
  }

  Future<String> command(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    check();
    final process = child = await Process.start(executable, args);
    if (cancelled) process.kill(ProcessSignal.sigkill);
    var output = '';
    void collect(List<int> data) {
      output += utf8.decode(data, allowMalformed: true);
      if (output.length > 8192) output = output.substring(output.length - 8192);
    }

    final out = process.stdout.listen(collect);
    final err = process.stderr.listen(collect);
    final stdoutDrained = out.asFuture<void>();
    final stderrDrained = err.asFuture<void>();
    final timer = Timer(timeout, () {
      cancelled = true;
      cancelReason = 'Runtime stage timed out: $executable. Retry.';
      process.kill(ProcessSignal.sigkill);
    });
    try {
      final code = await process.exitCode;
      await stdoutDrained;
      await stderrDrained;
      check();
      if (code != 0) {
        throw StateError('Runtime command failed ($code): $executable $output');
      }
      return output.trim();
    } finally {
      timer.cancel();
      await out.cancel();
      await err.cancel();
      child = null;
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

// Public macOS CommonCrypto/CommonDigest.h ABI: CC_LONG is uint32_t and
// CC_SHA256_CTX contains count[2], hash[8], wbuf[16]. No Python, shell utility,
// helper executable or application-global environment is involved.
final class _Sha256Context extends Struct {
  @Array(2)
  external Array<Uint32> count;
  @Array(8)
  external Array<Uint32> hash;
  @Array(16)
  external Array<Uint32> wbuf;
}

class _PlatformSha256 {
  static final _lib = DynamicLibrary.open(
    '/usr/lib/system/libcommonCrypto.dylib',
  );
  static final _libc = DynamicLibrary.process();
  static final _allocate = _libc
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');
  static final _free = _libc
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  static final _initialize = _lib
      .lookupFunction<
        Int32 Function(Pointer<_Sha256Context>),
        int Function(Pointer<_Sha256Context>)
      >('CC_SHA256_Init');
  static final _update = _lib
      .lookupFunction<
        Int32 Function(Pointer<_Sha256Context>, Pointer<Void>, Uint32),
        int Function(Pointer<_Sha256Context>, Pointer<Void>, int)
      >('CC_SHA256_Update');
  static final _finish = _lib
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Pointer<_Sha256Context>),
        int Function(Pointer<Uint8>, Pointer<_Sha256Context>)
      >('CC_SHA256_Final');
  static const _bufferSize = 64 * 1024;
  late final Pointer<_Sha256Context> _context;
  late final Pointer<Uint8> _buffer;

  _PlatformSha256() {
    _context = _allocate(sizeOf<_Sha256Context>()).cast<_Sha256Context>();
    if (_context == nullptr) throw StateError('SHA-256 allocation failed.');
    _buffer = _allocate(_bufferSize).cast<Uint8>();
    if (_buffer == nullptr) {
      _free(_context.cast<Void>());
      throw StateError('SHA-256 buffer allocation failed.');
    }
    try {
      if (_initialize(_context) != 1) {
        throw StateError('SHA-256 initialization failed.');
      }
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  void add(List<int> bytes) {
    for (var offset = 0; offset < bytes.length; offset += _bufferSize) {
      final end = offset + _bufferSize < bytes.length
          ? offset + _bufferSize
          : bytes.length;
      final length = end - offset;
      _buffer.asTypedList(length).setRange(0, length, bytes, offset);
      if (_update(_context, _buffer.cast<Void>(), length) != 1) {
        throw StateError('SHA-256 update failed.');
      }
    }
  }

  String finish() {
    if (_finish(_buffer, _context) != 1) {
      throw StateError('SHA-256 finalization failed.');
    }
    return _buffer
        .asTypedList(32)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void dispose() {
    _free(_buffer.cast<Void>());
    _free(_context.cast<Void>());
  }
}

bool _safePath(String path) =>
    path.isNotEmpty &&
    !path.contains('\\') &&
    !p.posix.isAbsolute(path) &&
    path.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..') &&
    path != '.complete.json';

Future<void> _installRuntime(Map<String, Object> args) async {
  final events = args['events'] as SendPort;
  final control = ReceivePort();
  final installer = _Installer(events, args['runtimeId'] as String);
  final subscription = control.listen((message) {
    installer.cancel('$message');
  });
  events.send(control.sendPort);
  Directory? staging;
  Map<String, String>? result;
  String? failure;
  try {
    final id = args['runtimeId'] as String;
    final resources = args['resources'] as String;
    final manifestFile = File(p.join(resources, 'python-runtimes', '$id.json'));
    if (!await manifestFile.exists() ||
        await manifestFile.length() > 32 * 1024 * 1024) {
      throw StateError(
        'Missing or oversized packaged $id manifest. Install a build with $id support.',
      );
    }
    installer.progress(
      'runtimeManifest',
      'Checking packaged $id runtime identity',
    );
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final entries = (manifest['entries'] as List).cast<Map<String, dynamic>>();
    final digest = manifest['signedTreeDigest'] as String;
    installer.signedTreeDigest = digest;
    final identity = {
      for (final key in [
        'policy',
        'runtimeId',
        'python',
        'packages',
        'executable',
        'nativeRoot',
        'entries',
      ])
        key: manifest[key],
    };
    if (manifest['schema'] != 2 ||
        manifest['policy'] != _policy ||
        manifest['runtimeId'] != id ||
        manifest['nativeRoot'] != 'python-runtimes/$id-native' ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        sha256.convert(utf8.encode(jsonEncode(identity))).toString() !=
            digest ||
        entries.isEmpty ||
        entries.length > 100000) {
      throw const FormatException(
        'Invalid packaged runtime manifest identity or policy.',
      );
    }
    final byPath = <String, Map<String, dynamic>>{};
    String? previous;
    for (final entry in entries) {
      final path = entry['path'] as String;
      final type = entry['type'];
      if (!_safePath(path) ||
          (previous != null && previous.compareTo(path) >= 0) ||
          !['file', 'directory', 'link', 'bundledNative'].contains(type) ||
          entry['mode'] is! int ||
          (entry['mode'] as int) < 0 ||
          (entry['mode'] as int) > 511) {
        throw FormatException(
          'Unsafe or duplicate runtime manifest member: $path',
        );
      }
      previous = path;
      byPath[path] = entry;
      if ((type == 'file' || type == 'bundledNative') &&
          (entry['size'] is! int ||
              (entry['size'] as int) < 0 ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch('${entry['sha256']}'))) {
        throw FormatException('Invalid runtime file identity: $path');
      }
      if (type == 'bundledNative' &&
          entry['bundlePath'] != '${manifest['nativeRoot']}/$path') {
        throw FormatException('Invalid bundled native binding: $path');
      }
      if (type == 'link') {
        final target = entry['target'] as String;
        final resolved = p.posix.normalize(
          p.posix.join(p.posix.dirname(path), target),
        );
        if (target.isEmpty ||
            target.contains('\\') ||
            p.posix.isAbsolute(target) ||
            resolved == '..' ||
            resolved.startsWith('../')) {
          throw FormatException('Escaping runtime symlink: $path');
        }
      }
    }
    // No archive member may traverse a symlink parent during extraction.
    for (final path in byPath.keys) {
      var parent = p.posix.dirname(path);
      while (parent != '.') {
        if (byPath[parent]?['type'] != 'directory') {
          throw FormatException('Missing/non-directory parent: $path');
        }
        parent = p.posix.dirname(parent);
      }
    }
    final executable = manifest['executable'] as String;
    if (!_safePath(executable) ||
        byPath[executable]?['type'] != 'bundledNative' ||
        ((byPath[executable]!['mode'] as int) & 73) == 0) {
      throw const FormatException(
        'Runtime interpreter is not an executable file.',
      );
    }
    final canonicalResources = await Directory(
      resources,
    ).resolveSymbolicLinks();
    final nativeRoot = Directory(
      p.join(resources, manifest['nativeRoot'] as String),
    );
    if (await FileSystemEntity.type(nativeRoot.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError(
        'Missing or linked bundled native root. Reinstall this application.',
      );
    }
    final canonicalNative = await nativeRoot.resolveSymbolicLinks();
    if (!p.isWithin(canonicalResources, canonicalNative)) {
      throw StateError('Bundled native root escapes application resources.');
    }
    final nativeTargets = <String, String>{};
    final nativeEntries = entries
        .where((entry) => entry['type'] == 'bundledNative')
        .toList();
    final nativeInventory = <String>{};
    await for (final item in nativeRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      installer.check();
      if (await FileSystemEntity.type(item.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        nativeInventory.add(
          p
              .relative(item.path, from: nativeRoot.path)
              .split(p.separator)
              .join('/'),
        );
      }
    }
    if (nativeInventory.length != nativeEntries.length) {
      throw StateError(
        'Undeclared or missing bundled native files. Reinstall this application.',
      );
    }
    await installer.verifyEntries(nativeEntries, (entry) async {
      installer.check();
      final relative = entry['path'] as String;
      final path = p.join(resources, entry['bundlePath'] as String);
      final canonical = await File(path).resolveSymbolicLinks();
      final stat = await FileStat.stat(path);
      if (!nativeInventory.contains(relative) ||
          await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file ||
          !p.isWithin(canonicalNative, canonical) ||
          stat.mode & 4095 != entry['mode'] ||
          stat.size != entry['size'] ||
          await installer.hash(File(path), nativeLabel: relative) !=
              entry['sha256']) {
        throw StateError(
          'Bundled native content/type/mode mismatch: $relative. Reinstall this application.',
        );
      }
      // Parent links are forbidden too, even if their target remains contained.
      var ancestor = p.dirname(path);
      while (ancestor != nativeRoot.path) {
        if (await FileSystemEntity.type(ancestor, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw StateError('Linked bundled native parent: $relative');
        }
        ancestor = p.dirname(ancestor);
      }
      nativeTargets[relative] = canonical;
      installer.progress(
        'runtimeNative',
        'Verified ${nativeTargets.length} of ${nativeEntries.length} bundled $id native targets',
        completed: nativeTargets.length,
        total: nativeEntries.length,
        unit: 'entries',
      );
    });
    final bundleIdentity = sha256
        .convert(utf8.encode(canonicalResources))
        .toString();
    final parent = Directory(
      p.join(args['support'] as String, 'python-runtimes', 'v2', id),
    );
    // Reject existing links anywhere below the application-owned support root.
    final supportPath = args['support'] as String;
    for (final directory in [
      Directory(supportPath),
      Directory(p.join(supportPath, 'python-runtimes')),
      Directory(p.join(supportPath, 'python-runtimes', 'v2')),
      parent,
    ]) {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw StateError(
          'Unsafe runtime publication parent: ${directory.path}',
        );
      }
    }
    await parent.create(recursive: true);
    if (await FileSystemEntity.type(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Runtime publication parent is not a directory.');
    }
    final published = Directory(p.join(parent.path, '$digest-$bundleIdentity'));
    Future<void> verify(Directory tree, {required bool receipt}) async {
      installer.progress(
        'runtimeInventory',
        'Checking $id runtime inventory',
        unit: 'entries',
        completed: 0,
        total: entries.length,
      );
      final canonicalTree = await tree.resolveSymbolicLinks();
      final found = <String>{};
      await for (final item in tree.list(recursive: true, followLinks: false)) {
        installer.check();
        final relative = p
            .relative(item.path, from: tree.path)
            .split(p.separator)
            .join('/');
        if (relative == '.complete.json' && receipt) continue;
        if (!byPath.containsKey(relative)) {
          throw StateError('Unexpected runtime member: $relative');
        }
        found.add(relative);
      }
      if (found.length != entries.length) {
        throw StateError('Incomplete $id runtime inventory.');
      }
      final bytesTotal = entries
          .where((e) => e['type'] == 'file')
          .fold<int>(0, (n, e) => n + (e['size'] as int));
      var bytes = 0, count = 0;
      var last = DateTime.now();
      await installer.verifyEntries(entries, (entry) async {
        installer.check();
        final path = p.join(tree.path, entry['path'] as String);
        final kind = await FileSystemEntity.type(path, followLinks: false);
        if (entry['type'] == 'bundledNative') {
          if (kind != FileSystemEntityType.link ||
              await Link(path).target() != nativeTargets[entry['path']] ||
              await Link(path).resolveSymbolicLinks() !=
                  nativeTargets[entry['path']]) {
            throw StateError('Runtime native link mismatch: $path');
          }
        } else if (entry['type'] == 'link') {
          if (kind != FileSystemEntityType.link ||
              await Link(path).target() != entry['target']) {
            throw StateError('Runtime link mismatch: $path');
          }
          final resolved = await Link(path).resolveSymbolicLinks();
          // Resolve the declared logical chain, admitting only its exact final
          // native entry. A link to any other external target fails closed.
          var logical = entry['path'] as String;
          final visited = <String>{};
          while (byPath[logical]?['type'] == 'link') {
            if (!visited.add(logical)) {
              throw StateError('Cyclic runtime link: $path');
            }
            logical = p.posix.normalize(
              p.posix.join(
                p.posix.dirname(logical),
                byPath[logical]!['target'] as String,
              ),
            );
          }
          if (!p.isWithin(canonicalTree, resolved) &&
              nativeTargets[logical] != resolved) {
            throw StateError('Runtime link escapes: $path');
          }
        } else {
          final expected = entry['type'] == 'file'
              ? FileSystemEntityType.file
              : FileSystemEntityType.directory;
          final stat = await FileStat.stat(path);
          if (kind != expected || stat.mode & 4095 != entry['mode']) {
            throw StateError('Runtime type/mode mismatch: $path');
          }
          if (expected == FileSystemEntityType.file) {
            final file = File(path);
            if (await file.length() != entry['size'] ||
                await installer.hash(file) != entry['sha256']) {
              throw StateError('Runtime content mismatch: $path');
            }
            bytes += entry['size'] as int;
          }
        }
        count++;
        if (DateTime.now().difference(last).inMilliseconds >= 100 ||
            count == entries.length) {
          installer.progress(
            'runtimeTree',
            'Verified $count of ${entries.length} $id runtime entries',
            completed: bytes,
            total: bytesTotal,
          );
          last = DateTime.now();
        }
      });
      installer.progress(
        'runtimeExecutable',
        'Verifying signed arm64 $id interpreter',
      );
      if (args['verifyExecutable'] == true) {
        final path = nativeTargets[executable]!;
        // lipo is an xcrun shim and cannot run inside an App Sandbox. The
        // system file inspector requires no developer toolchain. Admit only
        // one thin arm64 executable, never a universal/non-Mach-O input.
        final architecture = await installer.command('/usr/bin/file', [
          '-b',
          path,
        ]);
        if (architecture != 'Mach-O 64-bit executable arm64') {
          throw StateError(
            'Packaged interpreter must be arm64-only: $architecture',
          );
        }
        await installer.command('/usr/bin/codesign', [
          '--verify',
          '--strict',
          path,
        ]);
      }
      if (receipt) {
        final receiptFile = File(p.join(tree.path, '.complete.json'));
        if (await receiptFile.length() > 1024 ||
            await FileSystemEntity.type(receiptFile.path, followLinks: false) !=
                FileSystemEntityType.file) {
          throw StateError('Invalid runtime completion receipt.');
        }
        final value = jsonDecode(await receiptFile.readAsString());
        if (value['policy'] != _policy ||
            value['signedTreeDigest'] != digest ||
            value['bundleIdentity'] != bundleIdentity) {
          throw StateError('Invalid runtime completion receipt.');
        }
      }
      installer.check();
    }

    final publicationType = await FileSystemEntity.type(
      published.path,
      followLinks: false,
    );
    if (publicationType != FileSystemEntityType.notFound) {
      if (publicationType != FileSystemEntityType.directory) {
        throw StateError('Invalid published runtime tree.');
      }
      await verify(published, receipt: true);
    } else {
      final archive = File(p.join(resources, 'python-runtimes', '$id.zip'));
      final archiveIdentity = manifest['archive'] as Map;
      if (await archive.length() != archiveIdentity['size'] ||
          await installer.hash(archive, archive: true) !=
              archiveIdentity['sha256']) {
        throw StateError(
          'Corrupt packaged $id archive. Reinstall this application.',
        );
      }
      installer.progress(
        'runtimeArchiveInventory',
        'Checking $id archive members',
      );
      final input = InputFileStream(archive.path);
      try {
        final decoder = ZipDecoder();
        final decoded = decoder.decodeStream(input);
        if (decoder.directory.fileHeaders.length != decoded.length) {
          throw const FormatException('Duplicate ZIP members.');
        }
        final seen = <String>{};
        for (final member in decoded) {
          var name = member.name;
          if (name.endsWith('/')) name = name.substring(0, name.length - 1);
          final entry = byPath[name];
          if (!_safePath(name) ||
              !seen.add(name) ||
              entry == null ||
              entry['type'] == 'bundledNative' ||
              (member.isSymbolicLink
                      ? 'link'
                      : member.isDirectory
                      ? 'directory'
                      : 'file') !=
                  entry['type'] ||
              (member.isSymbolicLink &&
                  member.symbolicLink != entry['target']) ||
              (member.mode & 4095) != entry['mode'] ||
              (entry['type'] == 'file' && member.size != entry['size'])) {
            throw FormatException('Unsafe/mismatched ZIP member: $name');
          }
        }
        if (seen.length != entries.length - nativeEntries.length) {
          throw const FormatException(
            'ZIP inventory differs from signed manifest.',
          );
        }
      } finally {
        await input.close();
      }
      installer.check();
      staging = await parent.createTemp('.$digest-attempt-');
      installer.progress(
        'runtimeExtract',
        'Extracting $id runtime; waiting for verified inventory',
      );
      await installer.command('/usr/bin/ditto', [
        '-x',
        '-k',
        '--norsrc',
        '--noextattr',
        archive.path,
        staging.path,
      ]);
      for (final entry in nativeEntries) {
        installer.check();
        final path = p.join(staging.path, entry['path'] as String);
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw StateError('Native entry was present in data archive: $path');
        }
        await Link(path).create(nativeTargets[entry['path']]!);
      }
      await verify(staging, receipt: false);
      installer.progress('runtimePublish', 'Publishing verified $id runtime');
      await File(p.join(staging.path, '.complete.json')).writeAsString(
        jsonEncode({
          'policy': _policy,
          'signedTreeDigest': digest,
          'bundleIdentity': bundleIdentity,
        }),
        flush: true,
      );
      installer.check();
      // mkdir+rename semantics do not replace a nonempty completed winner.
      try {
        _renameExclusive(staging.path, published.path);
        staging = null;
      } on FileSystemException {
        if (!await published.exists()) rethrow;
        await verify(published, receipt: true);
      }
    }
    installer.check();
    result = {
      'executable': nativeTargets[executable]!,
      'pythonHome': published.path,
    };
  } catch (error) {
    failure = '$error';
  } finally {
    // No delayed count may arrive during cleanup or after the result/error.
    installer.closeProgress();
    installer.child?.kill(ProcessSignal.sigkill);
    try {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    } catch (error) {
      failure = '${failure ?? 'Installation cleanup failed'}; $error';
    }
    await subscription.cancel();
    control.close();
  }
  if (failure != null) {
    events.send({'error': failure});
  } else {
    events.send({'result': result});
  }
}

// macOS atomic no-replace publication. A plain Directory.rename may overwrite
// an existing empty (corrupt) directory; readers must never observe replacement.
void _renameExclusive(String source, String destination) {
  final libc = DynamicLibrary.process();
  final allocate = libc
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');
  final free = libc
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  final rename = libc
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Uint32),
        int Function(Pointer<Uint8>, Pointer<Uint8>, int)
      >('renamex_np');
  Pointer<Uint8> string(String value) {
    final bytes = utf8.encode(value);
    final pointer = allocate(bytes.length + 1).cast<Uint8>();
    if (pointer == nullptr) {
      throw StateError('Runtime publication allocation failed.');
    }
    pointer.asTypedList(bytes.length + 1).setAll(0, [...bytes, 0]);
    return pointer;
  }

  final from = string(source);
  final to = string(destination);
  try {
    if (rename(from, to, 4) != 0) {
      throw FileSystemException(
        'Exclusive runtime publication failed',
        destination,
      );
    }
  } finally {
    free(from.cast<Void>());
    free(to.cast<Void>());
  }
}
