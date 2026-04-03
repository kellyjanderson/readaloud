import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class PlaybackMetricRecord {
  const PlaybackMetricRecord({
    required this.metric,
    required this.documentId,
    required this.sessionId,
    required this.voiceId,
    required this.engineId,
    required this.recordedAt,
    this.chunkId,
    this.value,
  });

  final String metric;
  final String documentId;
  final String sessionId;
  final String voiceId;
  final String engineId;
  final DateTime recordedAt;
  final String? chunkId;
  final Object? value;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'metric': metric,
      'documentId': documentId,
      'sessionId': sessionId,
      'voiceId': voiceId,
      'engineId': engineId,
      'recordedAt': recordedAt.toUtc().toIso8601String(),
      'chunkId': chunkId,
      'value': value,
    };
  }
}

class PlaybackInstrumentationService {
  PlaybackInstrumentationService._();

  static final PlaybackInstrumentationService instance =
      PlaybackInstrumentationService._();

  final ListQueue<PlaybackMetricRecord> _recent = ListQueue<PlaybackMetricRecord>();

  void recordMetric({
    required String metric,
    required String documentId,
    required String sessionId,
    required String voiceId,
    required String engineId,
    String? chunkId,
    Object? value,
  }) {
    record(
      PlaybackMetricRecord(
        metric: metric,
        documentId: documentId,
        sessionId: sessionId,
        voiceId: voiceId,
        engineId: engineId,
        recordedAt: DateTime.now(),
        chunkId: chunkId,
        value: value,
      ),
    );
  }

  void record(PlaybackMetricRecord record) {
    if (!kDebugMode) {
      return;
    }

    _recent.addLast(record);
    while (_recent.length > 500) {
      _recent.removeFirst();
    }
    developer.log(
      jsonEncode(record.toMap()),
      name: 'read_aloud.playback_metrics',
    );
  }

  List<PlaybackMetricRecord> snapshot() {
    return _recent.toList(growable: false);
  }

  void clear() {
    _recent.clear();
  }
}
