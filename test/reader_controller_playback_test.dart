import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/reading_focus_state.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/models/reader_resume_state.dart';
import 'package:read_aloud/src/models/spoken_chunk_record.dart';
import 'package:read_aloud/src/models/spoken_selection.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';
import 'dart:io';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PlaybackInstrumentationService.instance.clear();
  });

  group('ReaderController playback', () {
    test('tracks primary playback state through buffering, playing, and completion', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText('Alpha beta. Gamma delta.');
      await controller.startPlayback();

      expect(
        controller.playbackState,
        ReaderPlaybackPrimaryState.bufferingFirstChunk,
      );
      expect(controller.statusMessage, isNull);

      engine.emitStart();
      expect(controller.playbackState, ReaderPlaybackPrimaryState.playing);

      final documentId = controller.document.displayDocument.documentId;
      final lastSegment = controller.document.speechDocument.segments.last;
      engine.emitProgress(
        TtsProgressUpdate(
          startOffset: 0,
          endOffset: controller.document.speakableText.length,
          word: 'delta',
          documentId: documentId,
          chunkId: 'chunk-complete',
          segmentId: lastSegment.segmentId,
          wordStartIndex: controller.document.wordCount - 1,
          wordEndIndex: controller.document.wordCount,
          elapsedInChunk: const Duration(seconds: 2),
          chunkAudioDuration: const Duration(seconds: 2),
          voiceId: controller.selectedVoice!.id,
          rate: controller.currentSpeed,
        ),
      );
      engine.emitComplete();

      expect(controller.playbackState, ReaderPlaybackPrimaryState.completed);
    });

    test('uses completed chunk records for timing and snaps jumps to segment starts', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText(
        'Alpha beta. Gamma delta. Epsilon zeta.',
      );
      await controller.startPlayback();
      engine.emitStart();

      final documentId = controller.document.displayDocument.documentId;
      final segments = controller.document.speechDocument.segments;
      final voiceId = controller.selectedVoice!.id;

      engine.emitProgress(
        TtsProgressUpdate(
          startOffset: 0,
          endOffset: 10,
          word: 'beta',
          documentId: documentId,
          chunkId: 'chunk-1',
          segmentId: segments[0].segmentId,
          wordStartIndex: 0,
          wordEndIndex: 2,
          elapsedInChunk: const Duration(seconds: 2),
          chunkAudioDuration: const Duration(seconds: 2),
          voiceId: voiceId,
          rate: controller.currentSpeed,
          routeId: 'route_narration_open',
          castId: 'cast_narrator',
        ),
      );
      engine.emitProgress(
        TtsProgressUpdate(
          startOffset: 11,
          endOffset: 22,
          word: 'delta',
          documentId: documentId,
          chunkId: 'chunk-2',
          segmentId: segments[1].segmentId,
          wordStartIndex: 2,
          wordEndIndex: 4,
          elapsedInChunk: const Duration(seconds: 2),
          chunkAudioDuration: const Duration(seconds: 2),
          voiceId: voiceId,
          rate: controller.currentSpeed,
          routeId: 'route_dialogue_jennifer',
          castId: 'cast_character_jennifer',
          dialogueSpanId: 'dlg_s_1',
        ),
      );

      expect(controller.wordsPerSecond, closeTo(1.0, 0.001));
      expect(
        controller.spokenChunkRecords.any((record) => record.chunkId == 'chunk-1' && record.completed),
        isTrue,
      );
      final dialogueRecord = controller.spokenChunkRecords.firstWhere(
        (record) => record.chunkId == 'chunk-2',
      );
      expect(dialogueRecord.routeId, 'route_dialogue_jennifer');
      expect(dialogueRecord.castId, 'cast_character_jennifer');
      expect(dialogueRecord.dialogueSpanId, 'dlg_s_1');
      expect(controller.spokenSelection.precision, SpokenSelectionPrecision.word);
      expect(controller.spokenSelection.routeId, 'route_dialogue_jennifer');
      expect(controller.spokenSelection.castId, 'cast_character_jennifer');
      expect(controller.spokenSelection.dialogueSpanId, 'dlg_s_1');

      await controller.jumpBySeconds(-1);

      expect(controller.currentWordIndex, 2);
    });

    test('records debug playback metrics with session attribution', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText('Alpha beta. Gamma delta.');
      final sessionId = controller.narrationState.sessionId;
      final documentId = controller.document.displayDocument.documentId;

      await controller.startPlayback();

      final metricsAfterPlay = PlaybackInstrumentationService.instance.snapshot();
      final positionMetric = metricsAfterPlay.firstWhere(
        (record) => record.metric == 'positionMapConfidence',
      );
      expect(positionMetric.documentId, documentId);
      expect(positionMetric.sessionId, sessionId);
      expect(positionMetric.voiceId, controller.selectedVoice!.id);
      expect(positionMetric.engineId, 'generic');

      engine.emitStart();

      final metricsAfterStart = PlaybackInstrumentationService.instance
          .snapshot();
      final latencyMetric = metricsAfterStart.firstWhere(
        (record) => record.metric == 'firstAudioLatencyMs',
      );
      expect(latencyMetric.documentId, documentId);
      expect(latencyMetric.sessionId, sessionId);
      expect(latencyMetric.voiceId, controller.selectedVoice!.id);
      expect(latencyMetric.engineId, 'generic');
      expect(latencyMetric.value, isA<int>());
    });

    test('restores the last heard position for the last opened document', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-restore-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/remembered.txt');
      await file.writeAsString('Alpha beta. Gamma delta. Epsilon zeta.');

      SharedPreferences.setMockInitialValues(<String, Object>{
        'reader.lastOpenedDocumentPath': file.path,
        'reader.lastOpenedDirectoryPath': tempDir.path,
        'reader.resumeState': jsonEncode(
          ReaderResumeState(
            documentPath: file.path,
            wordIndex: 3,
            wordIndexWithinSegment: 1,
            segmentTextAnchor: 'Gamma delta.',
            anchorWordText: 'delta',
          ).toJson(),
        ),
      });

      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      final restored = await controller.restoreLastOpenedDocument();

      expect(restored, isTrue);
      expect(controller.document.title, 'remembered.txt');
      expect(controller.windowTitle, 'Read Aloud - remembered.txt');
      expect(controller.currentWordIndex, 3);
      expect(
        controller.document.speakableText,
        contains('Alpha beta. Gamma delta. Epsilon zeta.'),
      );
      expect(
        controller.statusMessage,
        'Restored remembered.txt near your last heard position.',
      );
    });

    test('persists playback-derived resume state and restores it on startup', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-resume-persist-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/resume.txt');
      await file.writeAsString('Alpha beta. Gamma delta. Epsilon zeta.');

      final firstEngine = _FakeTtsEngine();
      final firstController = ReaderController(ttsEngine: firstEngine);

      await firstController.initialize();
      await firstController.importFilePaths(<String>[file.path]);
      await firstController.startPlayback();
      firstEngine.emitStart();

      final documentId = firstController.document.displayDocument.documentId;
      final secondSegment = firstController.document.speechDocument.segments[1];
      firstEngine.emitProgress(
        TtsProgressUpdate(
          startOffset: 11,
          endOffset: 22,
          word: 'delta',
          documentId: documentId,
          chunkId: 'chunk-resume',
          segmentId: secondSegment.segmentId,
          wordStartIndex: 2,
          wordEndIndex: 4,
          elapsedInChunk: const Duration(seconds: 2),
          chunkAudioDuration: const Duration(seconds: 2),
          voiceId: firstController.selectedVoice!.id,
          rate: firstController.currentSpeed,
        ),
      );
      await firstController.pausePlayback();
      firstController.dispose();

      final secondEngine = _FakeTtsEngine();
      final secondController = ReaderController(ttsEngine: secondEngine);
      addTearDown(secondController.dispose);

      await secondController.initialize();
      final restored = await secondController.restoreLastOpenedDocument();

      expect(restored, isTrue);
      expect(secondController.document.title, 'resume.txt');
      expect(secondController.currentWordIndex, 4);
      expect(
        secondController.statusMessage,
        'Restored resume.txt near your last heard position.',
      );
    });

    test('surfaces debug phoneme trace snapshots from the engine', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();

      engine.emitDebugTrace(
        TtsDebugTraceSnapshot(
          logPath: '/tmp/2026-04-03T01-45-00_af_bella.log',
          startedAt: DateTime.utc(2026, 4, 3, 1, 45),
          voiceId: 'af_bella',
          recentLines: <String>[
            'voiceId: af_bella',
            'trace: plainText text="for the road" prepared="for the road" phonemes="fˈɔɹ ðə ɹˈoʊd"',
          ],
          sessionId: 'session_debug',
        ),
      );

      expect(
        controller.ttsDebugTraceLogPath,
        '/tmp/2026-04-03T01-45-00_af_bella.log',
      );
      expect(controller.ttsDebugTraceVoiceId, 'af_bella');
      expect(
        controller.ttsDebugTraceLines.last,
        contains('phonemes="fˈɔɹ ðə ɹˈoʊd"'),
      );
    });

    test('live read mode reloads the watched file in place', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-live-read-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/live.txt');
      await file.writeAsString('Alpha beta.');

      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.startLiveReadFromPath(file.path);

      expect(controller.isLiveReadEnabled, isTrue);
      expect(controller.liveReadFilePath, file.path);
      expect(controller.document.title, 'live.txt');
      expect(controller.windowTitle, 'Read Aloud - live.txt');
      expect(controller.document.speakableText, contains('Alpha beta.'));

      await file.writeAsString('Gamma delta.');

      for (var attempt = 0; attempt < 20; attempt += 1) {
        if (controller.document.speakableText.contains('Gamma delta.')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(controller.document.speakableText, contains('Gamma delta.'));
      expect(controller.statusMessage, contains('Live read updated'));
    });

    test('live read refresh continues playback when the transport is active', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-live-read-resume-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/live-resume.txt');
      await file.writeAsString('Alpha beta. Gamma delta.');

      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.startLiveReadFromPath(file.path);
      await controller.startPlayback();
      engine.emitStart();

      expect(engine.speakCallCount, 1);
      expect(controller.isPlaying, isTrue);

      await file.writeAsString('Alpha beta. Gamma delta. Epsilon zeta.');

      for (var attempt = 0; attempt < 30; attempt += 1) {
        if (controller.document.speakableText.contains('Epsilon zeta.') &&
            engine.speakCallCount >= 2) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(controller.document.speakableText, contains('Epsilon zeta.'));
      expect(engine.speakCallCount, greaterThanOrEqualTo(2));
      expect(
        controller.playbackState,
        isIn(<ReaderPlaybackPrimaryState>[
          ReaderPlaybackPrimaryState.bufferingFirstChunk,
          ReaderPlaybackPrimaryState.playing,
        ]),
      );
    });

    test('live read refresh stays paused after an explicit user pause', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-live-read-paused-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/live-paused.txt');
      await file.writeAsString('Alpha beta. Gamma delta.');

      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.startLiveReadFromPath(file.path);
      await controller.startPlayback();
      engine.emitStart();
      await controller.pausePlayback();

      expect(engine.speakCallCount, 1);
      expect(controller.isPlaying, isFalse);

      await file.writeAsString('Alpha beta. Gamma delta. Epsilon zeta.');

      for (var attempt = 0; attempt < 30; attempt += 1) {
        if (controller.document.speakableText.contains('Epsilon zeta.')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(controller.document.speakableText, contains('Epsilon zeta.'));
      expect(engine.speakCallCount, 1);
      expect(controller.isPlaying, isFalse);
      expect(controller.playbackState, ReaderPlaybackPrimaryState.idle);
    });

    test('uses document title as the window title fallback for non-file content', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.windowTitle, 'Read Aloud - For Probe');

      await controller.importPastedText('Alpha beta.');

      expect(controller.windowTitle, 'Read Aloud - Pasted Text');
    });

    test('maintains reading focus state across progress, pause, and user yield', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText(
        'Alpha beta. Gamma delta. Epsilon zeta.',
      );
      await controller.startPlayback();
      engine.emitStart();

      final documentId = controller.document.displayDocument.documentId;
      final secondSegment = controller.document.speechDocument.segments[1];
      final voiceId = controller.selectedVoice!.id;

      engine.emitProgress(
        TtsProgressUpdate(
          startOffset: 11,
          endOffset: 22,
          word: 'delta',
          documentId: documentId,
          chunkId: 'chunk-2',
          segmentId: secondSegment.segmentId,
          wordStartIndex: 2,
          wordEndIndex: 4,
          elapsedInChunk: const Duration(seconds: 2),
          chunkAudioDuration: const Duration(seconds: 2),
          voiceId: voiceId,
          rate: controller.currentSpeed,
        ),
      );

      expect(controller.readingFocusState.playbackActive, isTrue);
      expect(
        controller.readingFocusState.followMode,
        ReadingFocusFollowMode.following,
      );
      expect(controller.readingFocusState.activeDisplayBlockId, 'b_0');
      expect(controller.readingFocusState.shouldAutoFollow, isTrue);

      controller.suspendReaderFollow();

      expect(
        controller.readingFocusState.followMode,
        ReadingFocusFollowMode.suspendedByUser,
      );
      expect(controller.readingFocusState.shouldAutoFollow, isFalse);
      expect(controller.readingFocusState.canRecenter, isTrue);

      await controller.pausePlayback();

      expect(controller.readingFocusState.playbackActive, isFalse);
      expect(controller.readingFocusState.activeDisplayBlockId, 'b_0');
      expect(controller.readingFocusState.canRecenter, isTrue);

      controller.resumeReaderFollow();

      expect(
        controller.readingFocusState.followMode,
        ReadingFocusFollowMode.following,
      );
      expect(controller.readingFocusState.canRecenter, isFalse);

      await controller.jumpBySeconds(30);

      expect(controller.readingFocusState.playbackActive, isFalse);
      expect(controller.readingFocusState.activeDisplayBlockId, isNull);
      expect(
        controller.readingFocusState.followMode,
        ReadingFocusFollowMode.following,
      );
    });

    test('builds a multi-voice playback plan with narrator speaker tags and quoted character speech', () async {
      final engine = _FakeTtsEngine(
        voices: const <VoiceProfile>[
          VoiceProfile(
            id: 'af_bella',
            label: 'Bella',
            locale: 'en-US',
            rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
            gender: VoiceGender.female,
          ),
          VoiceProfile(
            id: 'am_michael',
            label: 'Michael',
            locale: 'en-US',
            rawValue: <String, dynamic>{'name': 'Michael', 'locale': 'en-US'},
            gender: VoiceGender.male,
          ),
        ],
      );
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText(
        'John said, "Are you ok?" The room was silent.',
      );

      await controller.startPlayback();

      final request = engine.lastSpeakRequest;
      expect(request, isNotNull);
      final chunkPlan = request!.chunkPlan;
      expect(chunkPlan, isNotNull);

      final chunks = chunkPlan!.chunks;
      expect(chunks.length, greaterThanOrEqualTo(3));
      expect(chunks[0].speakText, 'John said,');
      expect(chunks[0].voiceId, 'af_bella');
      expect(chunks[0].castId, 'cast_narrator');

      expect(chunks[1].speakText, '"Are you ok?"');
      expect(chunks[1].voiceId, 'am_michael');
      expect(chunks[1].castId, 'cast_character_john');
      expect(chunks[1].dialogueSpanId, isNotNull);

      expect(chunks.last.speakText, 'The room was silent.');
      expect(chunks.last.voiceId, 'af_bella');
      expect(chunks.last.castId, 'cast_narrator');
    });

    test('disables cast-aware routing when multi-voice mode is turned off', () async {
      final engine = _FakeTtsEngine(
        voices: const <VoiceProfile>[
          VoiceProfile(
            id: 'af_bella',
            label: 'Bella',
            locale: 'en-US',
            rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
            gender: VoiceGender.female,
          ),
          VoiceProfile(
            id: 'am_michael',
            label: 'Michael',
            locale: 'en-US',
            rawValue: <String, dynamic>{'name': 'Michael', 'locale': 'en-US'},
            gender: VoiceGender.male,
          ),
        ],
      );
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText('John said, "Are you ok?" The room was silent.');

      expect(controller.isMultiVoiceEnabled, isTrue);
      await controller.setMultiVoiceEnabled(false);
      expect(controller.castVoiceAssignments, isNull);

      await controller.startPlayback();

      final request = engine.lastSpeakRequest;
      expect(request, isNotNull);
      final chunkPlan = request!.chunkPlan;
      expect(chunkPlan, isNotNull);
      expect(
        chunkPlan!.chunks.every(
          (chunk) =>
              chunk.voiceId == 'af_bella' &&
              chunk.castId == null &&
              chunk.routeId == null &&
              chunk.dialogueSpanId == null,
        ),
        isTrue,
      );
    });

    test(
      'assigns quoted Jennifer dialogue to a narrator-distinct character voice',
      () async {
        final engine = _FakeTtsEngine(
          voices: const <VoiceProfile>[
            VoiceProfile(
              id: 'af_bella',
              label: 'Bella',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
              gender: VoiceGender.female,
              qualityGrade: 'A-',
            ),
            VoiceProfile(
              id: 'af_heart',
              label: 'Heart',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Heart', 'locale': 'en-US'},
              gender: VoiceGender.female,
              qualityGrade: 'A',
            ),
            VoiceProfile(
              id: 'bf_emma',
              label: 'Emma',
              locale: 'en-GB',
              rawValue: <String, dynamic>{'name': 'Emma', 'locale': 'en-GB'},
              gender: VoiceGender.female,
              qualityGrade: 'B-',
            ),
            VoiceProfile(
              id: 'am_michael',
              label: 'Michael',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Michael', 'locale': 'en-US'},
              gender: VoiceGender.male,
              qualityGrade: 'C+',
            ),
          ],
        );
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText(
          '"JUST STOP FIGHTING!" Jennifer screamed, pulling on her hair.',
        );

        await controller.startPlayback();

        final request = engine.lastSpeakRequest;
        expect(request, isNotNull);
        final chunkPlan = request!.chunkPlan;
        expect(chunkPlan, isNotNull);

        final quoteChunk = chunkPlan!.chunks.firstWhere(
          (chunk) => chunk.speakText == '"JUST STOP FIGHTING!"',
        );
        final narratorChunk = chunkPlan.chunks.firstWhere(
          (chunk) =>
              chunk.speakText == 'Jennifer screamed, pulling on her hair.',
        );

        expect(quoteChunk.castId, 'cast_character_jennifer');
        expect(narratorChunk.castId, 'cast_narrator');
        expect(quoteChunk.voiceId, isNot(narratorChunk.voiceId));
      },
    );

    test(
      'builds alternating narrator and character chunks for quote-tag-quote exchanges',
      () async {
        final engine = _FakeTtsEngine(
          voices: const <VoiceProfile>[
            VoiceProfile(
              id: 'af_bella',
              label: 'Bella',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
              gender: VoiceGender.female,
              qualityGrade: 'A',
            ),
            VoiceProfile(
              id: 'am_michael',
              label: 'Michael',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Michael', 'locale': 'en-US'},
              gender: VoiceGender.male,
              qualityGrade: 'A-',
            ),
            VoiceProfile(
              id: 'bm_fable',
              label: 'Fable',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Fable', 'locale': 'en-US'},
              gender: VoiceGender.male,
              qualityGrade: 'B',
            ),
          ],
        );
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText(
          '"John, why did you have to budge in front of me this morning?" Elliot said '
          '"I dunno. I thought taking someone\'s position in line is how we operate now," '
          'John replied sarcastically.',
        );

        await controller.startPlayback();

        final request = engine.lastSpeakRequest;
        expect(request, isNotNull);
        final chunkPlan = request!.chunkPlan;
        expect(chunkPlan, isNotNull);

        final chunks = chunkPlan!.chunks;
        expect(
          chunks.map((chunk) => chunk.speakText).toList(growable: false),
          containsAllInOrder(<String>[
            '"John, why did you have to budge in front of me this morning?"',
            'Elliot said',
            '"I dunno. I thought taking someone\'s position in line is how we operate now,"',
            'John replied sarcastically.',
          ]),
        );
        expect(
          chunks.map((chunk) => chunk.castId).toList(growable: false),
          containsAllInOrder(<String?>[
            'cast_character_elliot',
            'cast_narrator',
            'cast_character_john',
            'cast_narrator',
          ]),
        );

        final firstQuote = chunks.firstWhere(
          (chunk) =>
              chunk.speakText ==
              '"John, why did you have to budge in front of me this morning?"',
        );
        final narratorTag = chunks.firstWhere(
          (chunk) => chunk.speakText == 'Elliot said',
        );
        final secondQuote = chunks.firstWhere(
          (chunk) =>
              chunk.speakText ==
              '"I dunno. I thought taking someone\'s position in line is how we operate now,"',
        );
        final closingTag = chunks.firstWhere(
          (chunk) => chunk.speakText == 'John replied sarcastically.',
        );

        expect(firstQuote.voiceId, isNot(narratorTag.voiceId));
        expect(secondQuote.voiceId, isNot(closingTag.voiceId));
        expect(narratorTag.voiceId, closingTag.voiceId);
        expect(firstQuote.dialogueSpanId, isNotNull);
        expect(secondQuote.dialogueSpanId, isNotNull);
        expect(narratorTag.dialogueSpanId, isNull);
        expect(closingTag.dialogueSpanId, isNull);
      },
    );

    test('exposes cast-processing state while a multi-voice import is in flight', () async {
      final importer = _DelayedDocumentImporter();
      final controller = ReaderController(
        importer: importer,
        ttsEngine: _FakeTtsEngine(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-cast-processing',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/processing.txt');
      await file.writeAsString('"Hello," John said.');

      final importFuture = controller.importFilePaths(<String>[file.path]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.isImporting, isTrue);
      expect(controller.isCastProcessingVisible, isTrue);
      expect(controller.documentLoadStageLabel, contains('dialogue'));

      importer.complete();
      await importFuture;

      expect(controller.isImporting, isFalse);
      expect(controller.isCastProcessingVisible, isFalse);
    });
  });
}

class _FakeTtsEngine implements TtsEngine {
  _FakeTtsEngine({
    List<VoiceProfile> voices = const <VoiceProfile>[
      VoiceProfile(
        id: 'af_bella',
        label: 'Bella',
        locale: 'en-US',
        rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
      ),
    ],
  }) : _voices = voices;

  final List<VoiceProfile> _voices;

  void Function()? _onStart;
  void Function(String? message)? _onStatus;
  void Function(TtsProgressUpdate update)? _onProgress;
  void Function()? _onComplete;
  void Function(String message)? _onError;
  void Function(TtsPlaybackActivity activity)? _onActivity;
  void Function(TtsDebugTraceSnapshot trace)? _onDebugTrace;
  TtsSpeakRequest? lastSpeakRequest;
  int speakCallCount = 0;

  @override
  set onStart(void Function()? callback) => _onStart = callback;

  @override
  set onStatus(void Function(String? message)? callback) => _onStatus = callback;

  @override
  set onProgress(void Function(TtsProgressUpdate update)? callback) =>
      _onProgress = callback;

  @override
  set onComplete(void Function()? callback) => _onComplete = callback;

  @override
  set onError(void Function(String message)? callback) => _onError = callback;

  @override
  set onActivity(void Function(TtsPlaybackActivity activity)? callback) =>
      _onActivity = callback;

  @override
  set onDebugTrace(void Function(TtsDebugTraceSnapshot trace)? callback) =>
      _onDebugTrace = callback;

  @override
  Future<void> initialize() async {
    _onStatus?.call(null);
    _onActivity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  Future<List<VoiceProfile>> loadVoices() async => _voices;

  @override
  Future<void> selectVoice(VoiceProfile voice) async {}

  @override
  Future<void> setSpeechRate(double multiplier) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> speak(TtsSpeakRequest request) async {
    lastSpeakRequest = request;
    speakCallCount += 1;
    _onActivity?.call(
      const TtsPlaybackActivity(phase: TtsPlaybackPhase.buffering),
    );
  }

  @override
  Future<void> pause() async {
    _onActivity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  Future<void> stop() async {
    _onActivity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  void dispose() {}

  void emitStart() {
    _onActivity?.call(const TtsPlaybackActivity(phase: TtsPlaybackPhase.playing));
    _onStart?.call();
  }

  void emitProgress(TtsProgressUpdate update) {
    _onProgress?.call(update);
  }

  void emitComplete() {
    _onActivity?.call(const TtsPlaybackActivity.idle());
    _onComplete?.call();
  }

  void emitError(String message) {
    _onError?.call(message);
  }

  void emitDebugTrace(TtsDebugTraceSnapshot trace) {
    _onDebugTrace?.call(trace);
  }
}

class _DelayedDocumentImporter extends DocumentImportService {
  _DelayedDocumentImporter();

  final Completer<void> _completer = Completer<void>();

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  @override
  Future<ReaderDocument> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    await _completer.future;
    return ReaderDocument.sample();
  }
}
