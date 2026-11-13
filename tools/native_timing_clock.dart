import 'package:flutter/services.dart';

/// Native capture and Ruby use this same host clock. Never substitute Dart's
/// Stopwatch or wall time when the native method is missing or malformed.
class NativeTimingClockSnapshot {
  const NativeTimingClockSnapshot._(this.monotonicRawNanos, this.unixMicros);

  static const clockDomain = 'CLOCK_MONOTONIC_RAW';
  final int monotonicRawNanos;
  final int unixMicros;

  static Future<NativeTimingClockSnapshot> capture() async {
    final value = await const MethodChannel(
      'read_aloud/mlx_tts_lifecycle',
    ).invokeMethod<Object?>('timingClockSnapshot');
    if (value is! Map ||
        value['clockDomain'] != clockDomain ||
        value['monotonicRawNanos'] is! int ||
        value['unixMicros'] is! int ||
        (value['monotonicRawNanos'] as int) <= 0 ||
        (value['unixMicros'] as int) <= 0) {
      throw const FormatException(
        'Invalid native CLOCK_MONOTONIC_RAW snapshot',
      );
    }
    return NativeTimingClockSnapshot._(
      value['monotonicRawNanos'] as int,
      value['unixMicros'] as int,
    );
  }

  void record(Map<String, Object?> receipt, String boundary) {
    receipt['timingClockDomain'] = clockDomain;
    receipt['${boundary}MonotonicRawNanos'] = monotonicRawNanos;
    receipt['${boundary}UnixMicros'] = unixMicros;
  }
}
