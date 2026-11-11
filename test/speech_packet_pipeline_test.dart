import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';
import 'package:read_aloud/src/services/speech_audio_packet.dart';
import 'package:read_aloud/src/services/speech_runtime.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';
import 'package:read_aloud/src/services/synthesis_admission_owner.dart';
import 'package:read_aloud/src/services/synthesis_boundary_policy.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'packet validation rejects foreign identity, sequence, format and path',
    () async {
      final root = await Directory.systemTemp.createTemp('packet-validation-');
      addTearDown(() => root.delete(recursive: true));
      final path = '${root.resolveSymbolicLinksSync()}/packet-0000.wav';
      File(path).writeAsBytesSync(_wav([3000, -3000, 4000], 24000));
      final packet = _packet(path);
      final response = {
        ...packet.toMap(),
        'synthesisIdentity': 'synth',
        'bindingFingerprint': 'binding',
        'bindingRevision': 1,
      };
      final input = <String, Object?>{
        'response': response,
        'attemptPath': root.path,
        'sessionId': 's',
        'generationId': 'g',
        'chunkId': 'c',
        'synthesisIdentity': 'synth',
        'bindingFingerprint': 'binding',
        'bindingRevision': 1,
        'packetIndex': 0,
        'frameStart': 0,
      };
      expect(validateMlxAudioPacket(input).frameCount, 3);
      for (final change in [
        {'sessionId': 'foreign'},
        {'generationId': 'foreign'},
        {'chunkId': 'foreign'},
        {'synthesisIdentity': 'foreign'},
        {'bindingFingerprint': 'foreign'},
        {'bindingRevision': 2},
        {'packetIndex': 1},
        {'frameStart': 1},
        {'sampleRate': 44100},
        {'frameCount': 4},
        {'channels': 2},
        {'bitsPerSample': 32},
        {'audioPath': '${root.path}/../escaped.wav'},
      ]) {
        expect(
          () => validateMlxAudioPacket({
            ...input,
            'response': {...response, ...change},
          }),
          throwsFormatException,
          reason: '$change',
        );
      }
      File(path).deleteSync();
      final other = File('${root.path}/other.wav')
        ..writeAsBytesSync(_wav([1, 2, 3], 24000));
      Link(path).createSync(other.path);
      expect(() => validateMlxAudioPacket(input), throwsFormatException);
    },
  );

  for (final cancel in [false, true]) {
    test(
      'runtime packet crosses lease before completion; ${cancel ? 'cancel drops late failure' : 'late failure remains terminal'}',
      () async {
        final processor = _StreamingProcessor();
        final owner = SynthesisAdmissionOwner(
          processor,
          exportMayRun: () => true,
        );
        final runtime = SpeechRuntime(
          engineId: 'fish_drama3',
          processor: owner.lease(export: true),
          boundaryCorrectionExecutor: (_) async =>
              throw StateError('must not finalize a failed scene'),
        );
        final events = <SpeechRuntimeEvent>[];
        runtime.events.listen(events.add);
        await runtime.initializeRuntime();
        await runtime.activateSession(_session());
        final early = runtime.events.firstWhere(
          (e) => e.type == SpeechRuntimeEventType.chunkPacketReady,
        );
        await runtime.preparePriorityChunk(
          sessionId: 's',
          generationId: 'g',
          chunk: _chunk(),
        );
        final event = await early.timeout(const Duration(seconds: 2));
        expect(event.audioPacket!.frameStart, 0);
        expect(
          SpeechRuntimeEvent.fromMap(event.toMap()).audioPacket!.toMap(),
          event.audioPacket!.toMap(),
        );
        expect(
          events.where((e) => e.type == SpeechRuntimeEventType.chunkReady),
          isEmpty,
        );
        final failure = cancel
            ? null
            : runtime.events.firstWhere(
                (e) => e.type == SpeechRuntimeEventType.chunkFailed,
              );
        if (cancel) await runtime.cancelSession('s');
        processor.release.complete();
        await processor.drained.future;
        await failure;
        await runtime.shutdownRuntime();
        await owner.shutdown();
        expect(
          events.where((e) => e.type == SpeechRuntimeEventType.chunkReady),
          isEmpty,
        );
        expect(
          events
              .where((e) => e.type == SpeechRuntimeEventType.chunkFailed)
              .length,
          cancel ? 0 : 1,
        );
      },
    );
  }

  test(
    'short packet handoff is awaited, completion counts and predecessor are retained',
    () async {
      final processor = _StreamingProcessor(fail: false);
      final owner = SynthesisAdmissionOwner(
        processor,
        exportMayRun: () => true,
      );
      final corrections = <Map<String, Object?>>[];
      final runtime = SpeechRuntime(
        engineId: 'fish_drama3',
        processor: owner.lease(export: false),
        boundaryCorrectionExecutor: (input) async {
          corrections.add(input);
          return {
            'durationMillis': 1,
            'applied': true,
            'leadingSilenceBeforeMs': 2,
            'leadingSilenceAfterMs': 1,
            'trailingSilenceBeforeMs': 0,
            'trailingSilenceAfterMs': 0,
            'joinSilenceBeforeMs': 2,
            'joinSilenceAfterMs': 1,
            'rawSampleRate': 24000,
            'onsetTrimFrames': 1,
          };
        },
      );
      await runtime.initializeRuntime();
      final descriptor = _session(predecessor: true);
      expect(
        SpeechRuntimeSessionDescriptor.fromPayload(
          descriptor.toPayload(),
        ).predecessorTrailingSilence,
        const Duration(milliseconds: 210),
      );
      await runtime.activateSession(descriptor);
      final packet = runtime.events.firstWhere(
        (e) => e.type == SpeechRuntimeEventType.chunkPacketReady,
      );
      final ready = runtime.events.firstWhere(
        (e) => e.type == SpeechRuntimeEventType.chunkReady,
      );
      await runtime.preparePriorityChunk(
        sessionId: 's',
        generationId: 'g',
        chunk: _chunk(),
      );
      final first = await packet;
      expect(first.isInitialChunk, false);
      expect(first.payload['previousTrailingSilenceMs'], 210);
      processor.release.complete();
      final completed = await ready;
      expect(completed.payload['streamedPacketCount'], 1);
      expect(completed.payload['streamedFrameCount'], 3);
      expect(completed.payload['onsetTrimFrames'], 1);
      expect(corrections.single['predecessorRawArtifactIdentity'], 'saved-raw');
      expect(corrections.single['previousTrailingSilenceMs'], 210);
      expect(corrections.single['isInitialChunk'], false);
      await runtime.shutdownRuntime();
      await owner.shutdown();
    },
  );

  test(
    'onset helper matches finalized PCM at native rates and all boundary classes',
    () async {
      final root = await Directory.systemTemp.createTemp('packet-onset-');
      addTearDown(() => root.delete(recursive: true));
      for (final rate in [24000, 44100]) {
        for (final boundary in BreakClass.values) {
          for (final initial in [false, true]) {
            final leading = (rate * .3757).round();
            final source =
                File('${root.path}/$rate-${boundary.name}-$initial.wav')
                  ..writeAsBytesSync(
                    _wav([...List.filled(leading, 0), 3000, -4000, 3000], rate),
                  );
            final frames = const SynthesisBoundaryPolicy().onsetTrimFrames(
              leadingSilentFrames: leading,
              sampleRate: rate,
              boundaryClass: boundary,
              isInitialChunk: initial,
              isResumedChunk: false,
              previousTrailingSilence: const Duration(milliseconds: 210),
            );
            final result = const SynthesisBoundaryPolicy().correctWavFileSync(
              chunkId: 'c',
              wavFilePath: source.path,
              boundaryClass: boundary,
              isInitialChunk: initial,
              isResumedChunk: false,
              previousTrailingSilence: const Duration(milliseconds: 210),
            );
            expect(
              source.readAsBytesSync().sublist(44 + frames * 2),
              File(result.audioPath!).readAsBytesSync().sublist(44),
            );
          }
        }
      }
    },
  );
}

SpeechAudioPacket _packet(String path) => SpeechAudioPacket(
  sessionId: 's',
  generationId: 'g',
  chunkId: 'c',
  audioPath: path,
  packetIndex: 0,
  frameStart: 0,
  frameCount: 3,
  sampleRate: 24000,
);

SpeechRuntimeSessionDescriptor _session({bool predecessor = false}) =>
    SpeechRuntimeSessionDescriptor(
      sessionId: 's',
      documentId: 'd',
      engineId: 'fish_drama3',
      voiceId: 'v',
      rate: 1,
      startSegmentId: 'segment',
      normalizationVersion: '1',
      enableAudioPackets: true,
      predecessorRawArtifactIdentity: predecessor ? 'saved-raw' : null,
      predecessorTrailingSilence: predecessor
          ? const Duration(milliseconds: 210)
          : null,
    );
SpeechRuntimeChunkPayload _chunk() => SpeechRuntimeChunkPayload(
  chunkId: 'c',
  segmentIds: const ['segment'],
  cacheKey: 'key',
  boundaryClass: BreakClass.sentence,
  documentId: 'd',
  normalizationVersion: '1',
  speakText: 'Hello',
  tokens: const [1],
  languageTag: 'en',
  voiceId: 'v',
  rate: 1,
  isInitialChunk: true,
  isResumedChunk: false,
);

class _StreamingProcessor
    implements SpeechWorkerChunkProcessor, StreamingSpeechWorkerChunkProcessor {
  _StreamingProcessor({this.fail = true});
  final bool fail;
  final release = Completer<void>();
  final drained = Completer<void>();
  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
  ) => throw StateError('stream opt-in was lost');
  @override
  Future<void> processWithAudioPackets(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
    Future<void> Function(SpeechAudioPacket) onAudioPacket,
  ) async {
    try {
      expect(request.enableAudioPackets, true);
      await onAudioPacket(_packet('/owned/packet-0000.wav'));
      await release.future;
      emit(
        SpeechWorkerEvent(
          type: fail
              ? SpeechWorkerEventType.failed
              : SpeechWorkerEventType.completed,
          sessionId: request.sessionId,
          generationId: request.generationId,
          chunkId: request.chunkId,
          emittedAt: DateTime.now().toUtc(),
          stage: fail ? 'failed' : 'completed',
          audioPath: '/owned/complete.wav',
          duration: const Duration(milliseconds: 1),
          streamedPacketCount: 1,
          streamedFrameCount: 3,
          message: fail ? 'late producer failure' : null,
        ),
      );
    } finally {
      drained.complete();
    }
  }

  @override
  Future<void> dispose() async {}
}

Uint8List _wav(List<int> frames, int rate) {
  final bytes = Uint8List(44 + frames.length * 2);
  final data = ByteData.sublistView(bytes);
  void tag(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, value.codeUnits);
  tag(0, 'RIFF');
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  tag(36, 'data');
  data.setUint32(4, bytes.length - 8, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(40, frames.length * 2, Endian.little);
  for (var i = 0; i < frames.length; i++) {
    data.setInt16(44 + i * 2, frames[i], Endian.little);
  }
  return bytes;
}
