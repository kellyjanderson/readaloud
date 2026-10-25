import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';
import 'package:read_aloud/src/services/synthesis_admission_owner.dart';

void main() {
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
