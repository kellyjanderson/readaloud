import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:read_aloud/src/models/character.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/radoc_audio_manifest.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/radoc_audio_package.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/services/speech_audio_packet.dart';
import 'package:read_aloud/src/services/rendered_scene_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _OfflineEngine engine;
  late ReaderController controller;
  late RenderedSceneRepository repository;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('read_aloud/document_access'),
          (call) async {
            if (call.method == 'createRadocExportStage') {
              return (await Directory.systemTemp.createTemp(
                'radoc-platform-stage-',
              )).path;
            }
            throw MissingPluginException();
          },
        );
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('reader-book-');
    engine = _OfflineEngine();
    repository = RenderedSceneRepository(Directory('${temp.path}/durable'));
    controller = ReaderController(
      ttsEngine: engine,
      deferInitialSynthesis: true,
      enablePlatformIntakeChannels: false,
      renderedSceneRepository: repository,
    );
    await controller.initialize();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('read_aloud/document_access'),
          null,
        );
    await controller.shutdownPreparation();
    controller.dispose();
    await temp.delete(recursive: true);
  });
  Future<File> fixture({
    bool secondAudio = true,
    bool staleDirections = false,
    bool lateCharacter = false,
    bool paragraphBreak = false,
    bool changedSource = false,
    bool middleGap = false,
    bool historicalEndInsideSegment = false,
    String? publishedEngine,
  }) async {
    final service = RadocAudioPackage();
    final members = <String, File>{};
    final ranges = <RadocPreparedRange>[];
    final scenes = <RadocAudioScene>[];
    final texts = [
      paragraphBreak ? 'Stay.\n\nClose.' : 'Stay close.',
      'Wait here.',
      if (middleGap) 'Keep quiet.',
    ];
    for (var i = 0; i < texts.length; i++) {
      final doc = DocumentImportService().importPastedText(
        middleGap ? texts.join(' ') : texts[i],
      );
      final name = 'prepared/$i.json';
      if (!middleGap || i == 0) {
        members[name] = await const ReaderDocumentSerializationService()
            .writeToFile(
              document: doc,
              outputPath: '${temp.path}/$i.json',
              characters: i != 1 || !lateCharacter
                  ? null
                  : CharacterCastRegistry(
                      documentId: doc.displayDocument.documentId,
                      registryVersion:
                          doc.characterCastRegistry.registryVersion,
                      entries: [
                        ...doc.characterCastRegistry.entries,
                        CastEntry(
                          castId: 'late-mara',
                          roleKind: CastEntryRoleKind.character,
                          displayLabel: 'Mara',
                          confidence: 1,
                          provenance: CastEntryProvenance.sourceMetadata,
                          characterState: CharacterState(
                            explicitGender: GenderEvidence(
                              value: CharacterGenderIdentityLabel.female,
                            ),
                            selectedVoice: const VoiceSelection(
                              mode: VoiceSelectionMode.explicit,
                              voiceId: 'other',
                              revision: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
            );
        ranges.add(
          RadocPreparedRange(
            member: name,
            startWord: middleGap ? 0 : i * 2,
            endWord: middleGap ? 6 : i * 2 + 2,
          ),
        );
      }
      if (i == 1 && (!secondAudio || middleGap)) continue;
      final audio = 'audio/$i.wav';
      members[audio] = await File('${temp.path}/$i.wav').writeAsBytes(_wav());
      final dependencies = <String, dynamic>{
        'text': texts[i],
        'rate': 1.0,
        if (staleDirections && i == 0)
          'raw': {
            'canonicalDirections': [
              {'delivery': 'whispered'},
            ],
          },
      };
      scenes.add(
        RadocAudioScene(
          sceneId: 'scene-$i',
          startWord: i * 2,
          endWord: historicalEndInsideSegment && i == 0 ? 1 : i * 2 + 2,
          audioMember: audio,
          dependencyDigest: artifactIdentity(dependencies),
          dependencies: dependencies,
          provenance: {
            'text': changedSource && i == 0
                ? 'Go close.'
                : texts[i].replaceAll(RegExp(r'\s+'), ' '),
            'startOffset': 0,
          },
          sampleRate: 24000,
          channels: 1,
          frameCount: 240,
        ),
      );
    }
    final file = File('${temp.path}/book.radoc');
    await service.export(
      destination: file,
      manifest: RadocAudioManifest(
        documentId: 'book',
        sourceId: 'source',
        preparationComplete: true,
        totalWords: middleGap ? 6 : 4,
        preparedRanges: ranges,
        analysisMembers: [],
        scenes: scenes,
        intent: {
          'engineId': ?publishedEngine,
          'defaultVoiceId': 'published',
          'multiVoice': true,
          'rate': 1.0,
          'voices': [
            {'id': 'published', 'label': 'Published voice', 'locale': 'en-US'},
            {'id': 'other', 'label': 'Other voice', 'locale': 'en-US'},
          ],
        },
      ),
      members: members,
    );
    await service.dispose();
    return file;
  }

  test(
    'unknown packet duration retains the initial parent source anchor',
    () async {
      await controller.importFilePaths([(await fixture()).path]);
      await controller.startPlayback();
      engine.onProgress!(
        const TtsProgressUpdate(
          startOffset: 0,
          endOffset: 2,
          word: 'Go',
          documentId: 'book',
          chunkId: 'scene-0',
          wordStartIndex: 0,
          wordEndIndex: 1,
          voiceId: 'published',
          rate: 1,
        ),
      );
      final pending = controller.spokenChunkRecords.single;
      expect(pending.startWordIndex, 0);
      expect(pending.audioDuration, Duration.zero);
      expect(pending.completed, false);
      engine.onProgress!(
        const TtsProgressUpdate(
          startOffset: 3,
          endOffset: 7,
          word: 'now',
          documentId: 'book',
          chunkId: 'scene-0',
          wordStartIndex: 1,
          wordEndIndex: 2,
          chunkAudioDuration: Duration(seconds: 1),
          elapsedInChunk: Duration(milliseconds: 900),
          voiceId: 'published',
          rate: 1,
        ),
      );
      final known = controller.spokenChunkRecords.single;
      expect(known.startWordIndex, 0);
      expect(known.endWordIndex, 2);
      expect(known.audioDuration, const Duration(seconds: 1));
    },
  );
  test(
    'copied complete book opens, advances and republishes without models',
    () async {
      final original = await fixture();
      final copied = await original.copy('${temp.path}/copied.radoc');
      await original.delete();
      await controller.importFilePaths([copied.path]);
      expect(
        controller.hasPublishedAudio,
        true,
        reason: controller.statusMessage,
      );
      expect(controller.document.speakableText, 'Stay close.');
      await controller.completeInitialIntake();
      await controller.startPlayback();
      expect(engine.modelCalls, 0);
      expect(engine.requests, hasLength(1), reason: controller.statusMessage);
      final first = engine.requests.single;
      expect(await File(first.audioPath).exists(), true);
      expect(controller.isPlaying, true);
      final canceled = Completer<void>();
      final next = await first.continuation!.next(
        first.rangeSequence,
        canceled.future,
      );
      expect(next!.startWordIndex, 2);
      next.onRangeActive!();
      expect(controller.document.speakableText, 'Wait here.');
      expect(
        await next.continuation!.next(next.rangeSequence, canceled.future),
        isNull,
      );
      final output = await controller.exportDocumentToPath(
        '${temp.path}/published.radoc',
      );
      expect(output, isNotNull, reason: controller.statusMessage);
      final check = RadocAudioPackage();
      final book = await check.open(output!);
      expect(book.manifest.renderingComplete, true);
      expect(book.manifest.preparedRanges, hasLength(2));
      expect(book.manifest.scenes, hasLength(2));
      await check.dispose();
      await controller.importFilePaths([output.path]);
      expect(
        controller.hasPublishedAudio,
        true,
        reason: controller.statusMessage,
      );
      await controller.startPlayback();
      expect(engine.requests, hasLength(2), reason: controller.statusMessage);
      expect(engine.modelCalls, 0);
    },
  );
  test('native scene joins preserve paragraph source equivalence', () async {
    await controller.importFilePaths([
      (await fixture(paragraphBreak: true)).path,
    ]);
    expect(controller.document.speakableText, contains('\n'));
    await controller.startPlayback();
    expect(engine.requests, hasLength(1), reason: controller.statusMessage);
    expect(engine.modelCalls, 0);
  });
  test('changed source words still demand rendering', () async {
    await controller.importFilePaths([
      (await fixture(paragraphBreak: true, changedSource: true)).path,
    ]);
    await controller.startPlayback();
    expect(engine.requests, isEmpty);
    expect(engine.modelCalls, 1);
  });
  test(
    'missing middle scene stops at the next saved span in the same range',
    () async {
      engine.renderAvailable = true;
      await controller.importFilePaths([(await fixture(middleGap: true)).path]);
      await controller.startPlayback();
      final first = engine.requests.single;
      final middle = await first.continuation!.next(
        0,
        Completer<void>().future,
      );
      expect(engine.exports, hasLength(1));
      final chunk = engine.exports.single.chunkPlan!.chunks.single;
      expect(chunk.startWordIndex, 2);
      expect(chunk.endWordIndex, 4);
      expect(middle!.text, 'Wait here.');
      final last = await middle.continuation!.next(1, Completer<void>().future);
      expect(last!.text, 'Keep quiet.');
      expect(engine.exports, hasLength(1));
    },
  );
  test(
    'partial book gap cannot be reported as EOF and demands model on resume',
    () async {
      await controller.importFilePaths([
        (await fixture(secondAudio: false)).path,
      ]);
      await controller.startPlayback();
      final request = engine.requests.single;
      await expectLater(
        request.continuation!.next(0, Completer<void>().future),
        throwsStateError,
      );
      expect(engine.modelCalls, 1);
      await controller.startPlayback();
      expect(engine.modelCalls, 2);
      expect(controller.statusMessage, contains('needs rendering'));
      expect(engine.requests, hasLength(1));
    },
  );
  test(
    'republish preserves unread later Character evidence and explicit voice',
    () async {
      await controller.importFilePaths([
        (await fixture(lateCharacter: true)).path,
      ]);
      expect(controller.characterCastRegistry.forCastId('late-mara'), isNull);
      final output = await controller.exportDocumentToPath(
        '${temp.path}/unread-save.radoc',
      );
      expect(output, isNotNull, reason: controller.statusMessage);
      await controller.importFilePaths([output!.path]);
      final later = await controller.readPreparedRange(2);
      final character = later!.fragment.characterCastRegistry.forCastId(
        'late-mara',
      );
      expect(character, isNotNull);
      expect(
        character!.explicitGender.value,
        CharacterGenderIdentityLabel.female,
      );
      expect(character.selectedVoice.mode, VoiceSelectionMode.explicit);
      expect(character.selectedVoice.voiceId, 'other');
      expect(character.selectedVoice.revision, 2);
      expect(engine.modelCalls, 0);
    },
  );
  test(
    'changed direction renders one bounded scene and reuses following audio',
    () async {
      engine.renderAvailable = true;
      await controller.importFilePaths([
        (await fixture(staleDirections: true, paragraphBreak: true)).path,
      ]);
      await controller.startPlayback();
      expect(engine.exports, hasLength(1), reason: controller.statusMessage);
      final export = engine.exports.single;
      expect(export.chunkPlan!.chunks, hasLength(1));
      expect(export.chunkPlan!.nextSegmentId, isNull);
      expect(export.chunkPlan!.chunks.single.speakText, 'Stay. Close.');
      expect(engine.requests, hasLength(1), reason: controller.statusMessage);
      final first = engine.requests.single;
      final next = await first.continuation!.next(0, Completer<void>().future);
      expect(next!.text, 'Wait here.');
      expect(await File(next.audioPath).readAsBytes(), _wav());
      expect(engine.exports, hasLength(1));
      await controller.pausePlayback();
      engine.renderAvailable = false;
      await controller.importFilePaths([(await fixture()).path]);
      await controller.startPlayback();
      expect(engine.exports, hasLength(1));
    },
  );
  test(
    'historical boundary inside a prepared segment refuses rendering',
    () async {
      engine.renderAvailable = true;
      await controller.importFilePaths([
        (await fixture(historicalEndInsideSegment: true)).path,
      ]);
      await controller.startPlayback();
      expect(controller.statusMessage, contains('inside a prepared segment'));
      expect(engine.exports, isEmpty);
      expect(engine.requests, isEmpty);
      expect(controller.isPlaying, isFalse);
      expect(controller.hasPendingPlaybackIntent, isFalse);
      await controller.importFilePaths([(await fixture()).path]);
      await controller.startPlayback();
      expect(engine.exports, isEmpty);
      expect(engine.requests, hasLength(1));
      expect(engine.requests.single.isCurrent!(), isTrue);
    },
  );

  test('one Play survives the demanded published-engine handoff', () async {
    final old = _OfflineEngine();
    final replacement = _OfflineEngine()..renderAvailable = true;
    final c = ReaderController(
      ttsEngine: old,
      engineFactory: (id, _) {
        expect(id, 'fish_drama3');
        return replacement;
      },
      deferInitialSynthesis: true,
      enablePlatformIntakeChannels: false,
      renderedSceneRepository: RenderedSceneRepository(
        Directory('${temp.path}/handoff'),
      ),
    );
    try {
      await c.initialize();
      await c.importFilePaths([
        (await fixture(
          staleDirections: true,
          publishedEngine: 'fish_drama3',
        )).path,
      ]);
      await c.startPlayback();
      expect(replacement.exports, hasLength(1), reason: c.statusMessage);
      expect(replacement.requests, hasLength(1), reason: c.statusMessage);
      expect(old.modelCalls, 0);
      expect(c.runningTtsEngineId, 'fish_drama3');
    } finally {
      await c.shutdownPreparation();
      c.dispose();
    }
  });
  test('Save Audio Book produces v5 before any scene is rendered', () async {
    await controller.importPastedText('A book awaiting its first reading.');
    if (!controller.hasCompleteDocumentSnapshot) {
      final complete = Completer<void>();
      void changed() {
        if (controller.hasCompleteDocumentSnapshot && !complete.isCompleted) {
          complete.complete();
        }
      }

      controller.addListener(changed);
      try {
        await complete.future.timeout(const Duration(seconds: 3));
      } finally {
        controller.removeListener(changed);
      }
    }
    final output = await controller.exportDocumentToPath(
      '${temp.path}/unrendered.radoc',
      audioBook: true,
    );
    expect(output, isNotNull, reason: controller.statusMessage);
    final transport = RadocAudioPackage();
    try {
      final book = await transport.open(output!);
      expect(book.manifest.preparationComplete, true);
      expect(book.manifest.renderingComplete, false);
      expect(book.manifest.scenes, isEmpty);
      expect(book.manifest.totalWords, 6);
    } finally {
      await transport.dispose();
    }
    expect(engine.modelCalls, 0);
  });
  test('replacement rejects an old scene continuation', () async {
    final file = await fixture();
    await controller.importFilePaths([file.path]);
    await controller.startPlayback();
    final request = engine.requests.single;
    await controller.importFilePaths([file.path]);
    expect(request.isCurrent!(), false);
    await expectLater(
      request.continuation!.next(0, Completer<void>().future),
      throwsA(anything),
    );
    expect(engine.requests, hasLength(1));
  });
  test(
    'newly saved missing passage reopens without its source files or model',
    () async {
      final file = await fixture(secondAudio: false);
      final audio = await File('${temp.path}/new.wav').writeAsBytes(_wav());
      final saved = await repository.publish(
        TtsFinalizedAudioScene(
          documentId: 'ephemeral',
          generationId: 'ephemeral',
          sceneId: 'ephemeral',
          text: 'Wait here.',
          engineSpeakText: 'Wait here.',
          startWordIndex: 2,
          endWordIndex: 4,
          startOffset: 0,
          sceneTurns: [],
          preparedBindings: [],
          audioPath: audio.path,
          duration: const Duration(milliseconds: 10),
          engineId: 'fixture',
          engineVersion: 'fixture-v1',
          normalizationVersion: 'fixture-v1',
          capabilityProfileId: 'fixture-v1',
          synthesisIdentity: 'fixture',
          translationSignature: 'fixture',
          synthesisRate: 1,
          assignmentRevision: 1,
          cancelled: Completer<void>().future,
          isCurrent: () => true,
        ),
        sourceId: 'source',
        intent: {
          'defaultVoiceId': 'published',
          'multiVoice': true,
          'rate': 1.0,
        },
      );
      await audio.delete();
      await controller.importFilePaths([file.path]);
      await controller.startPlayback();
      final first = engine.requests.single;
      final next = await first.continuation!.next(0, Completer<void>().future);
      expect(next!.audioPath, saved.audioPath);
      expect(next.startWordIndex, 2);
      expect(
        await next.continuation!.next(1, Completer<void>().future),
        isNull,
      );
      expect(engine.modelCalls, 0);
    },
  );
  test(
    'changed canonical direction invalidates saved audio before admission',
    () async {
      await controller.importFilePaths([
        (await fixture(staleDirections: true)).path,
      ]);
      await controller.startPlayback();
      expect(engine.modelCalls, 1);
      expect(engine.requests, isEmpty);
      expect(controller.statusMessage, contains('needs rendering'));
    },
  );
  test('missing opening packet plays before complete publication', () async {
    engine.renderAvailable = true;
    engine.packetGate = Completer<void>();
    await controller.importFilePaths([
      (await fixture(staleDirections: true)).path,
    ]);
    await controller.startPlayback().timeout(const Duration(seconds: 3));
    final opening = engine.requests.single;
    expect(opening.audioPacket, isNotNull);
    expect(opening.startWordIndex, 0);
    expect(opening.endWordIndex, 2);
    expect(engine.packetGate!.isCompleted, false);
    expect(await repository.sceneStartingAt('source', 0), isNull);
    final next = opening.continuation!.next(0, Completer<void>().future);
    engine.packetGate!.complete();
    final saved = await next.timeout(const Duration(seconds: 3));
    expect(saved!.audioPacket, isNull);
    expect(saved.startWordIndex, 2);
    expect((await opening.sceneCompletion!).packetCount, 1);
  });

  test(
    'later prepared range streams with global source bounds and gated EOF',
    () async {
      engine.renderAvailable = true;
      engine.packetGate = Completer<void>();
      await controller.importFilePaths([
        (await fixture(secondAudio: false)).path,
      ]);
      await controller.startPlayback();
      final prefix = engine.requests.single;
      final cancellation = Completer<void>();
      final missing = await prefix.continuation!
          .next(0, cancellation.future)
          .timeout(const Duration(seconds: 3));
      expect(missing!.audioPacket, isNotNull);
      expect(missing.startWordIndex, 2);
      expect(missing.endWordIndex, 4);
      final end = missing.continuation!.next(
        missing.rangeSequence,
        cancellation.future,
      );
      var ended = false;
      unawaited(end.then((_) => ended = true));
      await Future<void>.delayed(Duration.zero);
      expect(ended, false);
      engine.packetGate!.complete();
      expect(await end.timeout(const Duration(seconds: 3)), isNull);
    },
  );
  test(
    'late render failure cannot become packet EOF or persisted success',
    () async {
      engine.renderAvailable = true;
      engine.packetGate = Completer<void>();
      engine.failAfterPacket = true;
      await controller.importFilePaths([
        (await fixture(staleDirections: true)).path,
      ]);
      await controller.startPlayback();
      final opening = engine.requests.single;
      final next = opening.continuation!.next(0, Completer<void>().future);
      final rejected = expectLater(next, throwsStateError);
      engine.packetGate!.complete();
      await rejected;
      expect(await repository.sceneStartingAt('source', 0), isNull);
    },
  );

  test('replacement cancels and drains a held packet producer', () async {
    engine.renderAvailable = true;
    engine.packetGate = Completer<void>();
    final file = await fixture(staleDirections: true);
    await controller.importFilePaths([file.path]);
    await controller.startPlayback();
    final old = engine.requests.single;
    await controller
        .importFilePaths([file.path])
        .timeout(const Duration(seconds: 3));
    expect(old.isCurrent!(), false);
    expect(engine.requests, hasLength(1));
    expect(await repository.sceneStartingAt('source', 0), isNull);
  });

  test('changed default voice does not play the old saved identity', () async {
    await controller.importFilePaths([(await fixture()).path]);
    await controller.selectVoiceById('other');
    expect(engine.modelCalls, 0);
    await controller.startPlayback();
    expect(engine.modelCalls, 1);
    expect(engine.requests, isEmpty);
  });
}

class _OfflineEngine
    implements TtsEngine, RenderedAudioPlaybackCapable, AudioExportCapable {
  int modelCalls = 0;
  bool renderAvailable = false;
  Completer<void>? packetGate;
  bool failAfterPacket = false;
  final exports = <TtsExportRequest>[];
  final requests = <TtsRenderedAudioRequest>[];
  @override
  void Function()? onStart;
  @override
  void Function(String?)? onStatus;
  @override
  void Function(TtsProgressUpdate)? onProgress;
  @override
  void Function()? onComplete;
  @override
  void Function(String)? onError;
  @override
  void Function(TtsPlaybackActivity)? onActivity;
  @override
  void Function(TtsDebugTraceSnapshot)? onDebugTrace;
  @override
  Future<void> initialize() async {
    modelCalls++;
    if (!renderAvailable) throw StateError('No installed model');
  }

  @override
  Future<List<VoiceProfile>> loadVoices() async => [
    for (final id in ['published', 'other'])
      VoiceProfile(id: id, label: id, locale: 'en-US', rawValue: const {}),
  ];
  @override
  Future<void> selectVoice(VoiceProfile voice) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    exports.add(request);
    final chunk = request.chunkPlan!.chunks.single;
    await File(request.outputPath).writeAsBytes(_wav());
    Completer<TtsRenderedSceneCompletion>? packetCompletion;
    if (packetGate != null) {
      packetCompletion = Completer<TtsRenderedSceneCompletion>();
      unawaited(
        packetCompletion.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      await request.onPlayablePacket!(
        TtsPlayableAudioPacket(
          packet: SpeechAudioPacket(
            sessionId: request.sessionId!,
            generationId: 'export-test',
            chunkId: chunk.chunkId,
            audioPath: request.outputPath,
            packetIndex: 0,
            frameStart: 0,
            frameCount: 240,
            sampleRate: 24000,
          ),
          sceneId: chunk.chunkId,
          text: chunk.speakText,
          startWordIndex: request.sourceWordOffset + chunk.startWordIndex,
          endWordIndex: request.sourceWordOffset + chunk.endWordIndex,
          startOffset: 0,
          sceneTurns: const [],
          sceneCompletion: packetCompletion.future,
        ),
      );
      await Future.any([packetGate!.future, request.cancelled!]);
      if (request.isCurrent?.call() == false || failAfterPacket) {
        final error = StateError('Packet render failed or became obsolete.');
        packetCompletion.completeError(error);
        throw error;
      }
    }
    await request.onRenderedScene!(
      TtsFinalizedAudioScene(
        documentId: request.documentId!,
        generationId: 'export-test',
        sceneId: chunk.chunkId,
        text: chunk.speakText,
        engineSpeakText: chunk.speakText,
        startWordIndex: request.sourceWordOffset + chunk.startWordIndex,
        endWordIndex: request.sourceWordOffset + chunk.endWordIndex,
        startOffset: 0,
        sceneTurns: [],
        preparedBindings: [],
        audioPath: request.outputPath,
        duration: const Duration(milliseconds: 10),
        engineId: 'kokoro',
        engineVersion: '2',
        normalizationVersion: request.normalizationVersion!,
        capabilityProfileId: 'test',
        synthesisIdentity: 'test',
        translationSignature: 'test',
        synthesisRate: 1,
        assignmentRevision: request.assignmentRevision,
        cancelled: request.cancelled!,
        isCurrent: request.isCurrent!,
      ),
    );
    packetCompletion?.complete(
      TtsRenderedSceneCompletion(
        sceneId: chunk.chunkId,
        frameCount: 240,
        packetCount: 1,
        duration: const Duration(milliseconds: 10),
        onsetTrimFrames: 0,
      ),
    );
    return TtsExportResult(
      outputPath: request.outputPath,
      sidecarPath: '${request.outputPath}.json',
      duration: const Duration(milliseconds: 10),
      chunkCount: 1,
      voiceId: 'published',
      rate: 1,
      engineId: 'kokoro',
      engineVersion: '2',
    );
  }

  @override
  Future<void> playRendered(TtsRenderedAudioRequest request) async {
    requests.add(request);
    request.onPlaybackReady?.call(
      RenderedAudioPlaybackAcknowledgment(
        documentId: request.documentId,
        manifestIdentity: request.manifestIdentity,
        intentRevision: request.intentRevision,
        generationId: 'test',
      ),
    );
    request.onRangeActive?.call();
    onStart?.call();
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    modelCalls++;
    throw StateError('Unexpected synthesis call ${invocation.memberName}');
  }
}

Uint8List _wav() {
  final b = ByteData(44 + 480);
  void tag(int i, String s) {
    for (var k = 0; k < s.length; k++) {
      b.setUint8(i + k, s.codeUnitAt(k));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, b.lengthInBytes - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, 24000, Endian.little);
  b.setUint32(28, 48000, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, 480, Endian.little);
  return b.buffer.asUint8List();
}
