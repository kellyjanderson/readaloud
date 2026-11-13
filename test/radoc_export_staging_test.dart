import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/radoc_export_staging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('read_aloud/document_access');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'asks native service for destination-specific replacement stage',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'createRadocExportStage');
        expect(call.arguments, {'path': '/chosen/book.radoc'});
        return '/volume/replacement/unique';
      });
      final stage = await const RadocExportStaging().createStage(
        File('/chosen/book.radoc'),
      );
      expect(stage.path, '/volume/replacement/unique');
    },
  );

  test('native errors propagate without an unsafe fallback', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'radoc_stage_failed', message: 'Denied');
    });
    await expectLater(
      const RadocExportStaging().createStage(File('/chosen/book.radoc')),
      throwsA(isA<PlatformException>()),
    );
  });

  test('missing or invalid native stage is refused', () async {
    for (final path in [null, '', 'relative-stage']) {
      messenger.setMockMethodCallHandler(channel, (_) async => path);
      await expectLater(
        const RadocExportStaging().createStage(File('/chosen/book.radoc')),
        throwsA(isA<FileSystemException>()),
      );
    }
  });
}
