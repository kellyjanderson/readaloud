import 'dart:async';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/kokoro_speech_worker_processor.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';

void slowResident(Map<String, dynamic> input) async {
  final reply = input['reply'] as SendPort;
  final port = ReceivePort();
  reply.send({'kind': 'ready', 'port': port.sendPort});
  await for (final raw in port) {
    final command = raw as Map;
    if (command['kind'] == 'chunk') {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final request = SpeechWorkerChunkRequest.fromMap(
        Map<String, dynamic>.from(command['request'] as Map),
      );
      reply.send({
        ...SpeechWorkerEvent(
          type: SpeechWorkerEventType.completed,
          sessionId: request.sessionId,
          generationId: request.generationId,
          chunkId: request.chunkId,
          emittedAt: DateTime.now(),
          stage: 'completed',
        ).toMap(),
        'kind': 'event',
        'id': command['id'],
      });
    }
    reply.send({'kind': 'done', 'id': command['id'], 'bindings': []});
    if (command['kind'] == 'shutdown') {
      port.close();
      return;
    }
  }
}

void exitingResident(Map<String, dynamic> input) => Isolate.exit();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  KokoroSpeechWorkerChunkProcessor processor(
    void Function(Map<String, dynamic>) entry,
  ) => KokoroSpeechWorkerChunkProcessor(
    rootIsolateToken: RootIsolateToken.instance!,
    modelPath: 'unused',
    voicesDirectory: 'unused',
    generatedAudioDirectory: 'unused',
    engineId: 'test',
    engineVersion: '1',
    timeout: const Duration(milliseconds: 150),
    workerEntryPoint: entry,
  );
  test(
    'timeout quarantines admission, suppresses late success and drains before shutdown',
    () async {
      final worker = processor(slowResident);
      await worker.prepareResources(documentId: 'd', revision: 1, voiceIds: []);
      final events = <SpeechWorkerEvent>[];
      await expectLater(
        worker.process(
          const SpeechWorkerChunkRequest(
            sessionId: 's',
            generationId: 'g',
            chunkId: 'c',
            segmentIds: [],
            cacheKey: 'c',
            boundaryClass: BreakClass.none,
            documentId: 'd',
            normalizationVersion: '1',
            speakText: 'hello',
            tokens: [1],
            languageTag: 'en',
            voiceId: 'v',
            rate: 1,
          ),
          events.add,
        ),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        worker.prepareResources(documentId: 'new', revision: 2, voiceIds: []),
        throwsStateError,
      );
      var shut = false;
      final closing = worker.dispose().then((_) => shut = true);
      await Future<void>.delayed(Duration.zero);
      expect(shut, isFalse);
      await closing.timeout(const Duration(seconds: 3));
      expect(events, isEmpty);
      await worker.dispose();
    },
  );
  test('worker exit settles startup instead of waiting forever', () async {
    final worker = processor(exitingResident);
    await expectLater(
      worker.prepareResources(documentId: 'd', revision: 1, voiceIds: []),
      throwsStateError,
    );
    await worker.dispose().timeout(const Duration(seconds: 3));
  });
}
