import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/character.dart';
import 'package:read_aloud/src/models/reader_operation.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/models/native_speech_turn.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/chunk_plan.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/base_speech_annotation_inference_service.dart';
import 'package:read_aloud/src/services/document_preparation_supervisor.dart';
import 'package:read_aloud/src/services/reader_document_repository.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';
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
import 'package:read_aloud/src/services/synthesis_boundary_policy.dart';
import 'package:read_aloud/src/services/speech_planning_supervisor.dart';

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
      final openingOperation = controller.feedbackOperations.singleWhere(
        (p) => p.scope == 'Open audio book',
      );
      expect(openingOperation.state, OperationState.succeeded);
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
      expect(
        controller.feedbackOperations
            .where((p) => p.scope == 'Save audio book')
            .single
            .state,
        OperationState.succeeded,
      );
      expect(
        controller.feedbackOperations.where(
          (p) => p.scope == 'Read audio book member',
        ),
        isNotEmpty,
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
  testWidgets(
    'saved-book Settings names deferred loading and explicitly loads without Play',
    (tester) async {
      await tester.runAsync(() async {
        await controller.importFilePaths([(await fixture()).path]);
        await controller.completeInitialIntake();
        // Finish the tiny fixture's real package read before fake-clock UI work.
        await controller.readPreparedRange(2);
      });
      expect(controller.engineSession.phase.name, 'deferred');
      expect(controller.isInitializing, isFalse);
      expect(controller.engineSession.active, isNull);
      expect(engine.modelCalls, 0);
      engine.renderAvailable = true;
      await tester.pumpWidget(ReadAloudApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reader-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Speech model is not loaded yet.'),
        findsOneWidget,
      );
      expect(find.text('Cancel speech engine preparation'), findsNothing);
      final load = find.text('Load selected speech engine');
      expect(load, findsOneWidget);
      await tester.ensureVisible(load);
      await tester.tap(load);
      await tester.pumpAndSettle();
      expect(engine.modelCalls, 1);
      expect(controller.engineSession.phase.name, 'active');
      expect(controller.engineSession.active, isNotNull);
      expect(controller.hasPublishedAudio, isTrue);
      expect(controller.document.speakableText, 'Stay close.');
      expect(engine.requests, isEmpty);
      expect(engine.exports, isEmpty);
      expect(find.text('Load selected speech engine'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controller.shutdownPreparation);
    },
  );
  testWidgets(
    'failed Save has inline Clear, retains diagnostics and retries by identity',
    (tester) async {
      await tester.runAsync(() async {
        await controller.importFilePaths([(await fixture()).path]);
        final blocker = await File(
          '${temp.path}/not-a-directory',
        ).writeAsString('blocked');
        expect(
          await controller.exportDocumentToPath('${blocker.path}/book.radoc'),
          isNull,
        );
      });
      final failure = controller.feedbackOperations.singleWhere(
        (p) => p.scope == 'Save audio book',
      );
      expect(failure.state, OperationState.failed);
      expect(failure.error, isNotEmpty);
      expect(failure.recoveryActions, [OperationRecoveryAction.clear]);
      expect(controller.statusOwnedByInlineFailure, isTrue);
      await tester.pumpWidget(ReadAloudApp(controller: controller));
      await tester.pump();
      expect(find.byKey(const Key('clear-operation-failure')), findsOneWidget);
      expect(find.byKey(const Key('status-toast')), findsNothing);

      // Even identical text from another status owner remains a separate toast.
      final sameText = controller.statusMessage!;
      controller.showStatusMessage(sameText);
      await tester.pump();
      expect(controller.statusOwnedByInlineFailure, isFalse);
      expect(find.byKey(const Key('status-toast')), findsOneWidget);

      final readerPosition = tester.getTopLeft(
        find.byKey(const Key('reader-surface-shell')),
      );
      await tester.tap(find.byKey(const Key('clear-operation-failure')));
      await tester.pump();
      expect(find.byKey(const Key('clear-operation-failure')), findsNothing);
      expect(controller.statusMessage, sameText);
      expect(find.byKey(const Key('status-toast')), findsOneWidget);
      await controller.clearStatus();
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const Key('reader-surface-shell'))),
        readerPosition,
      );
      final cleared = controller.feedbackOperations.singleWhere(
        (p) => p.key == failure.key,
      );
      expect(cleared.state, OperationState.failed);
      expect(cleared.error, failure.error);
      expect(cleared.readerBlocking, isFalse);
      await tester.tap(find.byKey(const Key('toggle-activity')));
      await tester.pump();
      expect(
        find.text('Saving prepared document · Save audio book · failed'),
        findsOneWidget,
      );
      expect(find.text(failure.error!), findsOneWidget);

      // An old control callback cannot clear a newer attempt in the same lane.
      final retry = controller.beginReadingStage(
        PreparationStage.persistence,
        producerId: 'audio-book-package',
        scope: 'Save audio book',
      );
      controller.publishReadingStage(
        retry,
        const PreparationProgress(
          stage: PreparationStage.persistence,
          state: PreparationWorkState.failed,
          completed: 0,
          unit: 'members',
          error: 'New failure',
        ),
      );
      controller.clearFeedbackFailure(failure);
      expect(
        controller.feedbackOperations
            .singleWhere((p) => p.error == 'New failure')
            .readerBlocking,
        isTrue,
      );
      // A real Save retries with its own linked identity and succeeds.
      await tester.runAsync(() async {
        expect(
          await controller.exportDocumentToPath('${temp.path}/retried.radoc'),
          isNotNull,
        );
      });
      final successful = controller.feedbackOperations.singleWhere(
        (p) =>
            p.scope == 'Save audio book' && p.state == OperationState.succeeded,
      );
      expect(successful.operationId, isNot(failure.operationId));
      expect(successful.retryOf, isNotNull);
      expect(engine.modelCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final unrelatedStatus in [false, true]) {
    testWidgets(
      unrelatedStatus
          ? 'retry Save begins without clearing unrelated identical status'
          : 'retry Save without Clear retires its failure status before success',
      (tester) async {
        await tester.pumpWidget(ReadAloudApp(controller: controller));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await controller.importFilePaths([(await fixture()).path]);
          final blocker = await File(
            '${temp.path}/not-a-directory',
          ).writeAsString('blocked');
          expect(
            await controller.exportDocumentToPath('${blocker.path}/book.radoc'),
            isNull,
          );
        });
        final failure = controller.feedbackOperations.singleWhere(
          (operation) => operation.scope == 'Save audio book',
        );
        final failedStatus = controller.statusMessage!;
        expect(controller.statusOwnedByInlineFailure, isTrue);
        if (unrelatedStatus) controller.showStatusMessage(failedStatus);
        await tester.pump();

        late Completer<void> started;
        late Completer<void> release;
        await tester.runAsync(() async {
          started = Completer<void>();
          release = Completer<void>();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('read_aloud/document_access'),
                (call) async {
                  if (call.method != 'createRadocExportStage') {
                    throw MissingPluginException();
                  }
                  started.complete();
                  await release.future;
                  return (await Directory(
                    '${temp.path}/retry-stage',
                  ).create()).path;
                },
              );
        });
        late Future<File?> retry;
        try {
          await tester.runAsync(() async {
            retry = controller.exportDocumentToPath(
              '${temp.path}/retried.radoc',
            );
            await started.future.timeout(const Duration(seconds: 3));
          });
          await tester.pump();
          final active = controller.feedbackOperations.singleWhere(
            (operation) =>
                operation.scope == failure.scope && !operation.state.isTerminal,
          );
          expect(active.operationId, isNot(failure.operationId));
          expect(active.retryOf, failure.operationId);
          expect(
            controller.statusMessage,
            unrelatedStatus ? failedStatus : null,
          );
          expect(
            find.byKey(const Key('status-toast')),
            unrelatedStatus ? findsOneWidget : findsNothing,
          );
          if (unrelatedStatus) {
            controller.showStatusMessage('A newer unrelated status.');
            await tester.pump();
            expect(controller.statusMessage, 'A newer unrelated status.');
          }
        } finally {
          release.complete();
          await tester.runAsync(() async {
            expect(await retry, isNotNull, reason: controller.statusMessage);
          });
        }
        await tester.pump();
        expect(
          controller.feedbackOperations
              .singleWhere(
                (operation) =>
                    operation.scope == failure.scope &&
                    operation.state == OperationState.succeeded,
              )
              .retryOf,
          failure.operationId,
        );
        // Successful Save retains its existing success notification policy.
        expect(
          controller.statusMessage,
          'Saved audio book to ${temp.path}/retried.radoc.',
        );
        expect(controller.statusMessage, isNot(failedStatus));
        expect(find.byKey(const Key('status-toast')), findsOneWidget);
        expect(engine.modelCalls, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
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
  for (final terminal in ['pause', 'document', 'selection']) {
    test(
      'published engine handoff rejects later $terminal before readiness',
      () async {
        final held = _HeldBookEngine()..renderAvailable = true;
        final last = _OfflineEngine()..renderAvailable = true;
        final c = ReaderController(
          ttsEngine: _OfflineEngine(),
          engineFactory: (id, _) => id == 'fish_drama3' ? held : last,
          deferInitialSynthesis: true,
          enablePlatformIntakeChannels: false,
          renderedSceneRepository: RenderedSceneRepository(
            Directory('${temp.path}/handoff-$terminal'),
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
          final play = c.startPlayback();
          await held.started.future;
          final cancellation = switch (terminal) {
            'pause' => c.pausePlayback(),
            'document' => c.importPastedText('Replacement document.'),
            _ => c.setTtsEngineId('fish_drama3_4bit'),
          };
          held.release.complete();
          await Future.wait([play, cancellation]);
          expect(held.exports, isEmpty);
          expect(held.requests, isEmpty);
          expect(last.exports, isEmpty);
          expect(last.requests, isEmpty);
        } finally {
          await c.shutdownPreparation();
          c.dispose();
        }
      },
    );
  }

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

  Future<File> legacyFishFixture({String? defect}) async {
    const path = 'test/fixtures/s11_fish_legacy';
    final json =
        jsonDecode(await File('$path/manifest.json').readAsString())
            as Map<String, dynamic>;
    final members = <String, File>{
      'prepared/1.json': File('$path/prepared.json'),
    };
    if (defect == 'attribution') {
      final prepared =
          jsonDecode(await members['prepared/1.json']!.readAsString()) as Map;
      (prepared['documentVoiceAttribution'] as Map)['ranges'] = [];
      members['prepared/1.json'] = await File(
        '${temp.path}/no-attribution.json',
      ).writeAsString(jsonEncode(prepared));
    }
    String? predecessor;
    for (final (i, value) in (json['scenes'] as List).indexed) {
      final scene = value as Map<String, dynamic>;
      final bytes = _boundaryWav(sample: 1000 + i);
      // Long leading silence and an audible plateau exercise actual boundary
      // trimming after a changed predecessor, independently of speech quality.
      (scene['format'] as Map)['sampleRate'] = 24000;
      (scene['format'] as Map)['frameCount'] = (bytes.length - 44) ~/ 2;
      final rawId = 'wav-sha256:${sha256.convert(bytes)}';
      final provenance = scene['provenance'] as Map;
      provenance['rawArtifactIdentity'] = rawId;
      provenance['predecessorRawArtifactIdentity'] = predecessor;
      provenance['trailingSilenceMicros'] = 100000;
      (scene['dependencies'] as Map)['predecessorRawArtifactIdentity'] =
          predecessor;
      scene['dependencyDigest'] = artifactIdentity(scene['dependencies']);
      predecessor = rawId;
      final audio = await File(
        '${temp.path}/legacy-$i.wav',
      ).writeAsBytes(bytes);
      members[scene['audioMember'] as String] = audio;
      members[scene['rawAudioMember'] as String] = audio;
      if (i == 0) {
        final provenance = scene['provenance'] as Map;
        if (defect == 'binding') provenance['bindings'] = [];
        if (defect == 'precision') {
          (provenance['intent'] as Map)['engineId'] = 'fish_drama3_4bit';
        }
      }
    }
    final package = RadocAudioPackage();
    try {
      final output = File('${temp.path}/legacy-fish.radoc');
      await package.export(
        destination: output,
        manifest: RadocAudioManifest.fromJson(json),
        members: members,
      );
      return output;
    } finally {
      await package.dispose();
    }
  }

  Future<ReaderController> fishController(
    _OfflineEngine owner, {
    String preference = 'fish_drama3_8bit',
    TtsEngine Function(String, int)? engineFactory,
    bool deferInitialSynthesis = true,
    DocumentPreparationSupervisor? preparationSupervisor,
  }) async {
    SharedPreferences.setMockInitialValues({'reader.ttsEngineId': preference});
    final c = ReaderController(
      ttsEngine: owner,
      engineFactory: engineFactory,
      preparationSupervisor: preparationSupervisor,
      deferInitialSynthesis: deferInitialSynthesis,
      enablePlatformIntakeChannels: false,
      renderedSceneRepository: RenderedSceneRepository(
        Directory('${temp.path}/fish-scenes'),
      ),
    );
    addTearDown(() async {
      await c.shutdownPreparation();
      c.dispose();
    });
    await c.initialize();
    return c;
  }

  Future<void> loadFreshExportSource(ReaderController c) async {
    // Only the public fixture's source text is imported: no saved audio or
    // prepared book metadata supplies the scenes under test.
    final fixture =
        jsonDecode(
              await File(
                'test/fixtures/s11_fish_legacy/prepared.json',
              ).readAsString(),
            )
            as Map;
    await c.loadDocument(
      DocumentImportService().importPastedText(
        fixture['speakableText'] as String,
      ),
    );
  }

  test(
    'fresh whole-source export persists every window into a reusable book',
    () async {
      final owner = _WholeSourceExportEngine();
      final c = await fishController(owner, deferInitialSynthesis: false);
      await loadFreshExportSource(c);
      final words = c.document.wordCount;
      final result = await c.exportAudioToPath('${temp.path}/fresh.wav');
      expect(result, isNotNull, reason: c.statusMessage);
      expect(
        owner.exports.length,
        greaterThan(3),
        reason: 'Exercise later planning windows.',
      );
      expect(owner.requests, isEmpty, reason: 'Saving must not start speech.');
      expect(owner.synthesisRequests, isEmpty);
      final request = owner.wholeRequests.single;
      expect(request.sourceWordOffset, 0);
      final output = await c.exportDocumentToPath(
        '${temp.path}/fresh.radoc',
        audioBook: true,
      );
      expect(output, isNotNull, reason: c.statusMessage);
      final package = RadocAudioPackage();
      try {
        final book = await package.open(output!);
        expect(book.manifest.renderingComplete, true);
        expect(book.manifest.scenes, hasLength(owner.exports.length));
        var end = 0;
        for (final (i, scene) in book.manifest.scenes.indexed) {
          final rendered = owner.exports[i];
          final chunk = rendered.chunkPlan!.chunks.single;
          expect(scene.startWord, end);
          expect(scene.endWord, chunk.endWordIndex);
          end = scene.endWord;
          expect(scene.rawAudioMember, isNotNull);
          final raw = await package.materializeMember(
            book,
            scene.rawAudioMember!,
          );
          final finalAudio = await package.materializeMember(
            book,
            scene.audioMember,
          );
          expect(
            await raw.readAsBytes(),
            await File('${rendered.outputPath}.raw.wav').readAsBytes(),
          );
          expect(
            await finalAudio.readAsBytes(),
            await File(rendered.outputPath).readAsBytes(),
          );
          expect(
            (scene.dependencies['raw'] as Map)['engineId'],
            'fish_drama3_8bit',
          );
          expect(
            scene.provenance['rawArtifactIdentity'],
            startsWith('wav-sha256:'),
          );
          expect(scene.provenance['bindings'], isNotEmpty);
          expect(
            (scene.provenance['intent'] as Map)['engineId'],
            'fish_drama3_8bit',
          );
          expect(
            (scene.provenance['sceneTurns'] as List).single['startWord'],
            scene.startWord,
          );
        }
        expect(end, words);
      } finally {
        await package.dispose();
      }
      final renderedCount = owner.exports.length;
      expect(
        request.assignmentRevision,
        c.voiceAssignmentState.requestedRevision,
      );
      expect(
        request.isCurrent!(),
        false,
        reason: 'A returned export has retired.',
      );
      await c.importFilePaths([output.path]);
      await c.startPlayback();
      var playing = owner.requests.last;
      var sequence = 0;
      while (true) {
        final next = await playing.continuation!.next(
          sequence++,
          Completer<void>().future,
        );
        if (next == null) break;
        playing = next;
      }
      expect(
        owner.exports,
        hasLength(renderedCount),
        reason: 'Reopen reuses every export scene.',
      );
      await c.pausePlayback();
      await c.assignVoiceToCast('cast_character_mara', 'other');
      await c.startPlayback();
      playing = owner.requests.last;
      sequence = 0;
      while (true) {
        final next = await playing.continuation!.next(
          sequence++,
          Completer<void>().future,
        );
        if (next == null) break;
        playing = next;
      }
      final regenerated = owner.exports.skip(renderedCount).toList();
      expect(
        regenerated.map(
          (r) => (
            r.chunkPlan!.chunks.single.startWordIndex,
            r.chunkPlan!.chunks.single.endWordIndex,
          ),
        ),
        [(8, 15), (26, 30)],
        reason: 'Fresh export metadata retains exact Character ownership.',
      );
      expect(
        regenerated.every((r) => r.chunkPlan!.chunks.single.voiceId == 'other'),
        true,
      );
      await c.pausePlayback();
      final edited = await c.exportDocumentToPath(
        '${temp.path}/fresh-edited.radoc',
        audioBook: true,
      );
      expect(edited, isNotNull, reason: c.statusMessage);
      final afterEdit = owner.exports.length;
      await c.importFilePaths([edited!.path]);
      await c.startPlayback();
      playing = owner.requests.last;
      sequence = 0;
      while (true) {
        final next = await playing.continuation!.next(
          sequence++,
          Completer<void>().future,
        );
        if (next == null) break;
        playing = next;
      }
      expect(
        owner.exports,
        hasLength(afterEdit),
        reason: 'Edited export scenes also survive save/reopen.',
      );
      await c.pausePlayback();
    },
  );

  test(
    'whole-source export from a later range keeps complete canonical coordinates',
    () async {
      final failures = <Object?>[];
      PlaybackInstrumentationService.instance.observer = (m) {
        if (m.metric == 'audioExportFailed') failures.add(m.value);
      };
      addTearDown(
        () => PlaybackInstrumentationService.instance.observer = null,
      );
      final owner = _WholeSourceExportEngine();
      final source = _DirectedRangeSource(
        ReaderDocumentRepository('${temp.path}/ranges'),
      );
      final c = await fishController(
        owner,
        preparationSupervisor: source,
        deferInitialSynthesis: false,
      );
      await c.importPastedText('Stay close. Wait here.');
      await c.startPlayback();
      final first = owner.synthesisRequests.single;
      final next = await first.continuation!.next(
        first.rangeSequence,
        Completer<void>().future,
      );
      next!.onRangeActive!();
      await next.continuation!.next(
        next.rangeSequence,
        Completer<void>().future,
      );
      await _until(() => c.hasCompleteDocumentSnapshot);
      expect(c.document.speakableText, 'Wait here.');
      await c.pausePlayback();
      expect(
        await c.exportAudioToPath('${temp.path}/all-ranges.wav'),
        isNotNull,
        reason: '${c.statusMessage} $failures',
      );
      expect(owner.wholeRequests.single.text, contains('Stay close.'));
      expect(owner.wholeRequests.single.text, contains('Wait here.'));
      expect(owner.wholeRequests.single.sourceWordOffset, 0);
      final reader = RenderedSceneRepository(
        Directory('${temp.path}/fish-scenes'),
      );
      try {
        final scenes = await reader.scenesForSource(
          source.request.effectiveSourceRevision,
        );
        expect(scenes.first.startWordIndex, 0);
        expect(scenes.last.endWordIndex, 4);
        final directions = scenes
            .expand(
              (s) => (s.intent['canonicalDirections'] as List).cast<Map>(),
            )
            .toList();
        expect(
          directions.map((d) => (d['startWord'], d['endWord'], d['delivery'])),
          [(0, 2, 'whispered'), (2, 4, 'shouted')],
        );
      } finally {
        await reader.dispose();
      }
    },
  );

  for (final terminal in ['document', 'voice', 'rate', 'cancel']) {
    test(
      'whole-source export rejects late $terminal scene and keeps committed prefix',
      () async {
        final owner = _WholeSourceExportEngine()..holdAfterFirst = true;
        final c = await fishController(owner, deferInitialSynthesis: false);
        await loadFreshExportSource(c);
        final source = c.document.normalizedImportResult.sourceFingerprint;
        final exporting = c.exportAudioToPath('${temp.path}/obsolete.wav');
        await owner.held.future;
        expect(owner.exports, hasLength(1));
        switch (terminal) {
          case 'document':
            await c.loadDocument(
              DocumentImportService().importPastedText('New owner.'),
            );
          case 'voice':
            await c.selectVoiceById('other');
          case 'rate':
            await c.setVoiceSpeed(1.2);
          case 'cancel':
            owner.cancelled.complete();
        }
        c.showStatusMessage('New owner status');
        owner.release.complete();
        expect(await exporting, isNull);
        if (terminal != 'cancel') expect(c.statusMessage, 'New owner status');
        expect(owner.requests, isEmpty);
        // The fake deliberately delivers an obsolete callback. The controller
        // writer and repository must independently reject it before admission.
        final reader = RenderedSceneRepository(
          Directory('${temp.path}/fish-scenes'),
        );
        try {
          final scenes = await reader.scenesForSource(source);
          expect(scenes, hasLength(1));
          expect(scenes.single.startWordIndex, 0);
        } finally {
          await reader.dispose();
        }
      },
    );
  }

  test(
    'legacy Fish character edit regenerates only Mara and survives save/reopen',
    () async {
      final owner = _ScopedOfflineEngine('fish_drama3_8bit')
        ..renderAvailable = true;
      final c = await fishController(owner);
      await c.importFilePaths([(await legacyFishFixture()).path]);
      await c.assignVoiceToCast('cast_character_mara', 'library_fishadrian');
      await c.startPlayback();
      expect(owner.requests, hasLength(1), reason: c.statusMessage);
      var request = owner.requests.single;
      var sequence = 0;
      final admitted = <int>[];
      while (true) {
        admitted.add(request.startWordIndex);
        final next = await request.continuation!.next(
          sequence++,
          Completer<void>().future,
        );
        if (next == null) break;
        request = next;
      }
      expect(admitted, [0, 8, 15, 17, 24, 26, 30]);
      expect(
        owner.exports.map(
          (r) => (
            r.chunkPlan!.chunks.single.startWordIndex,
            r.chunkPlan!.chunks.single.endWordIndex,
          ),
        ),
        [(8, 15), (26, 30)],
      );
      expect(
        owner.exports.every(
          (r) => r.chunkPlan!.chunks.single.voiceId == 'library_fishadrian',
        ),
        true,
      );
      await c.pausePlayback();
      final output = await c.exportDocumentToPath(
        '${temp.path}/edited-fish.radoc',
        audioBook: true,
      );
      expect(output, isNotNull, reason: c.statusMessage);
      final package = RadocAudioPackage();
      try {
        final book = await package.open(output!);
        expect(
          (book.manifest.intent['characterSelections']
              as Map)['cast_character_mara'],
          'library_fishadrian',
        );
        expect(book.manifest.scenes, hasLength(7));
        final original =
            jsonDecode(
                  await File(
                    'test/fixtures/s11_fish_legacy/manifest.json',
                  ).readAsString(),
                )
                as Map;
        for (final (i, scene) in book.manifest.scenes.indexed) {
          final file = await package.materializeMember(book, scene.audioMember);
          final raw = await package.materializeMember(
            book,
            scene.rawAudioMember!,
          );
          final rawBytes = _boundaryWav(
            sample: [1, 5].contains(i) ? 777 : 1000 + i,
          );
          expect(await raw.readAsBytes(), rawBytes);
          if ([0, 3, 4].contains(i)) {
            expect(await file.readAsBytes(), rawBytes);
          } else {
            expect(
              (await file.length()),
              lessThan(rawBytes.length),
              reason:
                  'Native boundary policy must trim the fixture\'s long onset.',
            );
          }
          if ([2, 6].contains(i)) {
            final historical = (original['scenes'] as List)[i] as Map;
            expect(
              scene.dependencies['raw'],
              (historical['dependencies'] as Map)['raw'],
            );
            expect(
              scene.provenance['bindings'],
              (historical['provenance'] as Map)['bindings'],
            );
            expect(
              scene.provenance['intent'],
              (historical['provenance'] as Map)['intent'],
            );
            expect(
              scene.provenance['predecessorRawArtifactIdentity'],
              'wav-sha256:${sha256.convert(_boundaryWav(sample: 777))}',
            );
          }
        }
      } finally {
        await package.dispose();
      }
      await c.importFilePaths([output.path]);
      await c.startPlayback();
      request = owner.requests.last;
      sequence = 0;
      while (true) {
        final next = await request.continuation!.next(
          sequence++,
          Completer<void>().future,
        );
        if (next == null) break;
        request = next;
      }
      expect(
        owner.exports,
        hasLength(2),
        reason: 'Saved edited scenes must be reusable.',
      );
      final store = RenderedSceneRepository(
        Directory('${temp.path}/fish-scenes'),
      );
      try {
        final scenes = await store.scenesForSource('synthetic-s3-dialogue');
        expect(
          scenes.map((s) => s.startWordIndex),
          [8, 15, 26, 30],
          reason:
              'Only two syntheses and their two immediate boundary dependents are republished.',
        );
        expect(
          Directory('${temp.path}/fish-scenes/scenes')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.json')),
          hasLength(4),
          reason: 'Reopen must not publish another derivative or synthesis.',
        );
      } finally {
        await store.dispose();
      }
    },
  );

  for (final defect in ['binding', 'precision', 'attribution']) {
    test(
      'legacy Fish refuses missing or mismatched $defect ownership evidence',
      () async {
        final owner = _ScopedOfflineEngine('fish_drama3_8bit')
          ..renderAvailable = true;
        final c = await fishController(owner);
        await c.importFilePaths([
          (await legacyFishFixture(defect: defect)).path,
        ]);
        await c.startPlayback();
        expect(c.statusMessage, contains('lacks unambiguous voice ownership'));
        expect(owner.exports, isEmpty);
        expect(owner.requests, isEmpty);
      },
    );
  }

  for (final preference in ['kokoro', 'fish_drama3_4bit']) {
    test(
      'later legacy Fish demand hands $preference to published Fish8 with one Play',
      () async {
        final old = _ScopedOfflineEngine(preference)..renderAvailable = true;
        final replacement = _ScopedOfflineEngine('fish_drama3_8bit')
          ..renderAvailable = true;
        final c = await fishController(
          old,
          preference: preference,
          engineFactory: (id, _) {
            expect(id, 'fish_drama3_8bit');
            return replacement;
          },
        );
        await c.importFilePaths([(await legacyFishFixture()).path]);
        await c.assignVoiceToCast('cast_character_mara', 'library_fishadrian');
        await c.startPlayback();
        expect(old.requests.single.startWordIndex, 0);
        expect(old.modelCalls, 0);
        final consumerExited = Completer<void>();
        final consumptionRequested = Completer<void>();
        final consumed = Completer<void>();
        old.consumerDrain = consumerExited.future;
        // Real engine shutdown joins its owned continuation. A handoff that
        // awaits replacement from inside that same continuation would deadlock.
        final demand = old.requests.single.continuation!
            .demandNext(
              0,
              Completer<void>().future,
              awaitConsumed: () {
                consumptionRequested.complete();
                return consumed.future;
              },
            )
            .whenComplete(() {
              if (!consumerExited.isCompleted) consumerExited.complete();
            });
        try {
          await consumptionRequested.future;
          expect(replacement.modelCalls, 0);
          expect(
            old.requests.single.isCurrent!(),
            isTrue,
            reason: 'Prefetch must not retire an inaudible prefix.',
          );
          consumed.complete();
          await expectLater(
            demand.timeout(const Duration(seconds: 3)),
            throwsA(isA<PlanningCancelled>()),
          );
        } finally {
          if (!consumerExited.isCompleted) consumerExited.complete();
        }
        await _until(() => replacement.requests.isNotEmpty);
        expect(replacement.requests.single.startWordIndex, 8);
        var request = replacement.requests.single;
        var sequence = 0;
        while (true) {
          final next = await request.continuation!.next(
            sequence++,
            Completer<void>().future,
          );
          if (next == null) break;
          request = next;
        }
        expect(old.exports, isEmpty);
        expect(
          replacement.exports.map(
            (r) => r.chunkPlan!.chunks.single.startWordIndex,
          ),
          [8, 26],
        );
        expect(
          replacement.exports.first.predecessorRawArtifactIdentity,
          'wav-sha256:${sha256.convert(_boundaryWav(sample: 1000))}',
        );
        expect(
          replacement.exports.first.predecessorTrailingSilence,
          const Duration(milliseconds: 100),
        );
        expect(c.runningTtsEngineId, 'fish_drama3_8bit');
        await c.pausePlayback();
        final output = await c.exportDocumentToPath(
          '${temp.path}/handoff-edited.radoc',
          audioBook: true,
        );
        expect(output, isNotNull, reason: c.statusMessage);
        await c.importFilePaths([output!.path]);
        await c.startPlayback();
        request = replacement.requests.last;
        sequence = 0;
        while (true) {
          final next = await request.continuation!.next(
            sequence++,
            Completer<void>().future,
          );
          if (next == null) break;
          request = next;
        }
        expect(
          replacement.exports,
          hasLength(2),
          reason: 'Handoff output must survive saving and reopening.',
        );
      },
    );
  }

  test(
    'explicit engine change after book open is not replaced by published engine',
    () async {
      final old = _ScopedOfflineEngine('kokoro');
      final explicit = _ScopedOfflineEngine('fish_drama3_4bit')
        ..renderAvailable = true;
      final selected = <String>[];
      final c = await fishController(
        old,
        preference: 'kokoro',
        engineFactory: (id, _) {
          selected.add(id);
          return explicit;
        },
      );
      await c.importFilePaths([(await legacyFishFixture()).path]);
      await c.assignVoiceToCast('cast_character_mara', 'library_fishadrian');
      await c.setTtsEngineId('fish_drama3_4bit');
      await c.startPlayback();
      expect(selected, ['fish_drama3_4bit']);
      expect(
        explicit.exports.single.chunkPlan!.chunks.single.startWordIndex,
        0,
      );
      expect(c.runningTtsEngineId, 'fish_drama3_4bit');
    },
  );

  for (final terminal in ['pause', 'document', 'selection']) {
    test(
      'prefetched handoff rejects $terminal before prefix consumption',
      () async {
        final old = _ScopedOfflineEngine('kokoro');
        final target = _ScopedOfflineEngine('fish_drama3_8bit')
          ..renderAvailable = true;
        final explicit = _ScopedOfflineEngine('fish_drama3_4bit')
          ..renderAvailable = true;
        final selections = <String>[];
        final c = await fishController(
          old,
          preference: 'kokoro',
          engineFactory: (id, _) {
            selections.add(id);
            return id == 'fish_drama3_8bit' ? target : explicit;
          },
        );
        await c.importFilePaths([(await legacyFishFixture()).path]);
        await c.assignVoiceToCast('cast_character_mara', 'library_fishadrian');
        await c.startPlayback();
        final entered = Completer<void>();
        final consumed = Completer<void>();
        final cancelled = Completer<void>();
        final demand = old.requests.single.continuation!.demandNext(
          0,
          cancelled.future,
          awaitConsumed: () {
            entered.complete();
            return consumed.future;
          },
        );
        final failure = expectLater(demand, throwsA(isA<PlanningCancelled>()));
        await entered.future;
        expect(selections, isEmpty);
        switch (terminal) {
          case 'pause':
            await c.pausePlayback();
          case 'document':
            await c.importPastedText('Replacement document.');
          case 'selection':
            await c.setTtsEngineId('fish_drama3_4bit');
        }
        if (terminal == 'pause') {
          cancelled.complete();
        } else {
          consumed.complete();
        }
        await failure;
        expect(
          selections,
          terminal == 'selection' ? ['fish_drama3_4bit'] : isEmpty,
        );
        expect(target.requests, isEmpty);
        expect(target.exports, isEmpty);
        expect(explicit.requests, isEmpty);
        expect(explicit.exports, isEmpty);
      },
    );

    test(
      'later published-engine handoff rejects $terminal during preparation',
      () async {
        final old = _ScopedOfflineEngine('kokoro');
        final held = _HeldScopedBookEngine()..renderAvailable = true;
        final last = _ScopedOfflineEngine('fish_drama3_4bit')
          ..renderAvailable = true;
        final c = await fishController(
          old,
          preference: 'kokoro',
          engineFactory: (id, _) => id == 'fish_drama3_8bit' ? held : last,
        );
        await c.importFilePaths([(await legacyFishFixture()).path]);
        await c.assignVoiceToCast('cast_character_mara', 'library_fishadrian');
        await c.startPlayback();
        await expectLater(
          old.requests.single.continuation!.demandNext(
            0,
            Completer<void>().future,
            awaitConsumed: () async {},
          ),
          throwsA(isA<PlanningCancelled>()),
        );
        await held.started.future;
        final cancellation = switch (terminal) {
          'pause' => c.pausePlayback(),
          'document' => c.importPastedText('Replacement document.'),
          _ => c.setTtsEngineId('fish_drama3_4bit'),
        };
        held.release.complete();
        await cancellation;
        await _until(() => !c.isInitializing && !c.hasPendingPlaybackIntent);
        expect(held.exports, isEmpty);
        expect(held.requests, isEmpty);
        expect(last.exports, isEmpty);
        expect(last.requests, isEmpty);
      },
    );
  }

  test(
    'legacy two-argument consumer cannot hand off without playback evidence',
    () async {
      final old = _ScopedOfflineEngine('kokoro');
      final target = _ScopedOfflineEngine('fish_drama3_8bit')
        ..renderAvailable = true;
      final c = await fishController(
        old,
        preference: 'kokoro',
        engineFactory: (_, _) => target,
      );
      await c.importFilePaths([(await legacyFishFixture()).path]);
      await c.assignVoiceToCast('cast_character_mara', 'library_fishadrian');
      await c.startPlayback();
      await expectLater(
        old.requests.single.continuation!.next(0, Completer<void>().future),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('confirm consumed audio'),
          ),
        ),
      );
      expect(old.requests.single.isCurrent!(), true);
      expect(target.exports, isEmpty);
      expect(target.modelCalls, 0);
    },
  );
}

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out awaiting book owner');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _OfflineEngine
    implements TtsEngine, RenderedAudioPlaybackCapable, AudioExportCapable {
  int modelCalls = 0;
  bool renderAvailable = false;
  bool fishPublication = false;
  String fishEngineId = 'fish_drama3_8bit';
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
    for (final id in [
      'published',
      'other',
      'library_fishadrian',
      'library_fishfreya',
      'library_fishhannah',
    ])
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
    final binding = PreparedVoiceBinding(
      voiceId: chunk.voiceId,
      voiceDigest: 'fixture-${chunk.voiceId}',
      modelDigest: 'fixture-$fishEngineId-model',
      engineVersion: _fishFixtureEngineVersion,
      pronunciationProfileId: 'en-us-core',
      bindingRevision: 1,
      documentId: request.documentId!,
    );
    File? rawFile;
    String? rawIdentity;
    Duration duration = const Duration(milliseconds: 10);
    if (fishPublication) {
      final bytes = _boundaryWav(sample: 777);
      rawFile = await File('${request.outputPath}.raw.wav').writeAsBytes(bytes);
      rawIdentity = 'wav-sha256:${sha256.convert(bytes)}';
      final correction = const SynthesisBoundaryPolicy().correctWavFileSync(
        chunkId: chunk.chunkId,
        wavFilePath: rawFile.path,
        boundaryClass: chunk.boundaryClass,
        isInitialChunk: request.predecessorRawArtifactIdentity == null,
        isResumedChunk: false,
        previousArtifactIdentity: request.predecessorRawArtifactIdentity,
        previousTrailingSilence: request.predecessorTrailingSilence,
      );
      duration = correction.duration;
      await File(request.outputPath).writeAsBytes(
        await File(correction.audioPath ?? rawFile.path).readAsBytes(),
      );
    } else {
      await File(request.outputPath).writeAsBytes(_wav());
    }
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
    await request.onRenderedScene?.call(
      TtsFinalizedAudioScene(
        documentId: request.documentId!,
        generationId: 'export-test',
        sceneId: chunk.chunkId,
        text: chunk.speakText,
        engineSpeakText: chunk.speakText,
        startWordIndex: request.sourceWordOffset + chunk.startWordIndex,
        endWordIndex: request.sourceWordOffset + chunk.endWordIndex,
        startOffset: 0,
        sceneTurns: fishPublication
            ? [
                NativeSpeechTurn(
                  voiceId: chunk.voiceId,
                  text: chunk.speakText,
                  segmentIds: chunk.segmentIds,
                  startWord: request.sourceWordOffset + chunk.startWordIndex,
                  endWord: request.sourceWordOffset + chunk.endWordIndex,
                  bindingFingerprint: binding.fingerprint,
                  bindingRevision: 1,
                  castId: chunk.castId,
                ),
              ]
            : [],
        preparedBindings: fishPublication ? [binding] : [],
        audioPath: request.outputPath,
        duration: duration,
        engineId: fishPublication ? fishEngineId : 'kokoro',
        engineVersion: fishPublication ? _fishFixtureEngineVersion : '2',
        normalizationVersion: request.normalizationVersion!,
        capabilityProfileId: fishPublication
            ? '$fishEngineId:macos:v1'
            : 'test',
        synthesisIdentity: 'test',
        translationSignature: 'test',
        synthesisRate: 1,
        assignmentRevision: request.assignmentRevision,
        cancelled: request.cancelled!,
        isCurrent: request.isCurrent!,
        rawAudioPath: rawFile?.path,
        rawArtifactIdentity: rawIdentity,
        predecessorRawArtifactIdentity: request.predecessorRawArtifactIdentity,
        boundaryPolicyVersion: fishPublication
            ? SynthesisBoundaryPolicy.version
            : null,
        boundaryClass: fishPublication ? chunk.boundaryClass.name : null,
        trailingSilenceMicros: fishPublication ? 100000 : null,
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

const _fishFixtureEngineVersion =
    'mlx-audio-0.6.3-mlx-0.32.4-complete-v3-q0-native-cast-v1';

Uint8List _boundaryWav({required int sample}) =>
    _wav(sample: sample, frames: 12000, leading: 7200, trailing: 2400);

Uint8List _wav({
  int sample = 0,
  int frames = 240,
  int leading = 0,
  int trailing = 0,
}) {
  final b = ByteData(44 + frames * 2);
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
  b.setUint32(40, frames * 2, Endian.little);
  for (var i = 44; i < b.lengthInBytes; i += 2) {
    final frame = (i - 44) ~/ 2;
    b.setInt16(
      i,
      frame >= leading && frame < frames - trailing ? sample : 0,
      Endian.little,
    );
  }
  return b.buffer.asUint8List();
}

class _HeldBookEngine extends _OfflineEngine {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> initialize() async {
    started.complete();
    await release.future;
    await super.initialize();
  }
}

class _ScopedOfflineEngine extends _OfflineEngine
    implements TtsEngineIdentityCapable {
  _ScopedOfflineEngine(String id) {
    fishEngineId = id;
    fishPublication = id.startsWith('fish_drama3');
  }
  @override
  String get engineId => fishEngineId;
  @override
  String get engineVersion => fishPublication ? _fishFixtureEngineVersion : '2';
  Future<void>? consumerDrain;
  @override
  Future<void> stop() async => await consumerDrain;
}

class _HeldScopedBookEngine extends _ScopedOfflineEngine {
  _HeldScopedBookEngine() : super('fish_drama3_8bit');
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> initialize() async {
    started.complete();
    await release.future;
    await super.initialize();
  }
}

// Controller/repository plumbing evidence, not acoustic or native inference
// evidence. Reuse the existing per-scene WAV fixture and real bounded planner.
class _WholeSourceExportEngine extends _ScopedOfflineEngine {
  _WholeSourceExportEngine() : super('fish_drama3_8bit') {
    renderAvailable = true;
  }
  final wholeRequests = <TtsExportRequest>[];
  final synthesisRequests = <TtsSpeakRequest>[];
  final cancelled = Completer<void>();
  final held = Completer<void>();
  final release = Completer<void>();
  bool holdAfterFirst = false;
  @override
  Future<void> speak(TtsSpeakRequest request) async {
    synthesisRequests.add(request);
    request.onPlaybackReady?.call(
      TtsPlaybackAcknowledgment(
        documentId: request.documentId!,
        assignmentRevision: request.assignmentRevision,
        generationId: 'controller-test',
        bindingFingerprints: const {},
      ),
    );
  }

  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    wholeRequests.add(request);
    final planner = SpeechPlanningSupervisor();
    var plan = request.chunkPlan!;
    TtsExportResult? result;
    try {
      while (true) {
        for (final chunk in plan.chunks) {
          if (holdAfterFirst && exports.length == 1 && !held.isCompleted) {
            held.complete();
            await release.future;
          }
          result = await super.exportAudio(
            TtsExportRequest(
              text: chunk.speakText,
              outputPath: '${request.outputPath}.${exports.length}.wav',
              documentId: request.documentId,
              sessionId: request.sessionId,
              normalizationVersion: request.normalizationVersion,
              chunkPlan: ChunkPlan(planId: plan.planId, chunks: [chunk]),
              onRenderedScene: request.onRenderedScene,
              assignmentRevision: request.assignmentRevision,
              sourceWordOffset: request.sourceWordOffset,
              cancelled: cancelled.future,
              isCurrent: () =>
                  !cancelled.isCompleted && (request.isCurrent?.call() ?? true),
            ),
          );
          if (cancelled.isCompleted || request.isCurrent?.call() == false) {
            throw StateError('Export cancelled or superseded.');
          }
        }
        final next = plan.nextSegmentId;
        if (next == null) break;
        plan = (await planner.plan(
          request.planningContext!,
          startSegmentId: next,
        )).plan;
      }
      return result!;
    } finally {
      await planner.shutdown();
    }
  }
}

// A two-range source seam with real immutable checkpoint commits. This keeps
// the offset regression small while exercising the production complete merge.
class _DirectedRangeSource extends DocumentPreparationSupervisor {
  _DirectedRangeSource(ReaderDocumentRepository repository)
    : super(repository: repository);
  late DocumentPreparationRequest request;
  @override
  Future<DocumentPreparationResult> prepareRanges(
    DocumentPreparationRequest request, {
    Future<Uint8List> Function()? acquireBytes,
    String? cacheKey,
    Future<void> Function(DocumentIdentityMigration)? onIdentityMigration,
    required Future<void> Function(DocumentPreparationPublication)
    onPublication,
    void Function(PreparationProgress)? onProgress,
    void Function(CharacterDiscoveryPublication)? onCharacterDiscovery,
    Future<void> Function()? acquireSource,
    Future<void> Function()? onDrained,
  }) async {
    this.request = request.identityOnly;
    final checkpoint = await repository!.begin(
      sourceKey: cacheKey!,
      request: request,
    );
    ReaderDocument? last;
    var sourceOffset = 0;
    for (final (i, text) in ['Stay close.', 'Wait here.'].indexed) {
      final doc = DocumentImportService().importPastedText(text);
      final segment = doc.speechDocument.segments.first;
      last = ReaderDocument.fromNormalized(
        title: doc.title,
        type: doc.type,
        normalizedImportResult: doc.normalizedImportResult,
        dialogueAttributions: doc.dialogueAttributions,
        characterCastRegistry: doc.characterCastRegistry,
        documentVoiceAttribution: doc.documentVoiceAttribution,
        basePronunciationArtifacts: doc.basePronunciationArtifacts,
        baseSpeechAnnotations: const BaseSpeechAnnotationInferenceService()
            .infer(
              speechDocument: doc.speechDocument,
              displayDocument: doc.displayDocument,
              explicitIntents: [
                SpeechAnnotation(
                  annotationId: 'direction-$i',
                  segmentId: segment.segmentId,
                  kind: SpeechAnnotationKind.deliveryIntent,
                  startWord: 0,
                  endWord: 2,
                  confidence: 1,
                  source: SpeechAnnotationSource.userOverride,
                  deliveryIntent: i == 0
                      ? DeliveryIntent.whispered
                      : DeliveryIntent.shouted,
                ),
              ],
            ),
      );
      const codec = ReaderDocumentSerializationService();
      var encoded = codec.serializeToJsonString(last);
      for (final segment in last.speechDocument.segments) {
        encoded = encoded.replaceAll(
          '"${segment.segmentId}"',
          '"range${i}_${segment.segmentId}"',
        );
      }
      for (final block in last.displayDocument.blocks) {
        encoded = encoded.replaceAll(
          '"${block.blockId}"',
          '"range${i}_${block.blockId}"',
        );
      }
      for (final range in last.documentVoiceAttribution.ranges) {
        encoded = encoded.replaceAll(
          '"${range.rangeId}"',
          '"range${i}_${range.rangeId}"',
        );
      }
      last = codec.deserializeFromJsonString(encoded);
      final publication = DocumentPreparationPublication(
        request: request.identityOnly,
        sequence: i + 1,
        fragment: last,
        range: PreparedDocumentRange(
          sourceStart: sourceOffset,
          sourceEnd: sourceOffset + text.length,
          wordStart: i * 2,
          wordEnd: i * 2 + 2,
          segmentStart: i,
          segmentEnd: i + 1,
        ),
        coverage: const {
          PreparationStage.normalization,
          PreparationStage.mapping,
          PreparationStage.analysis,
          PreparationStage.pronunciation,
        },
        progress: const [],
        isLast: false,
      );
      sourceOffset += text.length;
      await checkpoint.commit(publication);
      await onPublication(publication);
    }
    await checkpoint.complete();
    return DocumentPreparationResult(
      request: request.identityOnly,
      outcome: DocumentPreparationOutcome.ready,
      document: last,
    );
  }
}
