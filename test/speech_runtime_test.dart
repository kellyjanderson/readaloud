import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/speech_runtime.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';

void main() {
  test(
    'failed predecessor clears prior silence instead of reusing an older join',
    () async {
      final inputs = <Map<String, Object?>>[];
      final runtime = SpeechRuntime(
        engineId: 'kokoro',
        processor: _FakeSpeechWorkerChunkProcessor(),
        boundaryCorrectionExecutor: (input) async {
          inputs.add(input);
          if (input['chunkId'] == 'failed') throw StateError('boundary failed');
          return _correction(trailing: 74);
        },
      );
      await runtime.initializeRuntime();
      await runtime.activateSession(_session());
      final lastReady = runtime.events.firstWhere(
        (e) =>
            e.type == SpeechRuntimeEventType.chunkReady && e.chunkId == 'after',
      );
      await runtime.prepareChunkPlan(
        sessionId: 'session-a',
        generationId: 'generation-a',
        chunks: [
          _chunk('first'),
          _chunk('failed', initial: false),
          _chunk('after', initial: false),
        ],
      );
      await lastReady.timeout(const Duration(seconds: 3));
      expect(inputs.map((input) => input['previousTrailingSilenceMs']), [
        null,
        74,
        null,
      ]);
      await runtime.shutdownRuntime();
    },
  );
  test(
    'slow correction holds admission and passes predecessor silence in order',
    () async {
      final firstStarted = Completer<void>();
      final firstRelease = Completer<void>();
      final inputs = <Map<String, Object?>>[];
      final processor = _FakeSpeechWorkerChunkProcessor();
      final runtime = SpeechRuntime(
        engineId: 'kokoro',
        processor: processor,
        boundaryCorrectionExecutor: (input) async {
          inputs.add(input);
          if (input['chunkId'] == 'first') {
            firstStarted.complete();
            await firstRelease.future;
          }
          return _correction(trailing: 137);
        },
      );
      await runtime.initializeRuntime();
      await runtime.activateSession(_session());
      await runtime.preparePriorityChunk(
        sessionId: 'session-a',
        generationId: 'generation-a',
        chunk: _chunk('first'),
      );
      await firstStarted.future;
      var admitted = false;
      final submission = runtime
          .prepareChunkPlan(
            sessionId: 'session-a',
            generationId: 'generation-a',
            chunks: List.generate(20, (i) => _chunk('next-$i', initial: false)),
          )
          .then((_) => admitted = true);
      await Future<void>.delayed(Duration.zero);
      expect(inputs.length, 1);
      expect(processor.startedChunks, ['first']);
      expect(admitted, isFalse);
      firstRelease.complete();
      await submission;
      final allReady = runtime.events.firstWhere(
        (e) =>
            e.type == SpeechRuntimeEventType.chunkReady &&
            e.chunkId == 'next-19',
      );
      await allReady.timeout(const Duration(seconds: 3));
      expect(inputs.first['previousTrailingSilenceMs'], isNull);
      expect(
        inputs
            .skip(1)
            .every((input) => input['previousTrailingSilenceMs'] == 137),
        isTrue,
      );
      expect(processor.startedChunks, [
        'first',
        ...List.generate(20, (i) => 'next-$i'),
      ]);
      await runtime.shutdownRuntime();
    },
  );

  for (final fails in [false, true]) {
    test(
      'cancelled correction ${fails ? 'failure' : 'success'} cannot alter replacement predecessor',
      () async {
        final started = Completer<void>();
        final release = Completer<Map<String, Object?>>();
        final inputs = <Map<String, Object?>>[];
        final events = <SpeechRuntimeEvent>[];
        final runtime = SpeechRuntime(
          engineId: 'kokoro',
          processor: _FakeSpeechWorkerChunkProcessor(),
          boundaryCorrectionExecutor: (input) {
            inputs.add(input);
            if (input['chunkId'] == 'old') {
              started.complete();
              return release.future;
            }
            return Future.value(_correction(trailing: 19));
          },
        );
        runtime.events.listen(events.add);
        await runtime.initializeRuntime();
        await runtime.activateSession(_session());
        await runtime.preparePriorityChunk(
          sessionId: 'session-a',
          generationId: 'old-gen',
          chunk: _chunk('old'),
        );
        await started.future;
        await runtime.cancelGeneration('old-gen');
        await runtime.preparePriorityChunk(
          sessionId: 'session-a',
          generationId: 'new-gen',
          chunk: _chunk('new', initial: false),
        );
        final ready = runtime.events.firstWhere(
          (e) =>
              e.type == SpeechRuntimeEventType.chunkReady && e.chunkId == 'new',
        );
        if (fails) {
          release.completeError(StateError('old failure'));
        } else {
          release.complete(_correction(trailing: 999));
        }
        await ready.timeout(const Duration(seconds: 3));
        expect(inputs.last['previousTrailingSilenceMs'], isNull);
        expect(
          events.where(
            (e) =>
                e.chunkId == 'old' &&
                (e.type == SpeechRuntimeEventType.chunkReady ||
                    e.type == SpeechRuntimeEventType.chunkFailed),
          ),
          isEmpty,
        );
        await runtime.shutdownRuntime();
      },
    );
  }
  test(
    'shutdown drains held boundary correction and suppresses stale failure',
    () async {
      final started = Completer<void>();
      final correction = Completer<Map<String, Object?>>();
      final runtime = SpeechRuntime(
        engineId: 'kokoro',
        runtimeId: 'drain',
        processor: _FakeSpeechWorkerChunkProcessor(),
        boundaryCorrectionExecutor: (_) {
          started.complete();
          return correction.future;
        },
      );
      final events = <SpeechRuntimeEvent>[];
      runtime.events.listen(events.add);
      await runtime.initializeRuntime();
      await runtime.activateSession(_session());
      await runtime.preparePriorityChunk(
        sessionId: 'session-a',
        generationId: 'generation-a',
        chunk: _chunk('held'),
      );
      await started.future;
      var closed = false;
      final shutdown = runtime.shutdownRuntime().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      correction.completeError(StateError('late boundary failure'));
      await shutdown;
      expect(
        events.where(
          (e) =>
              e.type == SpeechRuntimeEventType.chunkFailed ||
              e.type == SpeechRuntimeEventType.chunkReady,
        ),
        isEmpty,
      );
    },
  );
  final originalPlatform = defaultTargetPlatform;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = originalPlatform;
  });

  group('SpeechRuntime', () {
    test(
      'cancel bypasses blocked plan admission and repeated shutdown drains',
      () async {
        final held = Completer<void>();
        final runtime = SpeechRuntime(
          engineId: 'kokoro',
          processor: _FakeSpeechWorkerChunkProcessor(blockers: {'held': held}),
        );
        await runtime.initializeRuntime();
        await runtime.activateSession(_session());
        await runtime.preparePriorityChunk(
          sessionId: 'session-a',
          generationId: 'generation-a',
          chunk: _chunk('held'),
        );
        var admitted = false;
        final admission = runtime
            .prepareChunkPlan(
              sessionId: 'session-a',
              generationId: 'generation-a',
              chunks: List.generate(20, (i) => _chunk('queued-$i')),
            )
            .then((_) => admitted = true);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(admitted, isFalse);
        await runtime
            .cancelSession('session-a')
            .timeout(const Duration(seconds: 2));
        await admission.timeout(const Duration(seconds: 2));
        var drained = false;
        final first = runtime.shutdownRuntime().then((_) => drained = true);
        final second = runtime.shutdownRuntime();
        await Future<void>.delayed(Duration.zero);
        expect(drained, isFalse);
        held.complete();
        await Future.wait([first, second]).timeout(const Duration(seconds: 2));
        expect(runtime.state, SpeechRuntimeLifecycleState.disposed);
      },
    );
    for (final leadingMs in [80, 240]) {
      test(
        'ready duration matches corrected PCM for ${leadingMs}ms opening',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'runtime-duration-',
          );
          addTearDown(() => directory.delete(recursive: true));
          final file = File('${directory.path}/chunk.wav');
          const sampleRate = 24000;
          final samples = (leadingMs + 340) * 24;
          final bytes = Uint8List(44 + samples * 2);
          final data = ByteData.sublistView(bytes);
          bytes.setRange(0, 4, ascii.encode('RIFF'));
          bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
          bytes.setRange(36, 40, ascii.encode('data'));
          data.setUint32(4, bytes.length - 8, Endian.little);
          data.setUint32(16, 16, Endian.little);
          data.setUint16(20, 1, Endian.little);
          data.setUint16(22, 1, Endian.little);
          data.setUint32(24, sampleRate, Endian.little);
          data.setUint32(28, sampleRate * 2, Endian.little);
          data.setUint16(32, 2, Endian.little);
          data.setUint16(34, 16, Endian.little);
          data.setUint32(40, samples * 2, Endian.little);
          for (var i = leadingMs * 24; i < (leadingMs + 300) * 24; i++) {
            data.setInt16(44 + i * 2, 12000, Endian.little);
          }
          await file.writeAsBytes(bytes);
          final runtime = SpeechRuntime(
            engineId: 'kokoro',
            runtimeId: 'duration-test',
            processor: _FakeSpeechWorkerChunkProcessor(audioPath: file.path),
            boundaryCorrectionExecutor: (input) async =>
                runSpeechRuntimeBoundaryCorrection(input),
          );
          addTearDown(runtime.shutdownRuntime);
          final ready = runtime.events.firstWhere(
            (e) => e.type == SpeechRuntimeEventType.chunkReady,
          );
          await runtime.initializeRuntime();
          await runtime.activateSession(_session());
          await runtime.preparePriorityChunk(
            sessionId: 'session-a',
            generationId: 'generation-a',
            chunk: _chunk('chunk-a'),
          );
          final event = await ready.timeout(const Duration(seconds: 5));
          final retained = await File(event.audioPath!).readAsBytes();
          expect(event.audioPath, isNot(file.path));
          expect(await file.readAsBytes(), bytes);
          final expectedMs = ((retained.length - 44) / 2 / sampleRate * 1000)
              .round();
          expect(event.duration, Duration(milliseconds: expectedMs));
          expect(event.payload['durationMillis'], expectedMs);
          expect(expectedMs, leadingMs > 120 ? 460 : 420);
        },
      );
    }
    test(
      'chunk payload preserves pronunciation traceability through payload roundtrip',
      () {
        final payload = SpeechRuntimeChunkPayload(
          chunkId: 'chunk-a',
          segmentIds: const <String>['segment-a'],
          cacheKey: 'cache:chunk-a',
          boundaryClass: BreakClass.sentence,
          documentId: 'document-a',
          normalizationVersion: 'normalization-v1',
          capabilityProfileId: 'kokoro:macos:v1',
          speakText: 'Hello from chunk-a',
          tokens: const <int>[1, 2, 3],
          languageTag: 'en-us',
          voiceId: 'af_bella',
          rate: 1.0,
          isInitialChunk: true,
          isResumedChunk: false,
          routeId: 'route_dialogue_jennifer',
          castId: 'cast_character_jennifer',
          dialogueSpanId: 'dlg_s_1',
          pronunciationArtifacts: const <Map<String, Object?>>[
            <String, Object?>{
              'artifactId': 'artifact-a',
              'segmentId': 'segment-a',
              'startWord': 0,
              'endWord': 1,
              'resolutionClass': 'direct_resolved',
              'translationIntent': 'normalized_spoken_text',
              'translationOutcome': 'direct',
              'representationType': 'normalized_spoken_text',
              'representationValue': 'Ellie-ot',
              'diagnosticCodes': <String>['pronunciation.resolved.lexicon'],
            },
          ],
          missingFallbackWordCount: 2,
        );

        final roundTripped = SpeechRuntimeChunkPayload.fromPayload(
          payload.toPayload(),
        );

        expect(roundTripped.pronunciationArtifacts, hasLength(1));
        expect(
          roundTripped.pronunciationArtifacts.single['translationOutcome'],
          'direct',
        );
        expect(roundTripped.routeId, 'route_dialogue_jennifer');
        expect(roundTripped.castId, 'cast_character_jennifer');
        expect(roundTripped.dialogueSpanId, 'dlg_s_1');
        expect(roundTripped.capabilityProfileId, 'kokoro:macos:v1');
        expect(roundTripped.missingFallbackWordCount, 2);
      },
    );

    test(
      'initializes with stable capabilities and emits runtimeInitialized',
      () async {
        final runtime = SpeechRuntime(
          engineId: 'kokoro',
          runtimeId: 'runtime-test',
          processor: _FakeSpeechWorkerChunkProcessor(),
        );
        final events = <SpeechRuntimeEvent>[];
        final subscription = runtime.events.listen(events.add);

        await runtime.initializeRuntime(preferredVoiceId: 'af_bella');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(runtime.state, SpeechRuntimeLifecycleState.idle);
        expect(runtime.capabilities.isEngineSupported, isTrue);
        expect(
          events.map((event) => event.type),
          contains(SpeechRuntimeEventType.runtimeInitialized),
        );
        expect(
          events
              .firstWhere(
                (event) =>
                    event.type == SpeechRuntimeEventType.runtimeInitialized,
              )
              .capabilities
              ?.nativeQueuePolicy,
          SpeechRuntimeNativeQueuePolicy.serialBackgroundAdapter,
        );

        await subscription.cancel();
        await runtime.shutdownRuntime();
      },
    );

    test(
      'emits chunkReady after worker completion and boundary correction',
      () async {
        final runtime = SpeechRuntime(
          engineId: 'kokoro',
          runtimeId: 'runtime-test',
          processor: _FakeSpeechWorkerChunkProcessor(),
          boundaryCorrectionExecutor: (input) async {
            return <String, Object?>{
              'applied': true,
              'durationMillis': 820,
              'boundaryClass': BreakClass.sentence.name,
              'leadingSilenceBeforeMs': 120,
              'leadingSilenceAfterMs': 40,
              'trailingSilenceBeforeMs': 60,
              'trailingSilenceAfterMs': 60,
              'joinSilenceBeforeMs': 120,
              'joinSilenceAfterMs': 40,
            };
          },
        );
        final events = <SpeechRuntimeEvent>[];
        final subscription = runtime.events.listen(events.add);

        await runtime.initializeRuntime();
        await runtime.activateSession(_session());
        await runtime.preparePriorityChunk(
          sessionId: 'session-a',
          generationId: 'generation-a',
          chunk: _chunk('chunk-a'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(
          events.map((event) => event.type),
          containsAllInOrder(<SpeechRuntimeEventType>[
            SpeechRuntimeEventType.sessionActivated,
            SpeechRuntimeEventType.chunkQueued,
            SpeechRuntimeEventType.chunkStageChanged,
            SpeechRuntimeEventType.chunkReady,
          ]),
        );

        final readyEvent = events.firstWhere(
          (event) => event.type == SpeechRuntimeEventType.chunkReady,
        );
        expect(readyEvent.sessionId, 'session-a');
        expect(readyEvent.generationId, 'generation-a');
        expect(readyEvent.chunkId, 'chunk-a');
        expect(readyEvent.duration, const Duration(milliseconds: 820));
        expect(readyEvent.boundaryClass, BreakClass.sentence);
        expect(
          readyEvent.leadingSilenceBefore,
          const Duration(milliseconds: 120),
        );
        expect(readyEvent.leadingSilence, const Duration(milliseconds: 40));
        expect(
          readyEvent.trailingSilenceBefore,
          const Duration(milliseconds: 60),
        );
        expect(readyEvent.isInitialChunk, isTrue);
        expect(readyEvent.isResumedChunk, isFalse);
        expect(readyEvent.boundaryCorrectionApplied, isTrue);

        await subscription.cancel();
        await runtime.shutdownRuntime();
      },
    );

    test(
      'cancelling a session suppresses stale late chunkReady events',
      () async {
        final blocker = Completer<void>();
        final runtime = SpeechRuntime(
          engineId: 'kokoro',
          runtimeId: 'runtime-test',
          processor: _FakeSpeechWorkerChunkProcessor(
            blockers: <String, Completer<void>>{'chunk-a': blocker},
          ),
          boundaryCorrectionExecutor: (input) async {
            return <String, Object?>{
              'applied': false,
              'durationMillis': 900,
              'boundaryClass': BreakClass.sentence.name,
              'leadingSilenceBeforeMs': 0,
              'leadingSilenceAfterMs': 0,
              'trailingSilenceBeforeMs': 0,
              'trailingSilenceAfterMs': 0,
              'joinSilenceBeforeMs': 0,
              'joinSilenceAfterMs': 0,
            };
          },
        );
        final events = <SpeechRuntimeEvent>[];
        final subscription = runtime.events.listen(events.add);

        await runtime.initializeRuntime();
        await runtime.activateSession(_session());
        await runtime.preparePriorityChunk(
          sessionId: 'session-a',
          generationId: 'generation-a',
          chunk: _chunk('chunk-a'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await runtime.cancelSession('session-a', reasonCode: 'cancelled');
        blocker.complete();
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(
          events.map((event) => event.type),
          contains(SpeechRuntimeEventType.sessionCancelled),
        );
        expect(
          events.map((event) => event.type),
          isNot(contains(SpeechRuntimeEventType.chunkReady)),
        );

        await subscription.cancel();
        await runtime.shutdownRuntime();
      },
    );
  });
}

SpeechRuntimeSessionDescriptor _session() {
  return const SpeechRuntimeSessionDescriptor(
    sessionId: 'session-a',
    documentId: 'document-a',
    engineId: 'kokoro',
    voiceId: 'af_bella',
    rate: 1.0,
    startSegmentId: 'segment-a',
    normalizationVersion: 'normalization-v1',
  );
}

Map<String, Object?> _correction({required int trailing}) => {
  'applied': false,
  'durationMillis': 900,
  'leadingSilenceBeforeMs': 0,
  'leadingSilenceAfterMs': 0,
  'trailingSilenceBeforeMs': trailing,
  'trailingSilenceAfterMs': trailing,
  'joinSilenceBeforeMs': 0,
  'joinSilenceAfterMs': 0,
};

SpeechRuntimeChunkPayload _chunk(String chunkId, {bool initial = true}) {
  return SpeechRuntimeChunkPayload(
    chunkId: chunkId,
    segmentIds: const <String>['segment-a'],
    cacheKey: 'cache:$chunkId',
    boundaryClass: BreakClass.sentence,
    documentId: 'document-a',
    normalizationVersion: 'normalization-v1',
    speakText: 'Hello from $chunkId',
    tokens: const <int>[1, 2, 3],
    languageTag: 'en-us',
    voiceId: 'af_bella',
    rate: 1.0,
    isInitialChunk: initial,
    isResumedChunk: false,
  );
}

class _FakeSpeechWorkerChunkProcessor implements SpeechWorkerChunkProcessor {
  _FakeSpeechWorkerChunkProcessor({
    Map<String, Completer<void>>? blockers,
    this.audioPath,
  }) : _blockers = blockers ?? <String, Completer<void>>{};

  final Map<String, Completer<void>> _blockers;
  final String? audioPath;
  final startedChunks = <String>[];

  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent event) emit,
  ) async {
    startedChunks.add(request.chunkId);
    emit(
      SpeechWorkerEvent(
        type: SpeechWorkerEventType.inferencing,
        sessionId: request.sessionId,
        generationId: request.generationId,
        chunkId: request.chunkId,
        emittedAt: DateTime.now().toUtc(),
        stage: 'inferencing',
      ),
    );
    await _blockers[request.chunkId]?.future;
    emit(
      SpeechWorkerEvent(
        type: SpeechWorkerEventType.completed,
        sessionId: request.sessionId,
        generationId: request.generationId,
        chunkId: request.chunkId,
        emittedAt: DateTime.now().toUtc(),
        stage: 'completed',
        audioPath: audioPath ?? '/tmp/${request.chunkId}.wav',
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}
