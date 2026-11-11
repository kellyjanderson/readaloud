import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tools/native_main_responsiveness_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('read_aloud/mlx_tts_lifecycle');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('main probe admits one request and joins it on close', () async {
    final reply = Completer<Map<String, Object?>>();
    var requests = 0;
    messenger.setMockMethodCallHandler(channel, (call) {
      expect(call.method, 'speechWorkActivityProbe');
      requests++;
      return reply.future;
    });
    final probe = NativeMainResponsivenessProbe()..start(() => 'modelLoad');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(requests, 1);
    var closed = false;
    final closing = probe.close().then((value) {
      closed = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    reply.complete({
      'owners': 1,
      'nativeEntryUnixMicros': DateTime.now().microsecondsSinceEpoch,
      'applicationActive': true,
    });
    final receipt = await closing;
    expect(receipt['samples'], 1);
    expect(receipt['applicationActiveSamples'], 1);
    expect(receipt['error'], isNull);
    expect(receipt['passed'], isFalse);
    final delayed = (receipt['delayedRequests'] as List).single as Map;
    expect(delayed['applicationActive'], isTrue);
    expect(delayed['nativeEntryUnixMicros'], isA<int>());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(requests, 1);
  });

  test('unsupported native response cannot pass responsiveness', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final probe = NativeMainResponsivenessProbe()..start(() => 'load');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final receipt = await probe.close();
    expect(receipt['passed'], isFalse);
    expect(receipt['samples'], 0);
    expect(receipt['error'], contains('invalid ownership'));
  });
}
