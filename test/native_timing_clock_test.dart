import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tools/native_timing_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('read_aloud/mlx_tts_lifecycle');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native clock records exact integer boundaries without conversion',
    () async {
      var requests = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'timingClockSnapshot');
        requests++;
        return {
          'clockDomain': 'CLOCK_MONOTONIC_RAW',
          'monotonicRawNanos': 9234567890123456,
          'unixMicros': 1794444444123456,
        };
      });
      final snapshot = await NativeTimingClockSnapshot.capture();
      final receipt = <String, Object?>{};
      snapshot.record(receipt, 'documentLoadRequested');
      expect(requests, 1);
      expect(receipt, {
        'timingClockDomain': 'CLOCK_MONOTONIC_RAW',
        'documentLoadRequestedMonotonicRawNanos': 9234567890123456,
        'documentLoadRequestedUnixMicros': 1794444444123456,
      });
    },
  );

  for (final invalid in <Object?>[
    null,
    123,
    {'clockDomain': 'CLOCK_MONOTONIC', 'monotonicRawNanos': 1, 'unixMicros': 2},
    {
      'clockDomain': 'CLOCK_MONOTONIC_RAW',
      'monotonicRawNanos': 1.0,
      'unixMicros': 2,
    },
    {
      'clockDomain': 'CLOCK_MONOTONIC_RAW',
      'monotonicRawNanos': '1',
      'unixMicros': 2,
    },
    {
      'clockDomain': 'CLOCK_MONOTONIC_RAW',
      'monotonicRawNanos': 0,
      'unixMicros': 2,
    },
    {
      'clockDomain': 'CLOCK_MONOTONIC_RAW',
      'monotonicRawNanos': 1,
      'unixMicros': -2,
    },
    {'clockDomain': 'CLOCK_MONOTONIC_RAW', 'monotonicRawNanos': 1},
  ]) {
    test('malformed or foreign clock is refused: $invalid', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => invalid);
      await expectLater(
        NativeTimingClockSnapshot.capture(),
        throwsA(isA<FormatException>()),
      );
    });
  }

  test(
    'missing native method cannot fall back to a Dart or Unix clock',
    () async {
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        NativeTimingClockSnapshot.capture(),
        throwsA(isA<MissingPluginException>()),
      );
    },
  );
}
