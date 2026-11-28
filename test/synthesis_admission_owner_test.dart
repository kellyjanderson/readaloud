import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';
import 'package:read_aloud/src/services/synthesis_admission_owner.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';

void main() {
  test(
    'lease cancellation cannot abort another lease with the same generation',
    () async {
      final processor = _CancellableProcessor();
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => true,
      );
      final playback = owner.lease(export: false);
      final export = owner.lease(export: true);
      final active = export.process(_request('p1'), (_) {});
      (playback as CancellableSpeechWorkerChunkProcessor).cancelGeneration('g');
      playback.cancelPending();
      expect(processor.cancelled, isEmpty);
      (export as CancellableSpeechWorkerChunkProcessor).cancelGeneration('g');
      expect(processor.cancelled, ['g']);
      await active;
      await owner.shutdown();
    },
  );
  test(
    'buffer hysteresis, count cap and actual player speed govern admission',
    () {
      final policy = KokoroBufferAdmission(maxChunks: 6);
      expect(
        policy.admits(
          audioLead: const Duration(seconds: 8),
          outstandingChunks: 2,
        ),
        isFalse,
      );
      expect(
        policy.admits(
          audioLead: const Duration(seconds: 6),
          outstandingChunks: 2,
        ),
        isFalse,
      );
      expect(
        policy.admits(
          audioLead: const Duration(seconds: 4),
          outstandingChunks: 2,
        ),
        isTrue,
      );
      expect(
        policy.admits(audioLead: Duration.zero, outstandingChunks: 6),
        isFalse,
      );
      expect(
        policy.admits(
          audioLead: const Duration(seconds: 6),
          outstandingChunks: 2,
          playerSpeed: 2,
        ),
        isTrue,
      );
      expect(
        policy.admits(
          audioLead: const Duration(seconds: 4),
          outstandingChunks: 2,
          playerSpeed: 0.5,
        ),
        isFalse,
      );
    },
  );
  test(
    'playback wins next slot while export lease preserves shared owner',
    () async {
      final processor = _Processor();
      var safe = false;
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => safe,
      );
      final playback = owner.lease(export: false);
      final export = owner.lease(export: true);
      final first = playback.process(_request('p1'), (_) {});
      final background = export.process(_request('export'), (_) {});
      final second = playback.process(_request('p2'), (_) {});
      expect(processor.order, ['p1']);
      processor.gate.complete();
      await first;
      await second;
      expect(processor.order, ['p1', 'p2']);
      safe = true;
      owner.signal();
      await background;
      expect(processor.order, ['p1', 'p2', 'export']);
      await export.dispose();
      expect(processor.closed, isFalse);
      await playback.dispose();
      await owner.shutdown();
      expect(processor.closed, isTrue);
    },
  );
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
  final order = <String>[];
  final gate = Completer<void>();
  bool closed = false;
  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
  ) async {
    order.add(request.chunkId);
    if (request.chunkId == 'p1') await gate.future;
  }

  @override
  Future<void> dispose() async {
    closed = true;
  }
}

class _CancellableProcessor extends _Processor
    implements CancellableSpeechWorkerChunkProcessor {
  final cancelled = <String>[];
  @override
  void cancelGeneration(String generationId) {
    cancelled.add(generationId);
    if (!gate.isCompleted) gate.complete();
  }
}
