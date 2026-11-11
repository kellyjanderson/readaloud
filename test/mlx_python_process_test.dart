import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:read_aloud/src/models/speech_engine_catalog.dart';
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
    // These tests assert the macOS activity's lifecycle; the helper correctly
    // disables it on Flutter's default Android test target.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
    File.write('load.pid',Process.pid.to_s)
    File.write('cache-directories.json',JSON.generate(r['modelCacheDirectories'] || []))
    loaded=true
    response={id:r['id'],ok:true,modelIdentity:'pinned-model'}
    if r['requireVerifiedModelAssets'] && r['modelPath']!='missing-verification'
      response[:modelAssetsVerified]=true
      response[:verifiedModelIdentity]='owner/checkpoint@'+'a'*40
      if r['modelPath']=='wrong-verification' || File.exist?('reject-reload')
        response[:verifiedModelIdentity]='owner/other@'+'b'*40
      end
    end
    puts JSON.generate(response)
  else
    abort 'missing model' unless loaded
    if r['text']=='block'
      File.write(r['outputPath'],'started')
      sleep 30
    elsif r['text']=='memory-limit'
      puts JSON.generate(id:'',type:'memory',footprintBytes:1000)
      sleep 30
    elsif r['text']=='held-replacement'
      File.write(r['outputPath'],'started')
      sleep 0.002 until File.exist?(r['outputPath']+'.release')
    elsif r['text']=='packets'
      puts JSON.generate(id:r['id'],type:'audioPacket',packetIndex:0)
      puts JSON.generate(id:r['id'],type:'progress',stage:'afterPacket')
    elsif r['text']=='unsolicited-packet'
      puts JSON.generate(id:r['id'],type:'audioPacket',packetIndex:0)
    elsif r['text']=='friendly-error'
      STDERR.puts 'PRIVATE_WORKER_TRACEBACK_FIXTURE'
      puts JSON.generate(id:r['id'],ok:false,error:'Selected model is unavailable. Retry after downloading it.')
      next
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

  const pinnedIdentity =
      'owner/checkpoint@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  Future<Map<String, Object?>> loadVerified(
    String path, {
    List<String> cacheDirectories = const [],
  }) => worker.loadModel(
    modelId: 'fish_drama3',
    modelPath: path,
    quantizationBits: 0,
    privateCachePath: root.path,
    requireVerifiedModelAssets: true,
    expectedVerifiedModelIdentity: pinnedIdentity,
    modelCacheDirectories: cacheDirectories,
    onProgress: (_) {},
  );

  Future<void> expectLoadedChildReaped() async {
    final pid = await File('${root.path}/cache/load.pid').readAsString();
    final status = await Process.run('/bin/kill', ['-0', pid]);
    expect(status.exitCode, isNot(0), reason: 'Rejected child must be reaped');
  }

  test(
    'verified loading requires a pinned identity before starting a child',
    () async {
      await expectLater(
        worker.loadModel(
          modelId: 'fish_drama3',
          modelPath: '',
          quantizationBits: 0,
          privateCachePath: root.path,
          requireVerifiedModelAssets: true,
          onProgress: (_) {},
        ),
        throwsArgumentError,
      );
      expect(await File('${root.path}/cache/load.pid').exists(), isFalse);
    },
  );

  test(
    'verified loading binds the exact identity returned by the child',
    () async {
      final directories = ['${root.path}/models', '${root.path}/legacy-models'];
      final response = await loadVerified(
        'verified',
        cacheDirectories: directories,
      );
      expect(response['modelAssetsVerified'], isTrue);
      expect(response['verifiedModelIdentity'], pinnedIdentity);
      expect(
        jsonDecode(
          await File(
            '${root.path}/cache/cache-directories.json',
          ).readAsString(),
        ),
        directories,
      );
    },
  );

  for (final path in ['missing-verification', 'wrong-verification']) {
    test('rejects and reaps $path before permitting retry', () async {
      await expectLater(loadVerified(path), throwsStateError);
      await expectLoadedChildReaped();
      expect((await loadVerified('verified'))['modelAssetsVerified'], isTrue);
    });
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

  test(
    'worker diagnostics remain outside the actionable error message',
    () async {
      await load();
      try {
        await synth('friendly-error');
        fail('Expected a worker failure');
      } catch (error) {
        expect('$error', contains('Selected model is unavailable'));
        expect('$error', isNot(contains('PRIVATE_WORKER_TRACEBACK_FIXTURE')));
      }
    },
  );

  test(
    'automatic reload after cancellation revalidates pinned assets',
    () async {
      final directories = ['${root.path}/models'];
      await loadVerified('verified', cacheDirectories: directories);
      await worker.reapCancelledProcess();
      await File(
        '${root.path}/cache/reject-reload',
      ).writeAsString('changed identity');
      await expectLater(synth('after-reload'), throwsStateError);
      await expectLoadedChildReaped();
      expect(
        jsonDecode(
          await File(
            '${root.path}/cache/cache-directories.json',
          ).readAsString(),
        ),
        directories,
      );
    },
  );
  test(
    'normal preparation delegates managed snapshots for verification and repair',
    () async {
      final catalog = FishDramaCatalog.fromJson(
        modelsJson: await File('assets/fish_drama_models.json').readAsString(),
        checksumsJson: await File(
          'assets/fish_drama_model_checksums.json',
        ).readAsString(),
      );
      final variant = catalog.variants['fish_drama3']!;
      final support = await getApplicationSupportDirectory();
      final cache = Directory('${support.path}/read_aloud/mlx-tts/models');
      final snapshot = Directory(
        '${cache.path}/models--${variant.repository.replaceAll('/', '--')}/snapshots/${variant.revision}',
      );
      await snapshot.create(recursive: true);
      for (final name in variant.requiredFiles) {
        await File(
          '${snapshot.path}/$name',
        ).writeAsString('tiny unverified fixture');
      }
      final trace = File('${root.path}/resource-load.json');
      final executable = File('${root.path}/python');
      await executable.writeAsString(
        r'''#!/usr/bin/ruby
require 'json'
$stdout.sync=true
STDIN.each_line do |line|
  r=JSON.parse(line)
  File.write(FIXTURE_TRACE,line)
  valid=r['requireVerifiedModelAssets']==true &&
    r['expectedVerifiedModelIdentity']==FIXTURE_PIN && r['modelPath']==''
  puts JSON.generate(id:r['id'],ok:valid,error:'Managed snapshot bypassed acquisition',
    modelIdentity:'resource-fixture',modelAssetsVerified:valid,
    verifiedModelIdentity:FIXTURE_PIN,nativeScenesQualified:false)
end
'''
            .replaceAll('FIXTURE_TRACE', jsonEncode(trace.path))
            .replaceAll('FIXTURE_PIN', jsonEncode(variant.pinnedIdentity)),
      );
      final processor = MlxSpeechWorkerChunkProcessor(
        engineId: 'fish_drama3',
        modelPath: '',
        pythonPath: executable.path,
      );
      try {
        await processor.prepareModel();
        final request = jsonDecode(await trace.readAsString()) as Map;
        expect(request['modelPath'], isEmpty);
        expect(request['requireVerifiedModelAssets'], isTrue);
        expect(request['modelCacheDirectories'], contains(cache.path));
        expect(
          processor.supportsNativeScenes,
          isFalse,
          reason: 'Verified bytes alone do not qualify native scenes',
        );
      } finally {
        await processor.dispose();
      }
    },
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
      try {
        await started.future;
        expect(
          activityCalls.where((c) => c.method == 'beginSpeechWork').length,
          activityCalls.where((c) => c.method == 'endSpeechWork').length + 1,
        );
        worker.cancelActiveRequest();
        release.complete();
        await cancelled;
        expect((await synth('recovered'))['ok'], true);
      } finally {
        // An assertion failure must not strand the callback or hide the actual
        // failure behind the test runner's pending-Future timeout.
        worker.cancelActiveRequest();
        if (!release.isCompleted) release.complete();
        await cancelled;
      }
    },
  );

  for (final lateFailure in [false, true]) {
    test(
      'cancelled handoff late ${lateFailure ? 'failure' : 'success'} cannot settle an active replacement',
      () async {
        await load();
        final started = Completer<void>();
        final release = Completer<void>();
        final drained = Completer<void>();
        final old = synthPackets((_) async {
          started.complete();
          try {
            await release.future;
            if (lateFailure) throw const FormatException('obsolete packet');
          } finally {
            drained.complete();
          }
        });
        final cancelled = expectLater(
          old,
          throwsA(isA<MlxTtsRequestCancelled>()),
        );
        Future<Map<String, Object?>>? replacement;
        var replacementSettled = false;
        try {
          await started.future;
          worker.cancelActiveRequest();
          await cancelled;
          // Keep the obsolete consumer suspended through retirement and new
          // request admission, then complete it against an active new child.
          replacement = synth('held-replacement');
          final watchedReplacement = replacement.then(
            (value) {
              replacementSettled = true;
              return value;
            },
            onError: (Object error, StackTrace stack) {
              replacementSettled = true;
              Error.throwWithStackTrace(error, stack);
            },
          );
          replacement = watchedReplacement;
          final startedFile = File('${root.path}/held-replacement');
          Future<void> waitForReplacement() async {
            while (!await startedFile.exists()) {
              await Future<void>.delayed(const Duration(milliseconds: 2));
            }
          }

          await waitForReplacement().timeout(const Duration(seconds: 5));
          expect(drained.isCompleted, false);
          release.complete();
          await drained.future;
          await Future<void>.delayed(Duration.zero);
          expect(
            replacementSettled,
            false,
            reason:
                'An obsolete packet callback cannot complete or fail the new request',
          );
          await File('${startedFile.path}.release').writeAsString('complete');
          expect((await replacement)['ok'], true);
        } finally {
          if (!release.isCompleted) release.complete();
          worker.cancelActiveRequest();
          await cancelled;
          if (replacement != null) {
            try {
              await replacement;
            } on MlxTtsRequestCancelled {
              // A failed assertion still owns and drains its active replacement.
            }
          }
        }
      },
    );
  }

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
