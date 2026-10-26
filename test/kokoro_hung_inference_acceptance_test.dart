import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/kokoro_speech_worker_processor.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';

const _bound = Duration(seconds: 5);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final lateFailure in [false, true]) {
    test(
      'fake hung inference: owned timeout, quarantine, late '
      '${lateFailure ? 'failure' : 'success'} suppression and gated teardown',
      () async {
        final observations = ReceivePort();
        final controlReady = Completer<SendPort>();
        final started = Completer<void>();
        final inspected = Completer<Map>();
        final released = Completer<Map>();
        final observationSubscription = observations.listen((raw) {
          final message = raw as Map;
          switch (message['kind']) {
            case 'control':
              controlReady.complete(message['port'] as SendPort);
            case 'started':
              started.complete();
            case 'inspected':
              inspected.complete(message);
            case 'released':
              released.complete(message);
          }
        });
        final worker = KokoroSpeechWorkerChunkProcessor(
          rootIsolateToken: RootIsolateToken.instance!,
          modelPath: 'unused-no-model-access',
          voicesDirectory: 'unused-no-voice-access',
          generatedAudioDirectory: 'unused-no-audio-access',
          engineId: 'fake-only',
          engineVersion: '1',
          timeout: const Duration(milliseconds: 200),
          workerEntryPoint: _entry(observations.sendPort, lateFailure),
        );
        final observed = _ObservedProcessor(worker);
        final pipeline = SpeechWorkerPipeline(
          processor: observed,
          maxPending: 1,
        );
        final events = <SpeechWorkerEvent>[];
        final terminals = <String, Completer<SpeechWorkerEvent>>{
          'held': Completer<SpeechWorkerEvent>(),
          'newer': Completer<SpeechWorkerEvent>(),
        };
        final eventSubscription = pipeline.events.listen((event) {
          events.add(event);
          if (event.isTerminal && !terminals[event.chunkId]!.isCompleted) {
            terminals[event.chunkId]!.complete(event);
          }
        });
        SendPort? control;
        addTearDown(() async {
          // Release even after a failed assertion. No native call or asset exists
          // in this fixture; its dedicated control port remains responsive.
          control ??= await controlReady.future.timeout(_bound);
          control!.send('release');
          try {
            await pipeline.shutdown().timeout(_bound);
          } finally {
            await eventSubscription.cancel();
            await observationSubscription.cancel();
            observations.close();
          }
        });

        await worker
            .prepareResources(documentId: 'document', revision: 1, voiceIds: [])
            .timeout(_bound);
        control = await controlReady.future.timeout(_bound);
        await pipeline.prepareChunk(_request('old', 'held')).timeout(_bound);
        await started.future.timeout(_bound);
        final timeout = await terminals['held']!.future.timeout(_bound);
        expect(timeout.type, SpeechWorkerEventType.failed);
        expect(timeout.sessionId, 'session-old');
        expect(timeout.generationId, 'old');
        expect(timeout.chunkId, 'held');
        expect(timeout.message, contains('TimeoutException'));

        // A newer request receives its own fail-closed terminal outcome. A
        // quarantined resident must not admit replacement native ownership.
        await pipeline.prepareChunk(_request('new', 'newer')).timeout(_bound);
        final newer = await terminals['newer']!.future.timeout(_bound);
        expect(newer.type, SpeechWorkerEventType.failed);
        expect(newer.sessionId, 'session-new');
        expect(newer.generationId, 'new');
        expect(newer.message, contains('closing or unavailable'));
        expect(pipeline.pendingCount, 0);

        var shutdownComplete = false;
        final shutdown = pipeline.shutdown().then(
          (_) => shutdownComplete = true,
        );
        await observed.disposing.future.timeout(_bound);
        control!.send('inspect');
        final held = await inspected.future.timeout(_bound);
        expect(held['active'], 1);
        expect(held['resident'], 1);
        expect(held['chunks'], 1);
        expect(held['shutdownSeen'], false);
        expect(shutdownComplete, false);

        control!.send('release');
        final resources = await released.future.timeout(_bound);
        await shutdown.timeout(_bound);
        expect(shutdownComplete, true);
        expect(resources['active'], 0);
        expect(resources['resident'], 0);
        expect(resources['chunks'], 1);
        // Observe before the pipeline's shutdown guard, so that guard cannot
        // conceal a leaked late supervisor callback.
        expect(observed.forwarded, isEmpty);
        // Shutdown joins supervisor drain and isolate exit, making these final
        // assertions independent of wall-clock sleeps or late-event guesses.
        expect(events.where((event) => event.isTerminal).toList(), [
          same(timeout),
          same(newer),
        ]);
        expect(
          events.where(
            (event) => event.type == SpeechWorkerEventType.completed,
          ),
          isEmpty,
        );
        await pipeline.shutdown().timeout(_bound);
      },
    );
  }
}

class _ObservedProcessor implements SpeechWorkerChunkProcessor {
  _ObservedProcessor(this.worker);

  final KokoroSpeechWorkerChunkProcessor worker;
  final forwarded = <SpeechWorkerEvent>[];
  final disposing = Completer<void>();

  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
  ) => worker.process(request, (event) {
    forwarded.add(event);
    emit(event);
  });

  @override
  Future<void> dispose() {
    if (!disposing.isCompleted) disposing.complete();
    return worker.dispose();
  }
}

SpeechWorkerChunkRequest _request(String generation, String chunk) =>
    SpeechWorkerChunkRequest(
      sessionId: 'session-$generation',
      generationId: generation,
      chunkId: chunk,
      segmentIds: [chunk],
      cacheKey: chunk,
      boundaryClass: BreakClass.none,
      documentId: 'document',
      normalizationVersion: '1',
      speakText: 'fake speech',
      tokens: const [1],
      languageTag: 'en',
      voiceId: 'fake-voice',
      rate: 1,
    );

// Only sendable control data is captured by the isolate entry closure.
void Function(Map<String, dynamic>) _entry(
  SendPort observer,
  bool lateFailure,
) =>
    (configuration) => _gatedResident(configuration, observer, lateFailure);

// This fixture owns a fake resource counter and one serial command lane. It
// models drain-only adapter capability, never tensors, sessions or inference.
// A separate control lane releases the completer even while the command lane
// is held. A permanently stuck native call is outside this evidence boundary.
void _gatedResident(
  Map<String, dynamic> configuration,
  SendPort observer,
  bool lateFailure,
) async {
  final reply = configuration['reply'] as SendPort;
  final commands = ReceivePort();
  final controls = ReceivePort();
  final gate = Completer<void>();
  var resident = 0;
  var active = 0;
  var chunks = 0;
  var shutdownSeen = false;
  Map<String, Object> snapshot(String kind) => {
    'kind': kind,
    'resident': resident,
    'active': active,
    'chunks': chunks,
    'shutdownSeen': shutdownSeen,
  };
  controls.listen((message) {
    if (message == 'release' && !gate.isCompleted) gate.complete();
    if (message == 'inspect') observer.send(snapshot('inspected'));
  });
  observer.send({'kind': 'control', 'port': controls.sendPort});
  reply.send({'kind': 'ready', 'port': commands.sendPort});
  await for (final raw in commands) {
    final command = raw as Map;
    final id = command['id'];
    switch (command['kind']) {
      case 'prepare':
        resident = 1;
        reply.send({'kind': 'done', 'id': id, 'bindings': []});
      case 'chunk':
        chunks++;
        active++;
        observer.send({'kind': 'started'});
        await gate.future;
        final request = SpeechWorkerChunkRequest.fromMap(
          Map<String, dynamic>.from(command['request'] as Map),
        );
        reply.send({
          ...SpeechWorkerEvent(
            type: lateFailure
                ? SpeechWorkerEventType.failed
                : SpeechWorkerEventType.completed,
            sessionId: request.sessionId,
            generationId: request.generationId,
            chunkId: request.chunkId,
            emittedAt: DateTime.now().toUtc(),
            stage: 'late-terminal',
            message: lateFailure ? 'late fake inference failure' : null,
          ).toMap(),
          'kind': 'event',
          'id': id,
        });
        active--;
        reply.send({'kind': 'done', 'id': id});
      case 'shutdown':
        shutdownSeen = true;
        resident = 0;
        observer.send(snapshot('released'));
        commands.close();
        controls.close();
        Isolate.exit(reply, {'kind': 'done', 'id': id});
    }
  }
}
