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
    for (final failAfterRelease in <bool>[false, true]) {
      test(
        'cancels queued work and suppresses delayed ${failAfterRelease ? 'failure' : 'success'} before the next generation',
        () async {
          final processor = _ControlledSpeechWorkerChunkProcessor(
            failAfterRelease: failAfterRelease,
          );
          final pipeline = SpeechWorkerPipeline(processor: processor);
          final events = <SpeechWorkerEvent>[];
          final subscription = pipeline.events.listen(events.add);
          addTearDown(() async {
            processor.release();
            await subscription.cancel();
            await pipeline.shutdown();
          });
          final nextCompleted = pipeline.events
              .firstWhere(
                (event) => event.chunkId == 'fresh' && event.isTerminal,
              )
              .timeout(const Duration(seconds: 5));

          await pipeline.preparePlan('old', <SpeechWorkerChunkRequest>[
            _request('old', 'held'),
            _request('old', 'never-started'),
          ]);
          await processor.started.future.timeout(const Duration(seconds: 5));
          await pipeline.cancelGeneration('old');
          await pipeline.prepareChunk(_request('new', 'fresh'));
          expect(processor.processedChunkIds, <String>['held']);

          processor.release();
          expect((await nextCompleted).type, SpeechWorkerEventType.completed);
          expect(processor.processedChunkIds, <String>['held', 'fresh']);
          final oldTerminalEvents = events.where(
            (event) => event.generationId == 'old' && event.isTerminal,
          );
          expect(
            oldTerminalEvents.map((event) => event.chunkId),
            unorderedEquals(<String>['held', 'never-started']),
          );
          expect(
            oldTerminalEvents.map((event) => event.type),
            everyElement(SpeechWorkerEventType.cancelled),
          );
        },
      );
    }

    test(
      'delayed processor failure retains request identity and drains the queue',
      () async {
        final processor = _ControlledSpeechWorkerChunkProcessor(
          failAfterRelease: true,
        );
        final pipeline = SpeechWorkerPipeline(processor: processor);
        final events = <SpeechWorkerEvent>[];
        final subscription = pipeline.events.listen(events.add);
        addTearDown(() async {
          processor.release();
          await subscription.cancel();
          await pipeline.shutdown();
        });
        final nextCompleted = pipeline.events
            .firstWhere((event) => event.chunkId == 'fresh' && event.isTerminal)
            .timeout(const Duration(seconds: 5));

        await pipeline.prepareChunk(_request('old', 'held'));
        await processor.started.future.timeout(const Duration(seconds: 5));
        await pipeline.prepareChunk(_request('new', 'fresh'));
        processor.release();
        await nextCompleted;

        final failure = events.singleWhere(
          (event) => event.type == SpeechWorkerEventType.failed,
        );
        expect(failure.sessionId, 'session-old');
        expect(failure.generationId, 'old');
        expect(failure.chunkId, 'held');
        expect(failure.message, contains('controlled worker failure'));
        expect(processor.processedChunkIds, <String>['held', 'fresh']);
      },
    );
  });
}

// The test owns both barriers on its isolate. Only the first request waits;
// release permits either a success or a thrown failure. A terminal event from
// the queued successor proves the pipeline has consumed that outcome.
class _ControlledSpeechWorkerChunkProcessor
    implements SpeechWorkerChunkProcessor {
  _ControlledSpeechWorkerChunkProcessor({required this.failAfterRelease});

  final bool failAfterRelease;
  final processedChunkIds = <String>[];
  final started = Completer<void>();
  final _released = Completer<void>();

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent event) emit,
  ) async {
    processedChunkIds.add(request.chunkId);
    if (request.chunkId == 'held') {
      started.complete();
      await _released.future;
      if (failAfterRelease) throw StateError('controlled worker failure');
    }
    emit(
      SpeechWorkerEvent(
        type: SpeechWorkerEventType.completed,
        sessionId: request.sessionId,
        generationId: request.generationId,
        chunkId: request.chunkId,
        emittedAt: DateTime.now().toUtc(),
        stage: 'completed',
      ),
    );
  }

  @override
  Future<void> dispose() async {}
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
