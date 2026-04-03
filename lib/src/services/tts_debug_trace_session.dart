import 'dart:async';
import 'dart:io';

import 'project_test_artifact_store.dart';
import 'tts_engine.dart';

class TtsDebugTraceSession {
  TtsDebugTraceSession._({
    required this.logPath,
    required this.startedAt,
    required this.voiceId,
    required this.sessionId,
  });

  static const int _maxRecentLines = 160;

  final String logPath;
  final DateTime startedAt;
  final String voiceId;
  final String? sessionId;
  final List<String> _recentLines = <String>[];
  Future<void> _writeChain = Future<void>.value();

  void Function(TtsDebugTraceSnapshot trace)? onUpdated;

  static Future<TtsDebugTraceSession> create({
    required String voiceId,
    String? sessionId,
  }) async {
    final tracesDirectory = await resolveProjectTestArtifactDirectory(
      'tts-debug-traces',
    );

    final startedAt = DateTime.now().toUtc();
    final fileName =
        '${_timestampForFileName(startedAt)}_${_sanitizeFileComponent(voiceId)}.log';
    final logPath =
        '${tracesDirectory.path}${Platform.pathSeparator}$fileName';
    final file = File(logPath);
    await file.writeAsString('', flush: true);

    final session = TtsDebugTraceSession._(
      logPath: logPath,
      startedAt: startedAt,
      voiceId: voiceId,
      sessionId: sessionId,
    );
    session.appendLines(<String>[
      '=== TTS debug trace ===',
      'startedAt: ${startedAt.toIso8601String()}',
      'voiceId: $voiceId',
      if (sessionId != null) 'sessionId: $sessionId',
    ]);
    return session;
  }

  void appendLine(String line) {
    appendLines(<String>[line]);
  }

  void appendLines(Iterable<String> lines) {
    final stampedLines = <String>[];
    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        stampedLines.add('');
        continue;
      }
      stampedLines.add('[${DateTime.now().toIso8601String()}] $line');
    }
    if (stampedLines.isEmpty) {
      return;
    }

    _recentLines.addAll(stampedLines);
    final overflow = _recentLines.length - _maxRecentLines;
    if (overflow > 0) {
      _recentLines.removeRange(0, overflow);
    }
    _notifyUpdated();

    final payload = '${stampedLines.join('\n')}\n';
    _writeChain = _writeChain.then((_) async {
      await File(logPath).writeAsString(
        payload,
        mode: FileMode.append,
        flush: true,
      );
    });
  }

  TtsDebugTraceSnapshot snapshot() {
    return TtsDebugTraceSnapshot(
      logPath: logPath,
      startedAt: startedAt,
      voiceId: voiceId,
      recentLines: List<String>.unmodifiable(_recentLines),
      sessionId: sessionId,
    );
  }

  void _notifyUpdated() {
    final callback = onUpdated;
    if (callback == null) {
      return;
    }
    callback(snapshot());
  }
}

String _sanitizeFileComponent(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return normalized.isEmpty ? 'voice' : normalized;
}

String _timestampForFileName(DateTime timestamp) {
  return timestamp
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
}
