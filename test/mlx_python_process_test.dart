import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:read_aloud/src/models/speech_engine_catalog.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';
import 'package:read_aloud/src/services/runtime_memory_policy.dart';
import 'package:read_aloud/src/services/fish_drama_catalog_store.dart';
import 'package:read_aloud/src/services/qualified_engine_selection_service.dart';

// Real child processes with a tiny protocol stub: no MLX weights or network.
RuntimeMemorySnapshot memorySnapshot({
  RuntimeMemoryPressure pressure = RuntimeMemoryPressure.normal,
  int available = 110000000000,
}) => RuntimeMemorySnapshot(
  totalFootprintBytes: 1000000000,
  physicalMemoryBytes: 128000000000,
  availableMemoryBytes: available,
  pressure: pressure,
  complete: true,
  sampledAt: DateTime.now(),
);

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
      response[:verifiedModelIdentity]=r['expectedVerifiedModelIdentity']
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
  Future<void> load({int sizingEstimateBytes = 80000000000}) async {
    await worker.loadModel(
      modelId: 'fish_drama3',
      modelPath: '',
      quantizationBits: 0,
      privateCachePath: root.path,
      sizingEstimateBytes: sizingEstimateBytes,
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

  group(
    'quantized process scheduling candidate',
    () {
      const runtime = 'mlx-audio-0.6.3-mlx-0.32.4-complete-v3';
      const runtimeDigest =
          '1aa333dd9c99219e488d160e46efc42ee7fa20c74983c0982bed2e79f1abf7c3';
      const pin8 =
          'mlx-community/fish-audio-drama-3-8bit@fedc7cc92bab5a180709cbaae6208d10b390bb97';
      const pin4 =
          'mlx-community/fish-audio-drama-3-4bit@2b0c8028998533972e77359cce56b8bf1c5d6d4a';
      final launches = <(String, List<String>)>[];
      final childPids = <int>[];
      var rejectPolicyLaunch = false;

      Future<void> useRuntime({
        String? identity = runtime,
        String? digest = runtimeDigest,
        String? home = 'managed-home',
        bool missingExecutable = false,
      }) async {
        await worker.shutdown();
        launches.clear();
        childPids.clear();
        rejectPolicyLaunch = false;
        worker = MlxTtsPythonProcess(
          memorySampler: (_) async => sampledBytes,
          pythonPath:
              '${root.path}/${missingExecutable ? 'missing-python' : 'python'}',
          pythonHome: home,
          managedRuntimeIdentity: identity,
          managedRuntimeDigest: digest,
          helperPath: '${root.path}/worker.rb',
          privateCacheDirectory: Directory('${root.path}/cache'),
          processStarter:
              (executable, arguments, directory, environment) async {
                launches.add((executable, List.of(arguments)));
                if (rejectPolicyLaunch &&
                    executable == '/usr/sbin/taskpolicy') {
                  throw ProcessException(
                    executable,
                    arguments,
                    'policy unavailable',
                  );
                }
                final child = await Process.start(
                  executable,
                  arguments,
                  workingDirectory: directory,
                  environment: environment,
                );
                childPids.add(child.pid);
                return child;
              },
        );
      }

      Future<Map<String, Object?>> loadVariant({
        String id = 'fish_drama3_8bit',
        int bits = 8,
        String pin = pin8,
        bool verified = true,
      }) => worker.loadModel(
        modelId: id,
        modelPath: '',
        quantizationBits: bits,
        privateCachePath: root.path,
        onProgress: (_) {},
        requireVerifiedModelAssets: verified,
        expectedVerifiedModelIdentity: pin,
      );

      void expectLaunch(bool utility) {
        expect(
          launches.last.$1,
          utility ? '/usr/sbin/taskpolicy' : '${root.path}/python',
        );
        expect(launches.last.$2, <String>[
          if (utility) ...['-c', 'utility', '${root.path}/python'],
          '-u',
          '-B',
          '${root.path}/worker.rb',
        ]);
      }

      for (final variant in [
        ('fish_drama3_8bit', 8, pin8),
        ('fish_drama3_4bit', 4, pin4),
      ]) {
        test(
          'exact ${variant.$1} launches utility and keeps the owned PID',
          () async {
            await useRuntime();
            await loadVariant(
              id: variant.$1,
              bits: variant.$2,
              pin: variant.$3,
            );
            expectLaunch(true);
            expect(
              int.parse(
                await File('${root.path}/cache/load.pid').readAsString(),
              ),
              childPids.single,
              reason:
                  'taskpolicy must exec the protocol child, not own a peer PID',
            );
            expect((await synth('scheduled'))['ok'], true);
            expect(launches, hasLength(1));
            await worker.shutdown();
            await expectLoadedChildReaped();
          },
          skip: !Platform.isMacOS,
        );
      }

      for (final variant in [
        ('fish_drama3', 0, pin8, true),
        ('kokoro', 8, pin8, true),
        ('other_engine', 8, pin8, true),
        ('fish_drama3_8bit', 4, pin8, true),
        ('fish_drama3_4bit', 8, pin4, true),
        ('fish_drama3_8bit', 8, '$pin8-changed', true),
        ('fish_drama3_8bit', 8, pin4, true),
        ('fish_drama3_8bit', 8, pin8, false),
      ]) {
        test('inherits policy for unqualified model tuple $variant', () async {
          await useRuntime();
          await loadVariant(
            id: variant.$1,
            bits: variant.$2,
            pin: variant.$3,
            verified: variant.$4,
          );
          expectLaunch(false);
          expect((await synth('unqualified'))['ok'], true);
        });
      }

      for (final runtimeIdentity in [
        null,
        'unknown-runtime',
        '$runtime-changed',
      ]) {
        test('inherits policy for runtime $runtimeIdentity', () async {
          await useRuntime(identity: runtimeIdentity);
          await loadVariant();
          expectLaunch(false);
        });
      }

      for (final digest in [null, 'unreviewed-packaged-bytes']) {
        test(
          'inherits policy for an unreviewed runtime digest $digest',
          () async {
            await useRuntime(digest: digest);
            await loadVariant();
            expectLaunch(false);
          },
        );
      }

      test(
        'explicit Python override has no managed scheduling policy',
        () async {
          await useRuntime(home: null);
          await loadVariant();
          expectLaunch(false);
        },
      );

      test(
        'cancel and reload preserve exact launch policy and reap both PIDs',
        () async {
          await useRuntime();
          await loadVariant();
          final active = synth('block');
          final cancelled = expectLater(
            active,
            throwsA(isA<MlxTtsRequestCancelled>()),
          );
          while (!await File('${root.path}/block').exists()) {
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
          worker.cancelActiveRequest();
          await cancelled;
          await expectLoadedChildReaped();
          expect((await synth('reloaded'))['ok'], true);
          expect(launches, hasLength(2));
          expect(launches[0].$1, launches[1].$1);
          expect(launches[0].$2, launches[1].$2);
          expectLaunch(true);
          expect(childPids.toSet(), hasLength(2));
          await worker.shutdown();
          await expectLoadedChildReaped();
        },
        skip: !Platform.isMacOS,
      );

      test(
        'changed load policy retires child before unqualified reuse',
        () async {
          await useRuntime();
          await loadVariant();
          expectLaunch(true);
          final oldPid = childPids.single;
          await loadVariant(id: 'fish_drama3', bits: 0);
          expectLaunch(false);
          expect(launches, hasLength(2));
          expect(
            (await Process.run('/bin/kill', ['-0', '$oldPid'])).exitCode,
            isNot(0),
          );
          expect((await synth('unclamped'))['ok'], true);
        },
        skip: !Platform.isMacOS,
      );

      test(
        'policy launch failure surfaces without a default-policy retry',
        () async {
          await useRuntime();
          rejectPolicyLaunch = true;
          await expectLater(loadVariant(), throwsA(isA<ProcessException>()));
          expect(launches, hasLength(1));
          expectLaunch(true);
          expect(childPids, isEmpty);
          rejectPolicyLaunch = false;
          await loadVariant();
          expectLaunch(true);
          expect((await synth('retried'))['ok'], true);
        },
        skip: !Platform.isMacOS,
      );

      test(
        'taskpolicy exec failure retires its PID without fallback',
        () async {
          await useRuntime(missingExecutable: true);
          await expectLater(loadVariant(), throwsA(isA<StateError>()));
          expect(launches, hasLength(1));
          expect(launches.single.$1, '/usr/sbin/taskpolicy');
          expect(childPids, hasLength(1));
          expect(
            (await Process.run('/bin/kill', [
              '-0',
              '${childPids.single}',
            ])).exitCode,
            isNot(0),
          );
        },
        skip: !Platform.isMacOS,
      );
    },
    skip:
        const [
          'utility',
          'background-utility',
        ].contains(Platform.environment['READALOUD_S7_INFERENCE_POLICY'])
        ? 'Production policy assertions require the diagnostic override unset.'
        : false,
  );

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
        runtimeMemorySampler: () async => memorySnapshot(),
        engineId: 'fish_drama3',
        modelPath: '',
        pythonPath: executable.path,
      );
      try {
        await processor.prepareModel();
        final request = jsonDecode(await trace.readAsString()) as Map;
        expect(request['modelPath'], isEmpty);
        expect(request['requireVerifiedModelAssets'], isTrue);
        expect(request['sizingEstimateBytes'], variant.estimatedPeakBytes);
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
        memorySampler: (_) async => sampledBytes,
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
  Future<void> useNativeSampler(
    Future<RuntimeMemorySnapshot> Function() sampler, {
    Iterable<QualifiedModelMemoryRecord> records = const [],
  }) async {
    await worker.shutdown();
    worker = MlxTtsPythonProcess(
      pythonPath: '${root.path}/python',
      helperPath: '${root.path}/worker.rb',
      privateCacheDirectory: Directory('${root.path}/cache'),
      runtimeMemorySampler: sampler,
      deviceIdentitySampler: () async => 'fixture-mac',
      qualificationRecords: records,
    );
  }

  test(
    'actual load reapplies the exact qualified envelope over a smaller estimate',
    () async {
      var available = 90000000000;
      await useNativeSampler(
        () async => memorySnapshot(available: available),
        records: [
          QualifiedModelMemoryRecord(
            engineId: 'fish_drama3',
            checkpointIdentity: pinnedIdentity,
            envelope: QualifiedMemoryEnvelope(
              runtimeIdentity: '$fishDramaCatalogRuntime|$pinnedIdentity',
              deviceIdentity: 'fixture-mac',
              additionalPeakBytes: 90000000000,
              evidence:
                  'https://github.com/kellyjanderson/readaloud/issues/112',
            ),
          ),
        ],
      );
      final progress = <Map<String, Object?>>[];
      Future<Map<String, Object?>> attempt() => worker.loadModel(
        modelId: 'fish_drama3',
        modelPath: '',
        quantizationBits: 0,
        privateCachePath: root.path,
        onProgress: progress.add,
        sizingEstimateBytes: 40000000000,
        requireVerifiedModelAssets: true,
        expectedVerifiedModelIdentity: pinnedIdentity,
      );
      await expectLater(attempt(), throwsStateError);
      expect(await File('${root.path}/cache/load.pid').exists(), false);
      available = 110000000000;
      await attempt();
      expect(
        progress
            .where((p) => p['stage'] == 'memoryAdmission')
            .last['measuredEnvelope'],
        true,
      );
    },
  );

  test(
    'admission uses the captured descriptor sizing rather than bundled data',
    () async {
      await useNativeSampler(() async => memorySnapshot());
      await expectLater(
        load(sizingEstimateBytes: 100000000000),
        throwsStateError,
      );
      expect(await File('${root.path}/cache/load.pid').exists(), false);
      await load(sizingEstimateBytes: 40000000000);
      expect(await File('${root.path}/cache/load.pid').exists(), true);
    },
  );

  test(
    'catalog belongs to terminal session, not released document resources',
    () async {
      final reached = Completer<void>();
      final held = Completer<List<int>>();
      final catalog = FishDramaCatalogStore(
        root: Directory('${root.path}/catalog-owner'),
        bundledModelsJson: await File(
          'assets/fish_drama_models.json',
        ).readAsString(),
        bundledChecksumsJson: await File(
          'assets/fish_drama_model_checksums.json',
        ).readAsString(),
        transport: (_) {
          reached.complete();
          return held.future;
        },
      );
      await catalog.load();
      var settled = false;
      final refresh = catalog.refresh().whenComplete(() {
        settled = true;
      });
      await reached.future;
      final processor = MlxSpeechWorkerChunkProcessor(
        engineId: 'fish_drama3',
        modelPath: '',
        pythonPath: '${root.path}/python',
        catalogStore: catalog,
      );
      try {
        await processor.releaseResources();
        await Future<void>.delayed(Duration.zero);
        expect(settled, false);
        // Document replacement retains a still-open session catalog.
        expect(await catalog.load(), isNotNull);
        await processor.dispose().timeout(const Duration(seconds: 2));
        expect((await refresh).succeeded, false);
        held.complete(utf8.encode('{}'));
      } finally {
        if (!held.isCompleted) held.complete(utf8.encode('{}'));
        await processor.dispose();
        await catalog.close();
      }
    },
  );

  test(
    'insufficient whole-tree headroom rejects before spawning a model',
    () async {
      await useNativeSampler(
        () async => memorySnapshot(available: 20000000000),
      );
      await expectLater(
        load(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('headroom'),
          ),
        ),
      );
      expect(await File('${root.path}/cache/load.pid').exists(), false);
    },
  );
  test(
    'end-of-load pressure prevents validation and retires rejected child',
    () async {
      var samples = 0;
      await useNativeSampler(
        () async => memorySnapshot(
          pressure: ++samples == 2
              ? RuntimeMemoryPressure.warning
              : RuntimeMemoryPressure.normal,
        ),
      );
      await expectLater(
        load(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('pressure'),
          ),
        ),
      );
      await load();
      expect((await synth('recovered'))['ok'], true);
    },
  );
  test(
    'cancel during memory admission cannot spawn or publish a late model',
    () async {
      final held = Completer<RuntimeMemorySnapshot>();
      await useNativeSampler(() => held.future);
      final loading = load();
      final cancelled = expectLater(
        loading,
        throwsA(isA<MlxTtsRequestCancelled>()),
      );
      // beginSpeechWork is the first asynchronous step before native admission.
      while (!activityCalls.any((c) => c.method == 'beginSpeechWork')) {
        await Future<void>.delayed(Duration.zero);
      }
      worker.cancelActiveRequest();
      held.complete(memorySnapshot());
      await cancelled;
      expect(await File('${root.path}/cache/load.pid').exists(), false);
    },
  );
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
