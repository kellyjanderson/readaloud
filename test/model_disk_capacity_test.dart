import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/widgets/model_disk_capacity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'capacity has truthful loading, exact totals and refresh failure',
    (tester) async {
      final pending = Completer<ModelDiskSpace>();
      var queries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: ModelDiskCapacity(
                engineId: 'fish',
                loadRequirements: () async => {'fish': 1234567890},
                querySpace: () => ++queries == 1
                    ? pending.future
                    : Future.error(StateError('disk unavailable')),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('checking…'), findsOneWidget);
      await tester.pump();
      expect(find.textContaining('1234567890 bytes'), findsOneWidget);
      pending.complete(
        ModelDiskSpace(9876543210, DateTime(2026, 11, 11, 10, 30)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('9876543210 bytes'), findsOneWidget);
      expect(
        find.textContaining('not remaining download bytes'),
        findsOneWidget,
      );
      await tester.tap(find.text('Refresh available space'));
      await tester.pumpAndSettle();
      expect(find.textContaining('unavailable. Retry'), findsOneWidget);
      expect(queries, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unknown model requirement remains explicit', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelDiskCapacity(
            engineId: 'other',
            loadRequirements: () async => {},
            querySpace: () async => ModelDiskSpace(0, DateTime(2026)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('unknown for this engine'), findsOneWidget);
    expect(find.textContaining('0 bytes'), findsOneWidget);
  });
  test(
    'native disk snapshot validates payload and does not accept user paths',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('read_aloud/mlx_tts_lifecycle');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'modelDiskSpace');
        expect(call.arguments, isNull);
        return {'availableBytes': 42, 'checkedAtUnixMicros': 1000000};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect((await ModelDiskSpace.query()).availableBytes, 42);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'availableBytes': -1},
      );
      await expectLater(ModelDiskSpace.query(), throwsFormatException);
    },
  );
}
