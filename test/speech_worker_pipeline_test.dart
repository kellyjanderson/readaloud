import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';

void main() {
  group('SpeechWorkerPipeline', () {
    test('emits queued and worker stage events for a prepared chunk', () async {
      final processor = _FakeSpeechWorkerChunkProcessor();
      final pipeline = SpeechWorkerPipeline(processor: processor);
      final events = <SpeechWorkerEvent>[];
      final subscription = pipeline.events.listen(events.add);

      await pipeline.prepareChunk(_request('generation-a', 'chunk-a'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        events.map((event) => event.type),
        <SpeechWorkerEventType>[
          SpeechWorkerEventType.queued,
          SpeechWorkerEventType.phonemizing,
          SpeechWorkerEventType.completed,
        ],
      );
      expect(processor.processedChunkIds, <String>['chunk-a']);

      await subscription.cancel();
      await pipeline.shutdown();
    });

    test('prioritizes prepareChunk ahead of queued plan chunks', () async {
      final blocker = Completer<void>();
      final processor = _FakeSpeechWorkerChunkProcessor(
        blockers: <String, Completer<void>>{'warmup': blocker},
      );
      final pipeline = SpeechWorkerPipeline(processor: processor);

      await pipeline.prepareChunk(_request('generation-a', 'warmup'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await pipeline.preparePlan('generation-b', <SpeechWorkerChunkRequest>[
        _request('generation-b', 'late-1'),
        _request('generation-b', 'late-2'),
      ]);
      await pipeline.prepareChunk(_request('generation-c', 'first'));

      blocker.complete();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        processor.processedChunkIds,
        <String>['warmup', 'first', 'late-1', 'late-2'],
      );

      await pipeline.shutdown();
    });

    test('suppresses stale completion after generation cancellation', () async {
      final blocker = Completer<void>();
      final processor = _FakeSpeechWorkerChunkProcessor(
        blockers: <String, Completer<void>>{'chunk-a': blocker},
      );
      final pipeline = SpeechWorkerPipeline(processor: processor);
      final events = <SpeechWorkerEvent>[];
      final subscription = pipeline.events.listen(events.add);

      await pipeline.prepareChunk(_request('generation-a', 'chunk-a'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await pipeline.cancelGeneration('generation-a');
      blocker.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        events.map((event) => event.type),
        contains(SpeechWorkerEventType.cancelled),
      );
      expect(
        events.map((event) => event.type),
        isNot(contains(SpeechWorkerEventType.completed)),
      );

      await subscription.cancel();
      await pipeline.shutdown();
    });
  });
}

SpeechWorkerChunkRequest _request(String generationId, String chunkId) {
  return SpeechWorkerChunkRequest(
    sessionId: 'session-$generationId',
    generationId: generationId,
    chunkId: chunkId,
    segmentIds: <String>[chunkId],
    cacheKey: 'cache:$chunkId',
    boundaryClass: BreakClass.sentence,
    documentId: 'document',
    normalizationVersion: 'normalization-v1',
    speakText: 'Hello from $chunkId',
    tokens: const <int>[1, 2, 3],
    languageTag: 'en-us',
    voiceId: 'af_bella',
    rate: 1.0,
  );
}

class _FakeSpeechWorkerChunkProcessor implements SpeechWorkerChunkProcessor {
  _FakeSpeechWorkerChunkProcessor({
    Map<String, Completer<void>>? blockers,
  }) : _blockers = blockers ?? <String, Completer<void>>{};

  final Map<String, Completer<void>> _blockers;
  final List<String> processedChunkIds = <String>[];

  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent event) emit,
  ) async {
    processedChunkIds.add(request.chunkId);
    emit(
      SpeechWorkerEvent(
        type: SpeechWorkerEventType.phonemizing,
        sessionId: request.sessionId,
        generationId: request.generationId,
        chunkId: request.chunkId,
        emittedAt: DateTime.now().toUtc(),
        stage: 'phonemizing',
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
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}
