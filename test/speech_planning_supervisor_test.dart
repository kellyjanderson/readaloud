import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/models/narration_state.dart';
import 'package:read_aloud/src/models/voice_session_realization.dart';
import 'package:read_aloud/src/services/speech_planning_supervisor.dart';

void main() {
  final doc = ReaderDocument.sample();
  SpeechPlanningContext context([String version = '2']) =>
      SpeechPlanningContext(
        realization: VoiceSessionRealizationInput(
          speechDocument: doc.speechDocument,
          baseAnnotations: doc.baseSpeechAnnotations,
          basePronunciationArtifacts: doc.basePronunciationArtifacts,
          startSegmentId: doc.speechDocument.segments.first.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1,
          narrationState: NarrationState.initial(),
        ),
        engineVersion: version,
      );
  test(
    'one-chunk windows cover document contiguously with complete realization',
    () async {
      final owner = SpeechPlanningSupervisor();
      final retained = context();
      var next = doc.speechDocument.segments.first.segmentId;
      var end = 0;
      do {
        final result = await owner.plan(
          retained,
          startSegmentId: next,
          maxChunks: 1,
        );
        expect(result.plan.chunks, hasLength(1));
        final chunk = result.plan.chunks.single;
        expect(chunk.startWordIndex, end);
        end = chunk.endWordIndex;
        expect(
          result.realization.ttsArtifactSet.segments.map((s) => s.segmentId),
          containsAll(chunk.segmentIds),
        );
        final following = result.plan.nextSegmentId;
        if (following == null) break;
        next = following;
      } while (true);
      expect(end, doc.wordCount);
      expect(owner.workerStarts, 1);
      await owner.shutdown();
    },
  );
  test(
    'idle replacement transfers a new graph and invalid window recovers',
    () async {
      final owner = SpeechPlanningSupervisor();
      final original = context();
      final first = await owner.plan(original, maxChunks: 1);
      final repeated = await owner.plan(original, maxChunks: 1);
      expect(repeated.plan.planId, first.plan.planId);
      expect(
        repeated.realization.realizationId,
        first.realization.realizationId,
      );
      expect(
        repeated.plan.chunks.single.cacheKey,
        first.plan.chunks.single.cacheKey,
      );
      expect(owner.workerStarts, 1);
      final replacement = context('3');
      final changed = await owner.plan(replacement, maxChunks: 1);
      expect(
        changed.plan.chunks.single.cacheKey,
        isNot(first.plan.chunks.single.cacheKey),
      );
      expect(owner.workerStarts, 2);
      await expectLater(
        owner.plan(replacement, maxChunks: 0),
        throwsA(isA<StateError>()),
      );
      expect((await owner.plan(replacement)).plan.chunks, isNotEmpty);
      expect(owner.workerStarts, 3);
      await owner.shutdown();
    },
  );
  test(
    'latest planning request settles cancelled predecessor and shutdown rejects work',
    () async {
      final owner = SpeechPlanningSupervisor();
      final old = owner.plan(context());
      final cancelled = expectLater(old, throwsA(isA<PlanningCancelled>()));
      final latest = owner.plan(context(), maxChunks: 1);
      await cancelled;
      expect((await latest).plan.chunks, hasLength(1));
      await owner.shutdown();
      await expectLater(
        owner.plan(context()),
        throwsA(isA<PlanningCancelled>()),
      );
    },
  );
  test(
    'same context has one active and latest pending; replacement cancels old epoch',
    () async {
      final owner = SpeechPlanningSupervisor(
        workerEntryPoint: controlledWorker,
      );
      final retained = context('slow');
      final first = owner.plan(retained, maxChunks: 1);
      final second = owner.plan(retained);
      final dropped = expectLater(second, throwsA(isA<PlanningCancelled>()));
      final third = owner.plan(retained, maxChunks: 2);
      expect(owner.activeCount, 1);
      expect(owner.pendingCount, 1);
      await dropped;
      expect((await first).plan.chunks, hasLength(1));
      expect((await third).plan.chunks.length, lessThanOrEqualTo(2));
      expect(owner.workerStarts, 1);
      final old = owner.plan(context('slow'));
      final oldTerminal = expectLater(old, throwsA(isA<PlanningCancelled>()));
      final latest = owner.plan(context('2'), maxChunks: 1);
      await oldTerminal;
      expect((await latest).plan.chunks, hasLength(1));
      await owner.shutdown();
      expect(owner.activeCount, 0);
      expect(owner.pendingCount, 0);
    },
  );
  test(
    'cancel during spawn drains before fresh context and repeated shutdown',
    () async {
      final owner = SpeechPlanningSupervisor(
        workerEntryPoint: controlledWorker,
      );
      final old = owner.plan(context('slow'));
      final terminal = expectLater(old, throwsA(isA<PlanningCancelled>()));
      owner.cancel();
      await terminal;
      expect((await owner.plan(context())).plan.chunks, isNotEmpty);
      await Future.wait([owner.shutdown(), owner.shutdown()]);
      await expectLater(
        owner.plan(context()),
        throwsA(isA<PlanningCancelled>()),
      );
    },
  );
  for (final mode in ['stale', 'error', 'crash', 'hang']) {
    test('$mode fails owned request then recovers with fresh worker', () async {
      final owner = SpeechPlanningSupervisor(
        timeout: const Duration(milliseconds: 300),
        workerEntryPoint: controlledWorker,
      );
      await expectLater(
        owner.plan(context(mode)),
        throwsA(mode == 'hang' ? isA<TimeoutException>() : isA<StateError>()),
      );
      expect((await owner.plan(context())).plan.chunks, isNotEmpty);
      await owner.shutdown();
    });
  }
  test(
    'shutdown terminates active and queued requests during worker startup',
    () async {
      final owner = SpeechPlanningSupervisor(
        workerEntryPoint: controlledWorker,
      );
      final retained = context('hang');
      final first = owner.plan(retained);
      final firstTerminal = expectLater(
        first,
        throwsA(isA<PlanningCancelled>()),
      );
      final pending = owner.plan(retained);
      final pendingTerminal = expectLater(
        pending,
        throwsA(isA<PlanningCancelled>()),
      );
      await owner.shutdown();
      await Future.wait([firstTerminal, pendingTerminal]);
      expect(owner.activeCount, 0);
    },
  );
}

void controlledWorker(SpeechPlanningWorkerInput input) async {
  final mode = input.context.engineVersion;
  if (mode == 'slow') sleep(const Duration(milliseconds: 100));
  if (mode == 'crash') throw StateError('injected planning crash');
  if (!['stale', 'error', 'hang'].contains(mode)) {
    speechPlanningWorkerEntry(input);
    return;
  }
  final commands = ReceivePort();
  input.reply.send(commands.sendPort);
  await for (final raw in commands) {
    final command = raw as Map;
    if (mode == 'hang') continue;
    input.reply.send({
      'epoch': mode == 'stale' ? input.epoch - 1 : input.epoch,
      'sequence': command['sequence'],
      'error': 'injected old or current failure',
    });
  }
}
