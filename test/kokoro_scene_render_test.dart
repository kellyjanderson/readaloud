import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/models/chunk_plan.dart';
import 'package:read_aloud/src/models/engine_capability.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/tts_artifact.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/exported_audio_assembler.dart';
import 'package:read_aloud/src/services/kokoro_pronunciation_translation_service.dart';
import 'package:read_aloud/src/services/kokoro_tokenization_worker.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/services/speech_worker_pipeline.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/services/speech_audio_packet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.create());
  tearDown(() => fixture.close());

  test(
    'playable export packets precede held scene completion and durable publication',
    () async {
      fixture.processor.streamGate = Completer<void>();
      final packetReady = Completer<TtsPlayableAudioPacket>();
      final publishing = Completer<void>();
      final published = Completer<void>();
      final exporting = fixture.engine.exportAudio(
        fixture.request(
          packet: (value) async => packetReady.complete(value),
          publish: (_) async {
            publishing.complete();
            await published.future;
          },
        ),
      );
      final packet = await packetReady.future;
      var sceneCompleted = false;
      packet.sceneCompletion.then((_) => sceneCompleted = true);
      expect(packet.sceneId, 'scene_turn-one');
      expect(packet.startWordIndex, 102);
      expect(packet.endWordIndex, 106);
      expect(packet.text, 'One two Three four');
      expect(packet.sceneTurns, hasLength(2));
      expect(packet.isInitialScene, isTrue);
      expect(sceneCompleted, isFalse);
      expect(fixture.pins.pinCount(packet.packet.audioPath), greaterThan(0));
      fixture.processor.streamGate!.complete();
      await publishing.future;
      expect(sceneCompleted, isFalse);
      published.complete();
      final finalScene = await packet.sceneCompletion;
      expect(finalScene.packetCount, 1);
      expect(finalScene.frameCount, 24000);
      expect(finalScene.onsetTrimFrames, 0);
      expect(finalScene.duration, const Duration(seconds: 1));
      await exporting;
      expect(fixture.assembler.requests.single.chunks, hasLength(1));
      expect(fixture.pins.pinCount(packet.packet.audioPath), 0);
    },
  );

  test(
    'one-scene export captures actual bindings, directions, raw provenance and global spans',
    () async {
      final entered = Completer<TtsFinalizedAudioScene>();
      final release = Completer<void>();
      final supplied = [...fixture.bindings];
      final exporting = fixture.engine.exportAudio(
        fixture.request(
          bindings: supplied,
          publish: (scene) async {
            entered.complete(scene);
            await release.future;
          },
        ),
      );
      final scene = await entered.future;
      supplied.clear();
      expect(fixture.processor.requests, hasLength(1));
      expect(scene.sceneId, 'scene_turn-one');
      expect(scene.text, 'One two Three four');
      expect(scene.engineSpeakText, 'One two\nThree four');
      expect(scene.startWordIndex, 102);
      expect(scene.endWordIndex, 106);
      expect(scene.startOffset, 12);
      expect(scene.sceneTurns.map((t) => (t.startWord, t.endWord)), [
        (102, 104),
        (104, 106),
      ]);
      expect(scene.sceneTurns.first.directions.single['delivery'], 'whispered');
      expect(
        scene.sceneTurns.first.directions.single['annotationId'],
        'direction',
      );
      expect(scene.preparedBindings.map((b) => b.voiceId), [
        'af_heart',
        'af_bella',
      ]);
      expect(scene.preparedBindings.map((b) => b.bindingRevision), [7, 7]);
      expect(scene.assignmentRevision, 13);
      expect(scene.normalizationVersion, 'normalization-r1');
      expect(scene.synthesisIdentity, 'test-synthesis-content');
      expect(scene.translationSignature, isNotEmpty);
      expect(scene.rawAudioPath, fixture.raw.path);
      expect(
        scene.rawArtifactIdentity,
        'wav-sha256:${sha256.convert(await fixture.raw.readAsBytes())}',
      );
      expect(scene.predecessorRawArtifactIdentity, isNull);
      expect(scene.boundaryPolicyVersion, isNotEmpty);
      expect(scene.boundaryClass, 'paragraph');
      expect(scene.trailingSilenceMicros, isNonNegative);
      expect(fixture.pins.pinCount(scene.rawAudioPath!), greaterThan(0));
      expect(fixture.pins.pinCount(scene.audioPath), greaterThan(0));
      expect(fixture.assembler.requests, isEmpty);
      expect(scene.isCurrent(), isTrue);
      release.complete();
      final result = await exporting;
      expect(result.chunkCount, 1);
      expect(
        fixture.assembler.requests.single.chunks.single.startWordIndex,
        102,
      );
      expect(fixture.assembler.requests.single.chunks.single.endWordIndex, 106);
      expect(fixture.pins.pinCount(scene.rawAudioPath!), 0);
      expect(fixture.pins.pinCount(scene.audioPath), 0);
      expect(scene.isCurrent(), isFalse);
    },
  );

  for (final cancel in [false, true]) {
    test(
      '${cancel ? 'cancellation' : 'supersession'} during held publication prevents assembly and drains pins',
      () async {
        final entered = Completer<TtsFinalizedAudioScene>();
        final release = Completer<void>();
        final cancellation = Completer<void>();
        var current = true;
        var published = false;
        var settled = false;
        final exporting = fixture.engine.exportAudio(
          fixture.request(
            cancelled: cancellation.future,
            isCurrent: () => current,
            publish: (scene) async {
              entered.complete(scene);
              await release.future;
              if (scene.isCurrent()) published = true;
            },
          ),
        );
        final failure = expectLater(
          exporting,
          throwsStateError,
        ).then((_) => settled = true);
        final scene = await entered.future;
        if (cancel) {
          cancellation.complete();
          await scene.cancelled;
        } else {
          current = false;
        }
        expect(scene.isCurrent(), isFalse);
        expect(fixture.pins.pinCount(scene.audioPath), greaterThan(0));
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse);
        release.complete();
        await failure;
        expect(published, isFalse);
        expect(fixture.assembler.requests, isEmpty);
        expect(fixture.pins.pinCount(scene.rawAudioPath!), 0);
        expect(fixture.pins.pinCount(scene.audioPath), 0);
      },
    );
  }

  test(
    'publication error propagates before output assembly and releases artifacts',
    () async {
      TtsFinalizedAudioScene? received;
      await expectLater(
        fixture.engine.exportAudio(
          fixture.request(
            publish: (scene) async {
              received = scene;
              throw StateError('durable storage failed');
            },
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('durable storage failed'),
          ),
        ),
      );
      expect(fixture.assembler.requests, isEmpty);
      expect(fixture.pins.pinCount(received!.audioPath), 0);
      expect(fixture.pins.pinCount(received!.rawAudioPath!), 0);
    },
  );

  test(
    'cancellation during shared initialization never binds or admits export work',
    () async {
      await fixture.close();
      final initialized = Completer<void>();
      fixture = await _Fixture.create(initialization: initialized.future);
      final cancelled = Completer<void>();
      var settled = false;
      final exporting = fixture.engine.exportAudio(
        fixture.request(cancelled: cancelled.future),
      );
      final failure = expectLater(
        exporting,
        throwsStateError,
      ).then((_) => settled = true);
      cancelled.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        settled,
        isFalse,
      ); // shared initialization drains; playback owns it too
      initialized.complete();
      await failure;
      expect(fixture.processor.requests, isEmpty);
      expect(fixture.assembler.requests, isEmpty);
    },
  );

  test('stale request never admits synthesis or publication', () async {
    await expectLater(
      fixture.engine.exportAudio(fixture.request(isCurrent: () => false)),
      throwsStateError,
    );
    expect(fixture.processor.requests, isEmpty);
    expect(fixture.assembler.requests, isEmpty);
  });

  test('request cancellation interrupts its tokenization owner', () async {
    final cancellation = Completer<void>();
    fixture.tokenizer.block = Completer<void>();
    final exporting = fixture.engine.exportAudio(
      fixture.request(cancelled: cancellation.future),
    );
    final failure = expectLater(exporting, throwsStateError);
    await fixture.tokenizer.entered.future;
    cancellation.complete();
    await failure;
    expect(fixture.tokenizer.cancelCalls, 1);
    expect(fixture.processor.requests, isEmpty);
    expect(fixture.assembler.requests, isEmpty);
  });

  test(
    'late cancellation from completed export cannot cancel adjacent export',
    () async {
      final oldCancellation = Completer<void>();
      await fixture.engine.exportAudio(
        fixture.request(cancelled: oldCancellation.future),
      );
      final entered = Completer<TtsFinalizedAudioScene>();
      final release = Completer<void>();
      final exporting = fixture.engine.exportAudio(
        fixture.request(
          publish: (scene) async {
            entered.complete(scene);
            await release.future;
          },
        ),
      );
      final scene = await entered.future;
      oldCancellation.complete();
      await Future<void>.delayed(Duration.zero);
      expect(scene.isCurrent(), isTrue);
      expect(fixture.processor.cancelledGenerations, isEmpty);
      release.complete();
      await exporting;
      expect(fixture.assembler.requests, hasLength(2));
    },
  );

  test(
    'rendering below saved-playback low water admits work and cancellation preserves its pins',
    () async {
      fixture.processor.allowPreparation = true;
      final source = TtsRenderedAudioRequest(
        documentId: 'book',
        sceneId: 'saved-scene',
        manifestIdentity: 'saved-manifest',
        intentRevision: 1,
        text: 'Saved scene',
        startWordIndex: 0,
        endWordIndex: 2,
        sourceEndWordIndex: 2,
        startOffset: 0,
        sceneTurns: const [],
        audioPath: fixture.raw.path,
        format: const TtsRenderedAudioFormat(
          sampleRate: 24000,
          channels: 1,
          bitsPerSample: 16,
        ),
        duration: const Duration(seconds: 1),
        rangeSequence: 0,
      );
      await fixture.engine.playRendered(source);
      await _until(() => fixture.player.playCalls == 1);
      final stopCallsBeforeExport = fixture.player.stopCalls;
      final cancellation = Completer<void>();
      final entered = Completer<TtsFinalizedAudioScene>();
      final exporting = fixture.engine.exportAudio(
        fixture.request(
          prepareOnDemand: true,
          cancelled: cancellation.future,
          publish: (scene) async {
            entered.complete(scene);
            await scene.cancelled;
          },
        ),
      );
      final failure = expectLater(exporting, throwsStateError);
      await entered.future.timeout(const Duration(seconds: 3));
      cancellation.complete();
      await failure;
      expect(fixture.player.sources, [fixture.raw.path]);
      expect(fixture.player.stopCalls, stopCallsBeforeExport);
      expect(fixture.engine.debugPlaybackPinCount, 1);
      expect(fixture.pins.pinCount(fixture.raw.path), 1);
      expect(fixture.assembler.requests, isEmpty);
    },
  );
}

class _Fixture {
  _Fixture(
    this.directory,
    this.raw,
    this.player,
    this.processor,
    this.tokenizer,
    this.assembler,
    this.pins,
    this.bindings,
    this.engine,
  );
  final Directory directory;
  final File raw;
  final _FakePlayer player;
  final _Processor processor;
  final _Tokenizer tokenizer;
  final _Assembler assembler;
  final AudioArtifactPins pins;
  final List<PreparedVoiceBinding> bindings;
  final KokoroTtsEngine engine;

  static Future<_Fixture> create({Future<void>? initialization}) async {
    final directory = await Directory.systemTemp.createTemp(
      'scene-render-test-',
    );
    final raw = File('${directory.path}/raw.wav');
    await raw.writeAsBytes(_wav());
    final player = _FakePlayer();
    final processor = _Processor(raw.path);
    final tokenizer = _Tokenizer();
    final assembler = _Assembler();
    final pins = AudioArtifactPins();
    final bindings = ['af_heart', 'af_bella', 'af_nicole']
        .map(
          (voice) => PreparedVoiceBinding(
            voiceId: voice,
            voiceDigest: 'digest-$voice',
            modelDigest: 'model',
            engineVersion: '12',
            pronunciationProfileId: 'profile',
            bindingRevision: 7,
            documentId: 'book',
          ),
        )
        .toList();
    final engine = KokoroTtsEngine.withExportTestOwners(
      player: player,
      processor: processor,
      tokenizer: tokenizer,
      bindings: bindings,
      artifactPins: pins,
      exportAssembler: assembler,
      initialization: initialization,
    );
    return _Fixture(
      directory,
      raw,
      player,
      processor,
      tokenizer,
      assembler,
      pins,
      bindings,
      engine,
    );
  }

  TtsExportRequest request({
    List<PreparedVoiceBinding>? bindings,
    bool prepareOnDemand = false,
    Future<void> Function(TtsFinalizedAudioScene)? publish,
    Future<void>? cancelled,
    bool Function()? isCurrent,
    Future<void> Function(TtsPlayableAudioPacket)? packet,
  }) => TtsExportRequest(
    text: 'Before now. One two Three four',
    outputPath: '${directory.path}/output.wav',
    documentId: 'book',
    sessionId: 'render-session',
    normalizationVersion: 'normalization-r1',
    chunkPlan: ChunkPlan(
      planId: 'one-scene-only',
      chunks: [
        _spec(
          'scene',
          'One two Three four',
          'af_heart',
          2,
          6,
          turns: [
            _spec('turn-one', 'One two', 'af_heart', 2, 4, directed: true),
            _spec('turn-two', 'Three four', 'af_bella', 4, 6),
          ],
        ),
      ],
    ),
    preparedResources: prepareOnDemand ? null : (bindings ?? this.bindings),
    sourceWordOffset: 100,
    assignmentRevision: 13,
    cancelled: cancelled,
    isCurrent: isCurrent,
    onRenderedScene: publish,
    onPlayablePacket: packet,
  );

  Future<void> close() async {
    await engine.shutdownResources();
    engine.dispose();
    await Future<void>.delayed(Duration.zero);
    await directory.delete(recursive: true);
  }
}

ChunkSpec _spec(
  String id,
  String text,
  String voice,
  int start,
  int end, {
  List<ChunkSpec> turns = const [],
  bool directed = false,
}) => ChunkSpec(
  chunkId: id,
  segmentIds: [id],
  speakText: text,
  voiceId: voice,
  boundaryClass: BreakClass.paragraph,
  startSegmentIndex: start,
  endSegmentIndex: end,
  estimatedWordCount: end - start,
  cacheKey: 'cache-$id',
  startWordIndex: start,
  endWordIndex: end,
  sceneTurns: turns,
  ttsSegments: [
    TtsArtifactSegment(
      segmentId: id,
      speakText: text,
      pronunciationArtifacts: const [],
      performanceIntents: directed
          ? [
              RealizedPerformanceIntent(
                annotation: SpeechAnnotation(
                  annotationId: 'direction',
                  segmentId: id,
                  startWord: start,
                  endWord: end,
                  kind: SpeechAnnotationKind.deliveryIntent,
                  source: SpeechAnnotationSource.userOverride,
                  confidence: 1,
                  deliveryIntent: DeliveryIntent.whispered,
                ),
              ),
            ]
          : const [],
    ),
  ],
);

class _Tokenizer extends KokoroTokenizationWorker {
  _Tokenizer()
    : super(
        assets: const KokoroTokenizerAssets(
          vocabularyJson: '{}',
          lexiconJson: '{}',
          goldJson: '{}',
          silverJson: '{}',
        ),
        capabilityProfile: const EngineCapabilityRegistry().lookup(
          engineId: 'kokoro',
        ),
      );
  Completer<void>? block;
  final entered = Completer<void>();
  var cancelCalls = 0;
  @override
  Future<KokoroTokenizationResult> prepare(
    ChunkSpec spec,
    String languageTag, {
    EngineCapabilityProfile? capabilityOverride,
    String? requestId,
    int documentRevision = 0,
    int bindingRevision = 0,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await block?.future;
    return KokoroTokenizationResult(
      requestId: 'test',
      documentRevision: 0,
      bindingRevision: 0,
      workerName: 'deterministic-test-owner',
      tokens: const [1],
      phonemeTraceLines: const [],
      finalPhonemeString: spec.speakText,
      translatedChunk: KokoroTranslatedChunk(
        chunkId: spec.chunkId,
        capabilityProfileId: 'kokoro-test',
        speakText: spec.speakText,
        missingFallbackWordCount: 0,
        pronunciationArtifacts: const [],
        payloadUnits: [
          KokoroEnginePayloadUnit(
            kind: KokoroEnginePayloadUnitKind.plainText,
            value: spec.speakText,
          ),
        ],
      ),
    );
  }

  @override
  void cancel() {
    cancelCalls++;
    if (block?.isCompleted == false) {
      block!.completeError(StateError('Tokenization cancelled.'));
    }
  }
}

class _Processor
    implements
        SpeechWorkerResourceOwner,
        CancellableSpeechWorkerChunkProcessor,
        StreamingSpeechWorkerChunkProcessor {
  bool allowPreparation = false;
  Completer<void>? streamGate;

  _Processor(this.rawPath);
  final String rawPath;
  final requests = <SpeechWorkerChunkRequest>[];
  final cancelledGenerations = <String>[];
  @override
  Future<void> processWithAudioPackets(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
    Future<void> Function(SpeechAudioPacket) onAudioPacket,
  ) async {
    await onAudioPacket(
      SpeechAudioPacket(
        sessionId: request.sessionId,
        generationId: request.generationId,
        chunkId: request.chunkId,
        audioPath: rawPath,
        packetIndex: 0,
        frameStart: 0,
        frameCount: 24000,
        sampleRate: 24000,
      ),
    );
    await streamGate?.future;
    await process(
      request,
      (event) => emit(
        SpeechWorkerEvent(
          type: event.type,
          sessionId: event.sessionId,
          generationId: event.generationId,
          chunkId: event.chunkId,
          emittedAt: event.emittedAt,
          stage: event.stage,
          audioPath: event.audioPath,
          duration: event.duration,
          streamedPacketCount: 1,
          streamedFrameCount: 24000,
        ),
      ),
    );
  }

  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
  ) async {
    requests.add(request);
    emit(
      SpeechWorkerEvent(
        type: SpeechWorkerEventType.completed,
        sessionId: request.sessionId,
        generationId: request.generationId,
        chunkId: request.chunkId,
        emittedAt: DateTime.now(),
        stage: 'completed',
        audioPath: rawPath,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  void cancelGeneration(String generationId) =>
      cancelledGenerations.add(generationId);
  @override
  Future<List<PreparedVoiceBinding>> prepareResources({
    required String documentId,
    required int revision,
    required Iterable<String> voiceIds,
    String pronunciationProfileId = 'kokoro-default',
  }) async {
    if (!allowPreparation) throw StateError('Unexpected resource preparation.');
    return voiceIds
        .map(
          (voice) => PreparedVoiceBinding(
            voiceId: voice,
            voiceDigest: 'digest-$voice',
            modelDigest: 'model',
            engineVersion: '12',
            pronunciationProfileId: pronunciationProfileId,
            bindingRevision: revision,
            documentId: documentId,
          ),
        )
        .toList();
  }

  @override
  Future<void> releaseResources() async {}
  @override
  Future<void> dispose() async {}
}

class _Assembler extends ExportedAudioAssembler {
  final requests = <ExportedAudioAssemblyRequest>[];
  @override
  Future<TtsExportResult> assemble(ExportedAudioAssemblyRequest request) async {
    requests.add(request);
    return TtsExportResult(
      outputPath: request.outputPath,
      sidecarPath: '${request.outputPath}.json',
      duration: const Duration(seconds: 1),
      chunkCount: request.chunks.length,
      voiceId: request.voiceId,
      rate: request.rate,
      engineId: request.engineId,
      engineVersion: request.engineVersion,
    );
  }
}

// Container/provenance fixture only: deterministic non-silent PCM does not
// establish speech quality or human listening acceptance.
Uint8List _wav() {
  const frames = 24000;
  final bytes = Uint8List(44 + frames * 2);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, 'WAVEfmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 24000, Endian.little);
  data.setUint32(28, 48000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) {
    data.setInt16(
      44 + i * 2,
      i < 1200 || i >= frames - 1200 ? 0 : (i % 2 == 0 ? 8000 : -8000),
      Endian.little,
    );
  }
  return bytes;
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Playback did not reach expected state.');
}

class _FakePlayer extends Fake implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final indexes = StreamController<int?>.broadcast(sync: true);
  final sources = <String>[];
  Completer<void>? installGate;
  var installCalls = 0;
  var addCalls = 0;
  var playCalls = 0;
  var stopCalls = 0;
  var _index = 0;
  var _position = Duration.zero;
  var _state = PlayerState(false, ProcessingState.ready);
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<int?> get currentIndexStream => indexes.stream;
  @override
  PlayerState get playerState => _state;
  @override
  ProcessingState get processingState => _state.processingState;
  @override
  int? get currentIndex => _index;
  @override
  Duration get position => _position;
  @override
  double get speed => 1;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    installCalls++;
    if (installCalls == 1) await installGate?.future;
    sources
      ..clear()
      ..addAll(audioSources.map(_path));
    _state = PlayerState(false, ProcessingState.ready);
    _index = 0;
    return null;
  }

  String _path(AudioSource source) => (source as UriAudioSource).uri.path;
  @override
  Future<void> addAudioSource(AudioSource source) async {
    addCalls++;
    sources.add(_path(source));
  }

  @override
  Future<void> insertAudioSource(int index, AudioSource source) async =>
      sources.insert(index, _path(source));
  @override
  Future<void> removeAudioSourceRange(int start, int end) async =>
      sources.removeRange(start, end);
  @override
  Future<void> clearAudioSources() async => sources.clear();
  @override
  Future<void> play() async {
    playCalls++;
    _state = PlayerState(true, ProcessingState.ready);
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (index != null) _index = index;
    _state = PlayerState(true, ProcessingState.ready);
  }

  void moveTo(int index) {
    _index = index;
    indexes.add(index);
  }

  void advance(Duration value) {
    _position = value;
    positions.add(value);
  }

  void complete() {
    _state = PlayerState(true, ProcessingState.completed);
    states.add(_state);
  }

  @override
  Future<void> dispose() async {
    await states.close();
    await positions.close();
    await indexes.close();
  }
}
