import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Single resident child, one admitted exchange, no hidden queue. The supervisor
/// owns latest-window demand; cancellation invalidates and reaps out of band.
class ModernBookNlpProvider {
  ModernBookNlpProvider({
    required this.pythonPath,
    required this.helperPath,
    required this.runtimePath,
    this.pythonHome,
    this.timeout = const Duration(minutes: 2),
  });
  final String pythonPath, helperPath, runtimePath;
  final String? pythonHome;
  final Duration timeout;
  Process? _child;
  bool _busy = false, _closed = false;
  int _epoch = 0, _sequence = 0;
  Completer<void>? _done;
  Completer<Map<String, dynamic>>? _reply;
  String? _requestId;
  void Function(Map<String, dynamic>)? _progress;
  Future<void>? _retiring;
  StreamSubscription<List<int>>? _out, _err;
  String _stderr = '';
  int? get processId => _child?.pid;

  Future<void> prepare({
    bool offline = false,
    void Function(Map<String, dynamic>)? onProgress,
  }) async {
    await _exchange({
      'schema': 1,
      'command': 'prepare',
      'requestId': 'prepare-${++_sequence}',
      'offline': offline,
    }, onProgress);
  }

  Future<Map<String, dynamic>> analyze(
    ModernBookNlpRequest request, {
    void Function(Map<String, dynamic>)? onProgress,
  }) async {
    final response = await _exchange({
      ...request.toJson(),
      'command': 'analyze',
    }, onProgress);
    for (final key in [
      'requestId',
      'ownerId',
      'workId',
      'sourceRevision',
      'analysisRevision',
      'sequence',
    ]) {
      if (response[key] != request.toJson()[key]) {
        await cancel();
        throw FormatException('Stale provider $key');
      }
    }
    validateModernBookNlpResult(response, request.text);
    return response;
  }

  Future<Map<String, dynamic>> _exchange(
    Map<String, Object> request,
    void Function(Map<String, dynamic>)? onProgress,
  ) async {
    if (_closed || _busy) throw StateError('Provider closed or already active');
    _busy = true;
    final done = _done = Completer<void>();
    final epoch = _epoch;
    try {
      await _retiring;
      if (_closed || epoch != _epoch) throw const ModernBookNlpCancelled();
      if (_child == null) await _start();
      if (_closed || epoch != _epoch) throw const ModernBookNlpCancelled();
      final reply = _reply = Completer<Map<String, dynamic>>();
      _requestId = request['requestId'] as String;
      _progress = onProgress;
      final result = reply.future.timeout(
        request['command'] == 'prepare' ? const Duration(minutes: 30) : timeout,
      );
      unawaited(
        result.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      _child!.stdin.writeln(jsonEncode(request));
      await _child!.stdin.flush();
      final response = await result;
      if (_closed || epoch != _epoch) throw const ModernBookNlpCancelled();
      if (response['ok'] != true) {
        throw StateError('ModernBookNLP: ${response['error']}. $_stderr');
      }
      if (response['schema'] != 1 ||
          response['providerId'] != 'modernbooknlp-joint' ||
          response['providerVersion'] != modernBookNlpRevision ||
          response['modelIdentity'] != modernBookNlpModelIdentity ||
          response['adapterVersion'] != modernBookNlpAdapterVersion) {
        throw const FormatException('Unrecognized provider version');
      }
      return response;
    } catch (_) {
      await _retire();
      rethrow;
    } finally {
      _reply = null;
      _requestId = null;
      _progress = null;
      _busy = false;
      done.complete();
    }
  }

  Future<void> _start() async {
    final child = await Process.start(
      pythonPath,
      ['-u', '-B', helperPath, runtimePath, '--serve'],
      environment: {
        'PYTHONHOME': ?pythonHome,
        'TOKENIZERS_PARALLELISM': 'false',
        'OMP_NUM_THREADS': '4',
        'HF_HUB_DISABLE_XET': '1',
      },
    );
    _child = child;
    _stderr = '';
    final line = BytesBuilder(copy: false);
    void failed(Object error) {
      if (!identical(_child, child)) return;
      if (_reply?.isCompleted == false) _reply!.completeError(error);
      child.kill(ProcessSignal.sigkill);
    }

    _out = child.stdout.listen((chunk) {
      if (!identical(_child, child)) return;
      var start = 0;
      while (start < chunk.length) {
        final end = chunk.indexOf(10, start);
        final limit = end < 0 ? chunk.length : end;
        if (line.length + limit - start > 1024 * 1024) {
          failed(StateError('Provider output exceeds bound'));
          return;
        }
        line.add(chunk.sublist(start, limit));
        if (end < 0) break;
        start = end + 1;
        try {
          final message = Map<String, dynamic>.from(
            jsonDecode(utf8.decode(line.takeBytes())) as Map,
          );
          if (message['requestId'] != _requestId) continue;
          if (message['type'] == 'progress') {
            _progress?.call(message);
          } else if (_reply?.isCompleted == false) {
            _reply!.complete(message);
          }
        } catch (error) {
          failed(error);
          return;
        }
      }
    }, onError: failed);
    _err = child.stderr.listen((bytes) {
      if (!identical(_child, child)) return;
      _stderr += utf8.decode(bytes, allowMalformed: true);
      if (_stderr.length > 4096) {
        _stderr = _stderr.substring(_stderr.length - 4096);
      }
    }, onError: failed);
    unawaited(
      child.exitCode.then((code) {
        if (!identical(_child, child)) return;
        if (_reply?.isCompleted == false) {
          _reply!.completeError(
            StateError('Provider exited ($code). $_stderr'),
          );
        }
        // Retain the dead process until subscriptions are retired by next exchange.
      }),
    );
  }

  Future<void> cancel() async {
    ++_epoch;
    if (_reply?.isCompleted == false) {
      _reply!.completeError(const ModernBookNlpCancelled());
    }
    await _retire();
  }

  Future<void> close() async {
    _closed = true;
    final done = _done;
    await cancel();
    await done?.future;
    await _retire(); // Covers cancellation while Process.start was in flight.
  }

  Future<void> _retire() =>
      _retiring ??= _reap().whenComplete(() => _retiring = null);
  Future<void> _reap() async {
    final child = _child;
    _child = null;
    if (child == null) return;
    child.kill(ProcessSignal.sigterm);
    try {
      await child.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode.timeout(const Duration(seconds: 3));
    }
    await _out?.cancel();
    await _err?.cancel();
    _out = _err = null;
  }
}

const modernBookNlpAdapterVersion = 'readaloud-cpu-2';

const modernBookNlpModelIdentity =
    'a32c85b99e6491f559e0c46c6257b18be0a39a06c15c281389ca0934c229cfb2';
const modernBookNlpRevision = '84f1f34f6f0ec7c6e9c558b4371e61ea2354d95b';

class ModernBookNlpCancelled implements Exception {
  const ModernBookNlpCancelled();
}

class ModernBookNlpRequest {
  ModernBookNlpRequest({
    required this.requestId,
    required this.ownerId,
    required this.workId,
    required this.sourceRevision,
    required this.analysisRevision,
    required this.sequence,
    required this.text,
    this.windowPolicy = 'normalized-segments-newline-v1',
  }) {
    if ([
          requestId,
          ownerId,
          workId,
          sourceRevision,
        ].any((v) => v.isEmpty || v.length > 512) ||
        analysisRevision < 0 ||
        sequence < 0 ||
        text.isEmpty ||
        text.length > 16384) {
      throw ArgumentError(
        'Invalid identity or source window (max 16384 UTF-16 units)',
      );
    }
  }
  final String requestId, ownerId, workId, sourceRevision, text;
  final String windowPolicy;
  final int analysisRevision, sequence;
  Map<String, Object> toJson() => {
    'schema': 1,
    'requestId': requestId,
    'ownerId': ownerId,
    'workId': workId,
    'sourceRevision': sourceRevision,
    'analysisRevision': analysisRevision,
    'sequence': sequence,
    'text': text,
  };
}

void validateModernBookNlpResult(Map<String, dynamic> result, String text) {
  void span(Map row) {
    final a = row['startUtf16'], b = row['endUtf16'];
    bool splitsSurrogate(int n) =>
        n > 0 &&
        n < text.length &&
        text.codeUnitAt(n) >= 0xdc00 &&
        text.codeUnitAt(n) <= 0xdfff;
    if (a is! int ||
        b is! int ||
        a < 0 ||
        b <= a ||
        b > text.length ||
        splitsSurrogate(a) ||
        splitsSurrogate(b)) {
      throw const FormatException('Invalid provider source coordinates');
    }
  }

  final artifacts = result['linguisticArtifacts'];
  if (artifacts != null) {
    if (artifacts is! Map ||
        artifacts['schema'] != 1 ||
        artifacts['pipeline'] != 'entity,quote,coref' ||
        artifacts['coordinateSystem'] != 'python-codepoint') {
      throw const FormatException('Unsupported linguistic evidence');
    }
    final files = artifacts['files'];
    const names = {'tokens', 'entities', 'quotes', 'book'};
    if (files is! Map ||
        files.length != names.length ||
        !names.every((name) => files[name] is String)) {
      throw const FormatException('Incomplete linguistic evidence');
    }
    final book = jsonDecode(files['book'] as String);
    if (book is! Map || book['characters'] is! List) {
      throw const FormatException('Invalid character summaries');
    }
  }
  final ids = <String>{};

  for (final entity in result['entities'] as List) {
    if (entity['entityId'] is! String ||
        !ids.add(entity['entityId'] as String)) {
      throw const FormatException('Invalid or duplicate entity');
    }
    for (final mention in entity['mentions'] as List) {
      span(mention as Map);
      if (text.substring(
            mention['startUtf16'] as int,
            mention['endUtf16'] as int,
          ) !=
          mention['text']) {
        throw const FormatException('Entity mention does not match source');
      }
    }
  }
  for (final quote in result['quotes'] as List) {
    span(quote as Map);
    if (quote['entityId'] != null && !ids.contains(quote['entityId'])) {
      throw const FormatException('Speaker is absent from provider entities');
    }
    // Upstream only exposes the winning entity here; never invent confidence.
    if (quote['confidence'] != null) {
      throw const FormatException('Unsupported confidence');
    }
  }
}
