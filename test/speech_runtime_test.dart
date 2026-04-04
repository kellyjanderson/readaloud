import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/speech_runtime.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';

void main() {
  final originalPlatform = defaultTargetPlatform;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = originalPlatform;
  });

  group('SpeechRuntime', () {
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

SpeechRuntimeChunkPayload _chunk(String chunkId) {
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
    isInitialChunk: true,
    isResumedChunk: false,
  );
}

class _FakeSpeechWorkerChunkProcessor implements SpeechWorkerChunkProcessor {
  _FakeSpeechWorkerChunkProcessor({Map<String, Completer<void>>? blockers})
    : _blockers = blockers ?? <String, Completer<void>>{};

  final Map<String, Completer<void>> _blockers;

  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent event) emit,
  ) async {
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
        audioPath: '/tmp/${request.chunkId}.wav',
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}
