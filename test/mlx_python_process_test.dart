import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';

// Real child processes with a tiny protocol stub: no MLX weights or network.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const activityChannel = MethodChannel('read_aloud/mlx_tts_lifecycle');
  final activityCalls = <MethodCall>[];
  late Directory root;
  late MlxTtsPythonProcess worker;
  var sampledBytes = 0;
  setUp(() async {
    activityCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(activityChannel, (call) async {
          activityCalls.add(call);
          return null;
        });
    sampledBytes = 0;
    root = await Directory.systemTemp.createTemp('mlx-process-test-');
    final helper = File('${root.path}/worker.rb');
    await helper.writeAsString(r'''
require 'json'
$stdout.sync=true
loaded=false
STDIN.each_line do |line|
  r=JSON.parse(line)
  if r['command']=='load'
    File.write(ARGV[0] || 'python-home',ENV.fetch('PYTHONHOME','unset'))
    loaded=true
    puts JSON.generate(id:r['id'],ok:true,modelIdentity:'pinned-model')
  else
    abort 'missing model' unless loaded
    if r['text']=='block'
      File.write(r['outputPath'],'started')
      sleep 30
    elsif r['text']=='memory-limit'
      puts JSON.generate(id:'',type:'memory',footprintBytes:1000)
      sleep 30
    elsif r['text']=='packets'
      puts JSON.generate(id:r['id'],type:'audioPacket',packetIndex:0)
      puts JSON.generate(id:r['id'],type:'progress',stage:'afterPacket')
    elsif r['text']=='unsolicited-packet'
      puts JSON.generate(id:r['id'],type:'audioPacket',packetIndex:0)
    elsif r['text']=='malformed'
      puts 'not json'
      next
    end
    puts JSON.generate(id:r['id'],ok:true,audioPath:r['outputPath'])
  end
end
''');
    // The wrapper accepts the Python argv contract while executing Ruby.
    final executable = File('${root.path}/python');
    await executable.writeAsString(
      '#!/bin/sh\nshift\nshift\nexec /usr/bin/ruby "\$@"\n',
    );
    await Process.run('/bin/chmod', ['+x', executable.path]);
    worker = MlxTtsPythonProcess(
      memorySampler: (_) async => sampledBytes,
      pythonPath: executable.path,
      helperPath: helper.path,
      privateCacheDirectory: Directory('${root.path}/cache'),
    );
  });
  tearDown(() async {
    await worker.shutdown();
    final began = activityCalls
        .where((c) => c.method == 'beginSpeechWork')
        .map((c) => (c.arguments as Map)['owner'])
        .toList();
    final ended = activityCalls
        .where((c) => c.method == 'endSpeechWork')
        .map((c) => (c.arguments as Map)['owner'])
        .toList();
    expect(
      ended,
      unorderedEquals(began),
      reason: 'Every owned request drains its native activity',
    );
    expect(ended.toSet(), hasLength(ended.length));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(activityChannel, null);
    await root.delete(recursive: true);
  });
  Future<void> load() async {
    await worker.loadModel(
      modelId: 'fish_drama3',
      modelPath: '',
      quantizationBits: 0,
      privateCachePath: root.path,
      onProgress: (_) {},
    );
  }

  Future<Map<String, Object?>> synth(String text) => worker.synthesize(
    requestId: text,
    modelId: 'fish_drama3',
    sessionId: 's',
    generationId: 'g',
    chunkId: text,
    bindingFingerprint: 'b',
    bindingRevision: 1,
    text: text,
    voice: 'library_ava',
    language: 'English',
    outputPath: '${root.path}/$text',
  );
  Future<Map<String, Object?>> synthPackets(
    Future<void> Function(Map<String, Object?>) callback, {
    void Function(Map<String, Object?>)? progress,
  }) => worker.synthesize(
    requestId: 'packets',
    modelId: 'fish_drama3',
    sessionId: 's',
    generationId: 'g',
    chunkId: 'packets',
    bindingFingerprint: 'b',
    bindingRevision: 1,
    text: 'packets',
    voice: 'library_ava',
    language: 'English',
    outputPath: '${root.path}/packets',
    enableAudioPackets: true,
    onAudioPacket: callback,
    onProgress: progress,
  );

  test(
    'stdout waits only for bounded packet validation/handoff before terminal',
    () async {
      await load();
      final started = Completer<void>();
      final release = Completer<void>();
      var afterPacket = false;
      var completed = false;
      final result =
          synthPackets((packet) async {
            expect(packet['packetIndex'], 0);
            started.complete();
            await release.future;
          }, progress: (_) => afterPacket = true).then((value) {
            completed = true;
            return value;
          });
      await started.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(completed, false);
      expect(afterPacket, false);
      release.complete();
      expect((await result)['ok'], true);
      expect(afterPacket, true);
    },
  );

  test(
    'packet handoff failure poisons child and drains before reuse',
    () async {
      await load();
      await expectLater(
        synthPackets(
          (_) async => throw const FormatException('invalid packet'),
        ),
        throwsFormatException,
      );
      expect((await synth('recovered'))['ok'], true);
    },
  );

  test(
    'unsolicited packet cannot become successful terminal response',
    () async {
      await load();
      await expectLater(synth('unsolicited-packet'), throwsStateError);
      expect((await synth('recovered'))['ok'], true);
    },
  );

  test(
    'cancel while handoff drains cannot settle replacement request',
    () async {
      await load();
      final started = Completer<void>();
      final release = Completer<void>();
      final request = synthPackets((_) async {
        started.complete();
        await release.future;
      });
      final cancelled = expectLater(
        request,
        throwsA(isA<MlxTtsRequestCancelled>()),
      );
      await started.future;
      expect(
        activityCalls.where((c) => c.method == 'beginSpeechWork').length,
        activityCalls.where((c) => c.method == 'endSpeechWork').length + 1,
      );
      worker.cancelActiveRequest();
      release.complete();
      await cancelled;
      expect((await synth('recovered'))['ok'], true);
    },
  );

  test(
    'cancel reaps child and reloads exact model for next generation',
    () async {
      await load();
      final active = synth('block');
      final cancelled = expectLater(
        active,
        throwsA(isA<MlxTtsRequestCancelled>()),
      );
      while (!await File('${root.path}/block').exists()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      worker.cancelActiveRequest();
      await cancelled.timeout(const Duration(seconds: 8));
      expect((await synth('next'))['ok'], true);
    },
  );
  test('malformed response retires child before reuse', () async {
    await load();
    await expectLater(synth('malformed'), throwsStateError);
    expect((await synth('recovered'))['ok'], true);
  });
  test(
    'packaged home is scoped to its child; explicit override has no inferred home',
    () async {
      final inherited = Platform.environment['PYTHONHOME'];
      await load();
      expect(
        await File('${root.path}/cache/python-home').readAsString(),
        inherited ?? 'unset',
      );
      await worker.shutdown();
      worker = MlxTtsPythonProcess(
        pythonPath: '${root.path}/python',
        pythonHome: '${root.path}/verified-mlx-home',
        helperPath: '${root.path}/worker.rb',
        privateCacheDirectory: Directory('${root.path}/other-cache'),
      );
      await load();
      expect(
        await File('${root.path}/other-cache/python-home').readAsString(),
        '${root.path}/verified-mlx-home',
      );
      expect(Platform.environment['PYTHONHOME'], inherited);
    },
  );
  test('child memory telemetry retires an over-budget runtime', () async {
    await load();
    sampledBytes = 99000000000;
    await expectLater(
      synth('memory-limit'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('100 GB memory ceiling'),
        ),
      ),
    ).timeout(const Duration(seconds: 8));
    sampledBytes = 0;
    expect((await synth('recovered'))['ok'], true);
  });
  test(
    'admission is reserved before process start and shutdown joins it',
    () async {
      final loading = load();
      final stopped = expectLater(
        loading,
        throwsA(anyOf(isA<MlxTtsRequestCancelled>(), isA<StateError>())),
      );
      await expectLater(load(), throwsStateError);
      await Future.wait([worker.shutdown(), worker.shutdown()]);
      await stopped;
      await expectLater(synth('late'), throwsStateError);
    },
  );
}
