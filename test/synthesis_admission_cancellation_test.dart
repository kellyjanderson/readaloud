import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';
import 'package:read_aloud/src/services/synthesis_admission_owner.dart';

void main() {
  test(
    'produced credit is visible before forwarding and next native permit',
    () async {
      final processor = _CompletionDrainProcessor();
      var producedMs = 0;
      final order = <String>[];
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => false,
        playbackMayRun: () => producedMs < 8000,
        onPlaybackCompleted: (event) {
          producedMs += event.duration!.inMilliseconds;
          order.add('reserve ${event.chunkId}');
        },
      );
      final lease = owner.lease(export: false);
      final first = lease.process(_request('first'), (event) {
        if (event.type == SpeechWorkerEventType.completed) {
          expect(producedMs, 8000);
          order.add('forward first');
        }
      });
      await processor.completionSent.future;
      final second = lease.process(_request('second'), (_) {});
      expect(order, ['reserve first', 'forward first']);
      expect(processor.order, ['first']);
      processor.release.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(processor.order, [
        'first',
      ], reason: 'Finalized but unpublished audio owns credit.');
      producedMs = 0; // Publication/playback consumed the engine-owned credit.
      owner.signal();
      await second;
      expect(processor.order, ['first', 'second']);
      expect(order, ['reserve first', 'forward first', 'reserve second']);
      await lease.dispose();
      await owner.shutdown();
    },
  );

  test(
    'cache completions reserve once while export and stale identities do not',
    () async {
      final processor = _CompletionDrainProcessor(
        cacheHit: true,
        staleFirst: true,
        duplicateCompletion: true,
      );
      final credits = <String>[];
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => true,
        onPlaybackCompleted: (event) => credits.add(event.chunkId),
      );
      final playback = owner.lease(export: false);
      final seen = <SpeechWorkerEvent>[];
      final first = playback.process(_request('first'), seen.add);
      await processor.completionSent.future;
      expect(credits, ['first']);
      expect(seen.map((event) => event.type), [
        SpeechWorkerEventType.cacheHit,
        SpeechWorkerEventType.completed,
      ]);
      processor.release.complete();
      await first;
      final export = owner.lease(export: true);
      await export.process(_request('export'), (_) {});
      expect(credits, ['first']);
      await playback.dispose();
      await export.dispose();
      await owner.shutdown();
    },
  );

  test(
    'cancelled active completion cannot reserve or forward stale audio',
    () async {
      final processor = _Processor();
      var credits = 0;
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => true,
        onPlaybackCompleted: (_) {
          ++credits;
        },
      );
      final lease = owner.lease(export: false);
      final events = <SpeechWorkerEvent>[];
      final work = lease.process(_request('held'), events.add);
      final cancelled = expectLater(
        work,
        throwsA(isA<SynthesisAdmissionCancelled>()),
      );
      lease.cancelPending();
      processor.gate.complete();
      await cancelled;
      expect(credits, 0);
      _expectCancelled(events, 'held');
      await lease.dispose();
      await owner.shutdown();
    },
  );

  test(
    'credit callback failure waits native drain and becomes one pipeline failure',
    () async {
      final processor = _CompletionDrainProcessor();
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => true,
        onPlaybackCompleted: (_) => throw StateError('credit failure'),
      );
      final lease = owner.lease(export: false);
      final pipeline = SpeechWorkerPipeline(processor: lease);
      final events = <SpeechWorkerEvent>[];
      final failed = Completer<SpeechWorkerEvent>();
      final subscription = pipeline.events.listen((event) {
        events.add(event);
        if (event.type == SpeechWorkerEventType.failed && !failed.isCompleted) {
          failed.complete(event);
        }
      });
      await pipeline.prepareChunk(_request('first'));
      await processor.completionSent.future;
      expect(
        processor.afterEmit,
        isTrue,
        reason: 'Hook errors cannot escape the native event callback.',
      );
      expect(
        failed.isCompleted,
        isFalse,
        reason: 'The active processor must drain first.',
      );
      expect(events.where((event) => event.isTerminal), isEmpty);
      processor.release.complete();
      final failure = await failed.future;
      expect(failure.message, contains('credit failure'));
      await pipeline.shutdown();
      await subscription.cancel();
      expect(
        events.where((event) => event.type == SpeechWorkerEventType.failed),
        hasLength(1),
      );
      expect(
        events.where((event) => event.type == SpeechWorkerEventType.completed),
        isEmpty,
      );
      await owner.shutdown();
    },
  );

  test('synchronous reservation does not join its own native drain', () async {
    final processor = _CompletionDrainProcessor();
    late SynthesisAdmissionOwner owner;
    Future<void>? observedDrain;
    owner = SynthesisAdmissionOwner(
      processor,
      exportMayRun: () => true,
      onPlaybackCompleted: (_) {
        observedDrain = owner.drain();
      },
    );
    final lease = owner.lease(export: false);
    final work = lease.process(_request('first'), (_) {});
    await processor.completionSent.future;
    expect(observedDrain, isNotNull);
    processor.release.complete();
    await Future.wait([work, observedDrain!]);
    await lease.dispose();
    await owner.shutdown();
  });

  test(
    'fresh lead gate blocks queued burst until explicit low-water wake',
    () async {
      final processor = _Processor();
      var hasCredit = true;
      var gateChecks = 0;
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => false,
        playbackMayRun: () {
          ++gateChecks;
          return hasCredit;
        },
      );
      final firstLease = owner.lease(export: false);
      final secondLease = owner.lease(export: false);
      final active = firstLease.process(_request('held'), (_) {});
      final second = firstLease.process(_request('second'), (_) {});
      final third = secondLease.process(_request('third'), (_) {});
      expect(processor.order, ['held']);
      // Credit can disappear while one inference is active. Its queued followers
      // must reevaluate the live lead, rather than use credit from enqueue time.
      hasCredit = false;
      processor.gate.complete();
      await active;
      await Future<void>.delayed(Duration.zero);
      expect(processor.order, ['held']);
      final checksAfterBlocking = gateChecks;
      await Future<void>.delayed(Duration.zero);
      expect(
        gateChecks,
        checksAfterBlocking,
        reason: 'No internal gate polling.',
      );
      hasCredit = true;
      await Future<void>.delayed(Duration.zero);
      expect(processor.order, [
        'held',
      ], reason: 'Only owner signal wakes credit.');
      owner.signal();
      await Future.wait([second, third]);
      expect(processor.order, ['held', 'second', 'third']);
      await firstLease.dispose();
      await secondLease.dispose();
      await owner.shutdown();
    },
  );

  test(
    'gated playback permits safe export and ungated exclusive control',
    () async {
      final processor = _Processor();
      final owner = SynthesisAdmissionOwner(
        processor,
        playbackMayRun: () => false,
        exportMayRun: () => true,
      );
      final playback = owner.lease(export: false);
      final export = owner.lease(export: true);
      final waiting = playback.process(_request('waiting'), (_) {});
      final cancelled = expectLater(
        waiting,
        throwsA(isA<SynthesisAdmissionCancelled>()),
      );
      await export.process(_request('export'), (_) {});
      var controlRan = false;
      await owner.exclusive(() async {
        controlRan = true;
      });
      expect(controlRan, isTrue);
      expect(processor.order, ['export']);
      playback.cancelPending();
      await cancelled;
      await playback.dispose();
      await export.dispose();
      await owner.shutdown();
    },
  );

  test(
    'exclusive control wins next slot without consuming lead credit',
    () async {
      final processor = _Processor();
      var hasCredit = true;
      final owner = SynthesisAdmissionOwner(
        processor,
        playbackMayRun: () => hasCredit,
        exportMayRun: () => false,
      );
      final playback = owner.lease(export: false);
      final active = playback.process(_request('held'), (_) {});
      final waiting = playback.process(_request('waiting'), (_) {});
      final cancelled = expectLater(
        waiting,
        throwsA(isA<SynthesisAdmissionCancelled>()),
      );
      var controlRan = false;
      final control = owner.exclusive(() async {
        controlRan = true;
      });
      hasCredit = false;
      processor.gate.complete();
      await Future.wait([active, control]);
      expect(controlRan, isTrue);
      expect(processor.order, ['held']);
      playback.cancelPending();
      await cancelled;
      await playback.dispose();
      await owner.shutdown();
    },
  );

  test(
    'cancel and shutdown settle playback behind both closed credit gates',
    () async {
      final processor = _Processor();
      final owner = SynthesisAdmissionOwner(
        processor,
        playbackMayRun: () => false,
        exportMayRun: () => false,
      );
      final playback = owner.lease(export: false);
      final events = <SpeechWorkerEvent>[];
      final waiting = playback.process(_request('waiting'), events.add);
      final cancelled = expectLater(
        waiting,
        throwsA(isA<SynthesisAdmissionCancelled>()),
      );
      playback.cancelPending();
      await cancelled;
      _expectCancelled(events, 'waiting');
      final export = owner.lease(export: true);
      final another = playback.process(_request('another'), (_) {});
      final background = export.process(_request('background'), (_) {});
      final terminals = [
        expectLater(another, throwsA(isA<SynthesisAdmissionCancelled>())),
        expectLater(background, throwsA(isA<SynthesisAdmissionCancelled>())),
      ];
      await Future.wait([owner.shutdown(), owner.shutdown(), ...terminals]);
      expect(processor.order, isEmpty);
      expect(processor.disposeCount, 1);
    },
  );

  test(
    'cancellation during imposed pre-process latency never starts native',
    () async {
      final processor = _Processor();
      final started = Completer<void>();
      final release = Completer<void>();
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => true,
        beforeProcess: () async {
          started.complete();
          await release.future;
        },
      );
      final lease = owner.lease(export: false);
      final events = <SpeechWorkerEvent>[];
      final work = lease.process(_request('delayed'), events.add);
      final cancelled = expectLater(
        work,
        throwsA(isA<SynthesisAdmissionCancelled>()),
      );
      await started.future;
      lease.cancelPending();
      release.complete();
      await cancelled;
      expect(processor.order, isEmpty);
      _expectCancelled(events, 'delayed');
      await owner.shutdown();
    },
  );

  test('closed export gate does not hold cancelled queued admission', () async {
    final processor = _Processor();
    var safe = false;
    final owner = SynthesisAdmissionOwner(processor, exportMayRun: () => safe);
    final lease = owner.lease(export: true);
    final events = <SpeechWorkerEvent>[];
    final work = lease.process(_request('queued'), events.add);
    final cancelled = expectLater(
      work,
      throwsA(isA<SynthesisAdmissionCancelled>()),
    );
    lease.cancelPending();
    await cancelled;
    expect(processor.order, isEmpty);
    _expectCancelled(events, 'queued');
    safe = true;
    owner.signal();
    await lease.dispose();
    expect(processor.order, isEmpty);
    expect(processor.disposeCount, 0);
    await owner.shutdown();
    expect(processor.disposeCount, 1);
  });

  test(
    'queued export cancels behind active playback without touching native call',
    () async {
      final processor = _Processor();
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => false,
      );
      final playback = owner.lease(export: false);
      final export = owner.lease(export: true);
      final first = playback.process(_request('held'), (_) {});
      final events = <SpeechWorkerEvent>[];
      final queued = export.process(_request('queued'), events.add);
      final cancelled = expectLater(
        queued,
        throwsA(isA<SynthesisAdmissionCancelled>()),
      );
      export.cancelPending();
      await cancelled;
      await export.dispose();
      expect(processor.order, ['held']);
      expect(processor.finished, isFalse);
      _expectCancelled(events, 'queued');
      processor.gate.complete();
      await first;
      expect(processor.finished, isTrue);
      await playback.dispose();
      await owner.shutdown();
    },
  );

  test(
    'active cancellation suppresses stale events and dispose waits native drain',
    () async {
      final processor = _Processor();
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => true,
      );
      final lease = owner.lease(export: true);
      final events = <SpeechWorkerEvent>[];
      final work = lease.process(_request('held'), events.add);
      final cancelled = expectLater(
        work,
        throwsA(isA<SynthesisAdmissionCancelled>()),
      );
      lease.cancelPending();
      var disposed = false;
      final disposal = lease.dispose().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);
      expect(processor.finished, isFalse);
      processor.gate.complete();
      await cancelled;
      await disposal;
      expect(disposed, isTrue);
      expect(processor.finished, isTrue);
      expect(processor.disposeCount, 0);
      _expectCancelled(events, 'held');
      await expectLater(
        lease.process(_request('closed'), (_) {}),
        throwsStateError,
      );
      await owner.shutdown();
    },
  );

  test('fresh epoch may run after gated predecessor is cancelled', () async {
    final processor = _Processor();
    var safe = false;
    final owner = SynthesisAdmissionOwner(processor, exportMayRun: () => safe);
    final lease = owner.lease(export: true);
    final oldEvents = <SpeechWorkerEvent>[];
    final old = lease.process(_request('old'), oldEvents.add);
    final cancelled = expectLater(
      old,
      throwsA(isA<SynthesisAdmissionCancelled>()),
    );
    lease.cancelPending();
    final freshEvents = <SpeechWorkerEvent>[];
    final fresh = lease.process(_request('fresh'), freshEvents.add);
    expect(processor.order, isEmpty);
    safe = true;
    owner.signal();
    await Future.wait([cancelled, fresh]);
    expect(processor.order, ['fresh']);
    _expectCancelled(oldEvents, 'old');
    expect(freshEvents.single.type, SpeechWorkerEventType.completed);
    await lease.dispose();
    await owner.shutdown();
  });

  test(
    'shutdown rejects queued work and drains active native exactly once',
    () async {
      final processor = _Processor();
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => false,
      );
      final playback = owner.lease(export: false);
      final export = owner.lease(export: true);
      final active = playback.process(_request('held'), (_) {});
      final queued = export.process(_request('queued'), (_) {});
      var exclusiveRan = false;
      final exclusive = owner.exclusive(() async {
        exclusiveRan = true;
      });
      final terminals = [
        expectLater(active, throwsA(isA<SynthesisAdmissionCancelled>())),
        expectLater(queued, throwsA(isA<SynthesisAdmissionCancelled>())),
        expectLater(exclusive, throwsA(isA<SynthesisAdmissionCancelled>())),
      ];
      final firstShutdown = owner.shutdown();
      final secondShutdown = owner.shutdown();
      expect(identical(firstShutdown, secondShutdown), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(processor.disposeCount, 0);
      expect(exclusiveRan, isFalse);
      processor.gate.complete();
      await Future.wait([...terminals, firstShutdown, secondShutdown]);
      expect(processor.order, ['held']);
      expect(processor.disposeCount, 1);
      expect(exclusiveRan, isFalse);
      await expectLater(owner.exclusive(() async {}), throwsStateError);
      expect(() => owner.lease(export: false), throwsStateError);
    },
  );

  test(
    'native failure during cancellation remains observable after drain',
    () async {
      final processor = _Processor(failNative: true);
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => true,
      );
      final lease = owner.lease(export: true);
      final events = <SpeechWorkerEvent>[];
      final active = lease.process(_request('held'), events.add);
      final failure = expectLater(
        active,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'native failure',
            'native failure',
          ),
        ),
      );
      final disposal = expectLater(
        lease.dispose(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'native failure',
            'native failure',
          ),
        ),
      );
      processor.gate.complete();
      await Future.wait([failure, disposal]);
      expect(processor.finished, isTrue);
      _expectCancelled(events, 'held');
      expect(processor.disposeCount, 0);
      await owner.shutdown();
      expect(processor.disposeCount, 1);
    },
  );

  test(
    'processor close failure is retained by idempotent owner shutdown',
    () async {
      final processor = _Processor(failDispose: true);
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => true,
      );
      final shutdown = owner.shutdown();
      final repeated = owner.shutdown();
      expect(identical(shutdown, repeated), isTrue);
      await expectLater(shutdown, throwsStateError);
      await expectLater(repeated, throwsStateError);
      expect(processor.disposeCount, 1);
    },
  );
}

void _expectCancelled(List<SpeechWorkerEvent> events, String id) {
  expect(events, hasLength(1));
  expect(events.single.type, SpeechWorkerEventType.cancelled);
  expect(events.single.sessionId, 's');
  expect(events.single.generationId, 'g');
  expect(events.single.chunkId, id);
}

SpeechWorkerChunkRequest _request(String id) => SpeechWorkerChunkRequest(
  sessionId: 's',
  generationId: 'g',
  chunkId: id,
  segmentIds: const [],
  cacheKey: id,
  boundaryClass: BreakClass.none,
  documentId: 'd',
  normalizationVersion: '1',
  speakText: id,
  tokens: const [1],
  languageTag: 'en',
  voiceId: 'v',
  rate: 1,
);

class _Processor implements SpeechWorkerChunkProcessor {
  _Processor({this.failNative = false, this.failDispose = false});
  final bool failNative;
  final bool failDispose;
  final order = <String>[];
  final gate = Completer<void>();
  bool finished = false;
  int disposeCount = 0;
  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
  ) async {
    order.add(request.chunkId);
    if (request.chunkId == 'held') await gate.future;
    finished = true;
    if (failNative) throw StateError('native failure');
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
  Future<void> dispose() async {
    ++disposeCount;
    if (failDispose) throw StateError('close failure');
  }
}

class _CompletionDrainProcessor implements SpeechWorkerChunkProcessor {
  _CompletionDrainProcessor({
    this.cacheHit = false,
    this.staleFirst = false,
    this.duplicateCompletion = false,
  });
  final bool cacheHit;
  final bool staleFirst;
  final bool duplicateCompletion;
  final completionSent = Completer<void>();
  final release = Completer<void>();
  final order = <String>[];
  bool afterEmit = false;
  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
  ) async {
    order.add(request.chunkId);
    SpeechWorkerEvent event(SpeechWorkerEventType type, {bool stale = false}) =>
        SpeechWorkerEvent(
          type: type,
          sessionId: stale ? 'stale-session' : request.sessionId,
          generationId: request.generationId,
          chunkId: request.chunkId,
          emittedAt: DateTime.now().toUtc(),
          stage: type.name,
          duration: const Duration(seconds: 8),
        );
    if (staleFirst) emit(event(SpeechWorkerEventType.completed, stale: true));
    if (cacheHit) emit(event(SpeechWorkerEventType.cacheHit));
    emit(event(SpeechWorkerEventType.completed));
    if (duplicateCompletion) emit(event(SpeechWorkerEventType.completed));
    afterEmit = true;
    if (request.chunkId == 'first') {
      completionSent.complete();
      await release.future;
    }
  }

  @override
  Future<void> dispose() async {}
}
