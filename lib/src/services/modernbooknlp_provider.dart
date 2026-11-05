import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Experimental offline provider. No app startup, playback or voice mutation.
/// Uses platform Process ownership, not another scheduling framework. The caller
/// admits one bounded window; replacing/cancelling it kills and reaps the child.
class ModernBookNlpProvider {
  ModernBookNlpProvider({
    required this.pythonPath,
    required this.helperPath,
    required this.runtimePath,
    this.timeout = const Duration(minutes: 2),
  });
  final String pythonPath, helperPath, runtimePath;
  final Duration timeout;
  Process? _child;
  bool _busy = false, _closed = false;
  int _epoch = 0;
  Future<void>? _retiring;
  Completer<void>? _operationDone;

  Future<Map<String, dynamic>> analyze(ModernBookNlpRequest request) async {
    if (_closed || _busy) throw StateError('Provider closed or already active');
    _busy = true;
    final operationDone = _operationDone = Completer<void>();
    final epoch = _epoch;
    final output = BytesBuilder(copy: false);
    var stderr = '';
    var exceeded = false;
    StreamSubscription<List<int>>? outSubscription, errSubscription;
    Process? child;
    try {
      await _retiring;
      child = await Process.start(
        pythonPath,
        ['-u', '-B', helperPath, runtimePath],
        environment: {
          'TOKENIZERS_PARALLELISM': 'false',
          'OMP_NUM_THREADS': '4',
          'HF_HUB_OFFLINE': '1',
          'TRANSFORMERS_OFFLINE': '1',
        },
      );
      _child = child;
      if (_closed || epoch != _epoch) throw const ModernBookNlpCancelled();
      final outDone = Completer<void>(), errDone = Completer<void>();
      outSubscription = child.stdout.listen(
        (bytes) {
          if (output.length + bytes.length > 1024 * 1024) {
            exceeded = true;
            child!.kill(ProcessSignal.sigkill);
          } else {
            output.add(bytes);
          }
        },
        onDone: outDone.complete,
        onError: outDone.completeError,
      );
      errSubscription = child.stderr.listen(
        (bytes) {
          stderr += utf8.decode(bytes, allowMalformed: true);
          if (stderr.length > 4096) {
            stderr = stderr.substring(stderr.length - 4096);
          }
        },
        onDone: errDone.complete,
        onError: errDone.completeError,
      );
      child.stdin.writeln(jsonEncode(request.toJson()));
      await child.stdin.close();
      final code = await child.exitCode.timeout(timeout);
      await Future.wait([
        outDone.future,
        errDone.future,
      ]).timeout(const Duration(seconds: 3));
      if (_closed || epoch != _epoch) throw const ModernBookNlpCancelled();
      if (exceeded || code != 0) {
        throw StateError('Provider failed ($code): $stderr');
      }
      final response = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(output.takeBytes())) as Map,
      );
      if (response['ok'] != true) {
        throw StateError('ModernBookNLP: ${response['error']}');
      }
      for (final key in [
        'requestId',
        'ownerId',
        'workId',
        'sourceRevision',
        'analysisRevision',
        'sequence',
      ]) {
        if (response[key] != request.toJson()[key]) {
          throw FormatException('Stale provider $key');
        }
      }
      if (response['schema'] != 1 ||
          response['providerId'] != 'modernbooknlp-joint' ||
          response['providerVersion'] != modernBookNlpRevision ||
          response['modelIdentity'] != modernBookNlpModelIdentity ||
          response['adapterVersion'] != 'readaloud-cpu-1') {
        throw const FormatException('Unrecognized provider version');
      }
      validateModernBookNlpResult(response, request.text);
      return response;
    } finally {
      try {
        if (child != null) await _reap(child);
      } finally {
        if (identical(_child, child)) _child = null;
        await outSubscription?.cancel();
        await errSubscription?.cancel();
        _busy = false;
        operationDone.complete();
      }
    }
  }

  Future<void> cancel() async {
    ++_epoch; // Revoke publication before signalling or awaiting process exit.
    final child = _child;
    if (child != null) {
      await (_retiring ??= _reap(child).whenComplete(() => _retiring = null));
    }
  }

  Future<void> close() async {
    _closed = true;
    final done = _operationDone;
    await cancel();
    await done?.future;
  }

  Future<void> _reap(Process child) async {
    child.kill(ProcessSignal.sigterm);
    try {
      await child.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode.timeout(const Duration(seconds: 3));
    }
  }
}

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
