import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_model_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_onnxruntime');
  late _NativeLedger native;
  late KokoroModelRunner runner;

  setUp(() {
    native = _NativeLedger();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.handle);
    runner = KokoroModelRunner(modelPath: '/mock/model.onnx');
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<List<num>> infer() => runner.runInference(
    tokens: const [1, 2],
    voice: Float32List(256),
    speed: 1,
  );
  void expectReleased() {
    expect(native.released, unorderedEquals(native.allocated));
    expect(
      native.released.toSet().length,
      native.released.length,
      reason: 'Every acquired native value must be released exactly once.',
    );
  }

  for (final allocation in [1, 2, 3]) {
    test('allocation $allocation failure releases earlier inputs', () async {
      native.failAllocation = allocation;
      await runner.initialize();
      await expectLater(infer(), throwsA(isA<PlatformException>()));
      expect(native.runCount, 0);
      expectReleased();
    });
  }
  test('run failure releases all inputs', () async {
    native.failRun = true;
    await runner.initialize();
    await expectLater(infer(), throwsA(isA<PlatformException>()));
    expect(native.allocated.length, 3);
    expectReleased();
  });
  test('native output read failure releases inputs and every output', () async {
    native.failRead = true;
    await runner.initialize();
    await expectLater(infer(), throwsA(isA<PlatformException>()));
    expect(native.allocated.length, 5);
    expectReleased();
  });
  test('nonnumeric output decode failure releases every value', () async {
    native.audioData = ['invalid'];
    await runner.initialize();
    await expectLater(infer(), throwsA(isA<TypeError>()));
    expectReleased();
  });
  test('missing expected output releases unexpected outputs too', () async {
    native.missingAudio = true;
    await runner.initialize();
    await expectLater(infer(), throwsStateError);
    expect(native.allocated.length, 4);
    expectReleased();
  });
  test('empty output releases inputs', () async {
    native.emptyOutput = true;
    await runner.initialize();
    await expectLater(infer(), throwsStateError);
    expectReleased();
  });
  test(
    'successful repeated runs release tensors while reusing session',
    () async {
      await runner.initialize();
      await runner.initialize();
      for (var i = 0; i < 3; i++) {
        expect(await infer(), [0.25, -0.5]);
        expectReleased();
      }
      expect(native.sessionCount, 1);
      expect(native.runCount, 3);
    },
  );
  test('one release failure does not skip remaining releases', () async {
    native.failRelease = 'audio-1';
    await runner.initialize();
    await expectLater(infer(), throwsA(anything));
    expectReleased();
  });
  test(
    'dispose closes session on every host including macOS and is idempotent',
    () async {
      await runner.initialize();
      await runner.dispose();
      await runner.dispose();
      expect(native.closedSessions, ['session-1']);
      await expectLater(infer(), throwsStateError);
      await runner.initialize();
      expect(native.sessionCount, 2);
      await runner.dispose();
      expect(native.closedSessions, ['session-1', 'session-2']);
    },
  );
}

// Native handles are modeled at the real plugin channel, without allocating ORT.
class _NativeLedger {
  int? failAllocation;
  bool failRun = false;
  bool failRead = false;
  bool missingAudio = false;
  bool emptyOutput = false;
  String? failRelease;
  List<Object> audioData = [0.25, -0.5];
  int allocationCount = 0;
  int sessionCount = 0;
  int runCount = 0;
  final allocated = <String>[];
  final released = <String>[];
  final closedSessions = <String>[];

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map;
    switch (call.method) {
      case 'createSession':
        return {
          'sessionId': 'session-${++sessionCount}',
          'inputNames': ['input_ids', 'style', 'speed'],
          'outputNames': ['audio'],
        };
      case 'createOrtValue':
        allocationCount++;
        if (allocationCount == failAllocation) {
          throw PlatformException(code: 'allocation');
        }
        final id = 'input-$allocationCount';
        allocated.add(id);
        return {
          'valueId': id,
          'dataType': args['sourceType'],
          'shape': args['shape'],
        };
      case 'runInference':
        runCount++;
        if (failRun) throw PlatformException(code: 'run');
        if (emptyOutput) return <String, Object>{};
        final outputs = <String, Object>{};
        for (final name in [if (!missingAudio) 'audio', 'aux']) {
          final id = '$name-$runCount';
          allocated.add(id);
          outputs[name] = [
            id,
            'float32',
            [audioData.length],
          ];
        }
        return outputs;
      case 'getOrtValueData':
        if (failRead) throw PlatformException(code: 'read');
        return {'data': audioData};
      case 'releaseOrtValue':
        final id = args['valueId'] as String;
        released.add(id);
        if (id == failRelease) throw PlatformException(code: 'release');
        return null;
      case 'closeSession':
        closedSessions.add(args['sessionId'] as String);
        return null;
      default:
        throw StateError('Unexpected native call: ${call.method}');
    }
  }
}
