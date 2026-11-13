import 'package:flutter/services.dart';
import 'package:read_aloud/src/models/reader_operation.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/native_speech_work_activity.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('read_aloud/mlx_tts_lifecycle');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('overlapping work releases only its own native activity', () async {
    final a = await NativeSpeechWorkActivity.begin();
    final b = await NativeSpeechWorkActivity.begin();
    final owners = calls.map((c) => (c.arguments as Map)['owner']).toList();
    expect(owners.toSet(), hasLength(2));
    await b.release();
    await a.release();
    expect(calls.map((c) => c.method), [
      'beginSpeechWork',
      'beginSpeechWork',
      'endSpeechWork',
      'endSpeechWork',
    ]);
    expect((calls[2].arguments as Map)['owner'], owners[1]);
    expect((calls[3].arguments as Map)['owner'], owners[0]);
  });

  test('repeated and concurrent release is idempotent', () async {
    final activity = await NativeSpeechWorkActivity.begin();
    await Future.wait([activity.release(), activity.release()]);
    await activity.release();
    expect(calls.where((c) => c.method == 'endSpeechWork'), hasLength(1));
  });

  test('request failure can drain its activity in finally', () async {
    final activity = await NativeSpeechWorkActivity.begin();
    try {
      throw StateError('cancelled or failed work');
    } catch (_) {
      // Caller still owns the matching activity until its operation drains.
    } finally {
      await activity.release();
    }
    expect(calls.last.method, 'endSpeechWork');
  });

  test('platform-free hosts have a no-op activity', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final activity = await NativeSpeechWorkActivity.begin();
    await activity.release();
  });

  test(
    'model preparation failure before Python releases its activity',
    () async {
      final progress = <TtsResourceProgress?>[];
      final processor = MlxSpeechWorkerChunkProcessor(
        engineId: 'invalid-test-engine',
        modelPath: '',
        pythonPath: '',
        onResourceProgress: progress.add,
      );
      await expectLater(processor.prepareModel(), throwsStateError);
      expect(calls.map((c) => c.method), ['beginSpeechWork', 'endSpeechWork']);
      expect(calls.first.arguments, calls.last.arguments);
      expect(progress.map((p) => p?.state), [
        OperationState.queued,
        OperationState.failed,
      ]);
      final failedId = progress.last!.operationId;
      await expectLater(processor.prepareModel(), throwsStateError);
      expect(progress.last!.operationId, isNot(failedId));
      expect(progress.last!.retryOf, failedId);
      expect(progress.every((p) => p != null), isTrue);
      await processor.dispose();
    },
  );
}
