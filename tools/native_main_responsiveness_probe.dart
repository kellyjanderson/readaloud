import 'dart:async';

import 'package:flutter/services.dart';

/// Observes the existing native main-thread method-channel route. At most one
/// request is in flight. The timer never accumulates a pending request queue.
class NativeMainResponsivenessProbe {
  final Stopwatch _clock = Stopwatch()..start();
  final _channel = const MethodChannel('read_aloud/mlx_tts_lifecycle');
  final List<Map<String, Object?>> _delays = [];
  Timer? _timer;
  Future<void>? _pending;
  bool _closed = false;
  int _samples = 0, _maximumMs = 0;
  String? _error;

  void start(String Function() phase) {
    _timer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_closed || _pending != null) return;
      final started = _clock.elapsedMilliseconds;
      final stage = phase();
      _pending = _channel
          .invokeMethod<int>('speechWorkActivityCount')
          .then<void>(
            (owners) {
              if (_closed) return;
              if (owners == null || owners < 0 || owners > 8) {
                _error = 'Native main-thread probe returned invalid ownership.';
                return;
              }
              final elapsed = _clock.elapsedMilliseconds - started;
              _samples++;
              if (elapsed > _maximumMs) _maximumMs = elapsed;
              if (elapsed > 100) {
                if (_delays.length == 16) _delays.removeAt(0);
                _delays.add({
                  'startedMs': started,
                  'elapsedMs': elapsed,
                  'phaseAtStart': stage,
                  'phaseAtEnd': phase(),
                });
              }
            },
            onError: (Object error) {
              if (!_closed) _error = '$error';
            },
          )
          .whenComplete(() {
            _pending = null;
          });
    });
  }

  Future<Map<String, Object?>> close() async {
    _timer?.cancel();
    // One outstanding native request may finish while the UI isolate drains.
    // The native handler reads its bounded owner count and returns immediately.
    // A utility-queue footprint query would mix background scheduling/I/O into
    // this measurement and could not isolate the main-thread channel route.
    try {
      await _pending?.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      _error = 'Native main-thread probe did not drain within two seconds.';
    } finally {
      _closed = true;
    }
    return {
      'samples': _samples,
      'maxRoundTripMs': _maximumMs,
      'delayedRequests': _delays,
      'error': _error,
      'passed': _samples > 0 && _error == null && _maximumMs <= 250,
      'scope':
          'UI-isolate request through the native main-thread channel and immediate bounded owner-count response; no utility query or keyboard/mouse delivery claim. Historical footprint roundtrips are a different measurement.',
    };
  }
}
