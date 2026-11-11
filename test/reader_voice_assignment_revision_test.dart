import 'dart:async';
import 'package:read_aloud/src/services/work_character_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/voice_assignment_state.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/models/reader_appearance_mode.dart';
import 'package:read_aloud/src/models/reader_resume_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<ReaderController> reader(
    _AssignmentEngine engine, {
    ReaderPreferencesService? preferences,
  }) async {
    final controller = ReaderController(
      ttsEngine: engine,
      enablePlatformIntakeChannels: false,
      preferencesService: preferences,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.loadDocument(
      DocumentImportService().importPastedText(
        'Amber birds circle quietly. Blue rivers flow slowly. Golden clouds move onward.',
      ),
    );
    return controller;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(done(), isTrue, reason: 'bounded asynchronous completion');
  }

  test(
    'active B/C edits automatically coalesce at source anchor and require current ack',
    () async {
      final engine = _AssignmentEngine();
      final controller = await reader(engine);
      await controller.startPlayback();
      final original = engine.requests.single;
      engine.acknowledge(original);
      expect(controller.isPlaying, isTrue);
      final stops = engine.stops;
      engine.anchor = TtsPlaybackResumeAnchor(
        documentId: original.documentId!,
        chunkId: 'audible-source',
        startWordIndex: 4,
      );
      final barrier = _Barrier();
      engine.nextStop = barrier;
      await controller.selectVoiceById('af_heart');
      await barrier.started.future;
      await controller.assignVoiceToCast('cast_narrator', 'am_fenrir');
      expect(engine.requests, hasLength(1));
      expect(
        controller.voiceAssignmentState.effectiveDefaultVoiceId,
        'af_bella',
      );
      expect(
        controller.voiceAssignmentState.requestedDefaultVoiceId,
        'af_heart',
      );
      barrier.release.complete();
      await until(() => engine.requests.length == 2);
      expect(engine.stops, greaterThan(stops));
      expect(engine.requests.last.chunkPlan!.chunks.first.voiceId, 'am_fenrir');
      final replacement = engine.requests.last;
      expect(replacement.chunkPlan!.chunks.first.startWordIndex, 4);
      expect(
        controller.voiceAssignmentState.effectiveDefaultVoiceId,
        'af_bella',
      );
      engine.acknowledge(original); // Malicious late success must not commit A.
      expect(controller.voiceAssignmentState.hasPending, isTrue);
      engine.acknowledge(replacement);
      expect(
        controller.voiceAssignmentState.effectiveDefaultVoiceId,
        'af_heart',
      );
      expect(controller.voiceAssignmentState.hasPending, isFalse);
      expect(
        controller.voiceAssignmentState.phase,
        VoiceAssignmentPhase.current,
      );
    },
  );

  for (final fail in [false, true]) {
    test(
      'initial A/B/C coalesces latest after stale A ${fail ? 'failure' : 'success'}',
      () async {
        final engine = _AssignmentEngine();
        final controller = await reader(engine);
        final barrier = _Barrier();
        engine.nextSelection = barrier;
        final starting = controller.startPlayback();
        await barrier.started.future;
        await controller.selectVoiceById('af_heart');
        await controller.selectVoiceById('am_fenrir');
        expect(engine.requests, isEmpty);
        expect(controller.voiceAssignmentState.isInitialBuffering, isTrue);
        if (fail) {
          barrier.release.completeError(StateError('obsolete A failure'));
        } else {
          barrier.release.complete();
        }
        await starting;
        expect(engine.requests, hasLength(1));
        final current = engine.requests.single;
        expect(current.planningContext!.realization.voiceId, 'am_fenrir');
        expect(
          controller.voiceAssignmentState.phase,
          VoiceAssignmentPhase.preparing,
        );
        expect(controller.statusMessage, isNot(contains('obsolete')));
        engine.acknowledge(current);
        expect(
          controller.voiceAssignmentState.effectiveDefaultVoiceId,
          'am_fenrir',
        );
        expect(controller.voiceAssignmentState.hasPending, isFalse);
      },
    );
  }

  test(
    'an already captured export keeps its voices while selection automatically changes playback',
    () async {
      final engine = _AssignmentEngine();
      final controller = await reader(engine);
      await controller.startPlayback();
      engine.acknowledge(engine.requests.single);
      engine.exportBarrier = Completer<TtsExportResult>();
      final exporting = controller.exportAudioToPath('/tmp/effective.wav');
      while (engine.exports.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final captured = engine.exports.single;
      await controller.selectVoiceById('af_heart');
      expect(await controller.exportAudioToPath('/tmp/pending.wav'), isNull);
      expect(engine.exports, hasLength(1));
      engine.exportBarrier!.complete(_result(captured));
      expect(await exporting, isNotNull);
      expect(captured.planningContext!.realization.voiceId, 'af_bella');
      expect(
        controller.voiceAssignmentState.effectiveDefaultVoiceId,
        'af_bella',
      );
      expect(
        controller.voiceAssignmentState.requestedDefaultVoiceId,
        'af_heart',
      );
    },
  );

  test('pause during automatic change cannot revive playback', () async {
    final engine = _AssignmentEngine();
    final controller = await reader(engine);
    await controller.startPlayback();
    engine.acknowledge(engine.requests.single);
    final barrier = _Barrier();
    engine.nextStop = barrier;
    await controller.selectVoiceById('af_heart');
    await barrier.started.future;
    await controller.pausePlayback();
    barrier.release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(engine.requests, hasLength(1));
    expect(controller.isPlaying, isFalse);
    expect(controller.voiceAssignmentState.hasPending, isTrue);
  });

  test(
    'paused pending Play uses retained source anchor; no-edit resume keeps saved word',
    () async {
      final engine = _AssignmentEngine();
      final controller = await reader(engine);
      await controller.startPlayback();
      engine.acknowledge(engine.requests.last);
      engine.anchor = TtsPlaybackResumeAnchor(
        documentId: engine.requests.last.documentId!,
        chunkId: 'current-source',
        startWordIndex: 4,
      );
      engine.progress?.call(
        TtsProgressUpdate(
          startOffset: controller.document.charOffsetForWord(6),
          endOffset: controller.document.charOffsetForWord(7),
          word: 'flow',
          documentId: engine.requests.last.documentId,
        ),
      );
      await controller.pausePlayback();
      final savedWord = controller.currentWordIndex;
      expect(savedWord, 7);
      await controller.startPlayback();
      expect(
        controller.currentWordIndex,
        savedWord,
        reason: 'ordinary resume is unchanged',
      );
      engine.acknowledge(engine.requests.last);
      await controller.pausePlayback();
      await controller.selectVoiceById('af_heart');
      expect(controller.voiceAssignmentState.isInitialBuffering, isFalse);
      await controller.startPlayback();
      expect(controller.currentWordIndex, 4);
      expect(engine.requests.last.chunkPlan!.chunks.first.startWordIndex, 4);
    },
  );

  test(
    'an acknowledged underrun automatically applies the latest selection',
    () async {
      final engine = _AssignmentEngine();
      final controller = await reader(engine);
      await controller.startPlayback();
      engine.acknowledge(engine.requests.last);
      engine.activity?.call(
        const TtsPlaybackActivity(phase: TtsPlaybackPhase.buffering),
      );
      final stops = engine.stops;
      await controller.selectVoiceById('af_heart');
      await until(() => engine.requests.length == 2);
      expect(engine.stops, greaterThan(stops));
      expect(
        engine.requests.last.planningContext!.realization.voiceId,
        'af_heart',
      );
    },
  );

  for (final paused in [false, true]) {
    test(
      'pending edit navigation overrides obsolete pause anchor (paused=$paused)',
      () async {
        final engine = _AssignmentEngine();
        final controller = await reader(engine);
        await controller.startPlayback();
        engine.acknowledge(engine.requests.last);
        engine.anchor = TtsPlaybackResumeAnchor(
          documentId: engine.requests.last.documentId!,
          chunkId: 'old-pause-source',
          startWordIndex: 0,
        );
        await controller.pausePlayback();
        await controller.startPlayback();
        engine.acknowledge(engine.requests.last);
        engine.progress?.call(
          TtsProgressUpdate(
            startOffset: controller.document.charOffsetForWord(8),
            endOffset: controller.document.charOffsetForWord(9),
            word: 'Golden',
            documentId: engine.requests.last.documentId,
          ),
        );
        if (paused) {
          await controller.pausePlayback();
        } else {
          engine.anchor = TtsPlaybackResumeAnchor(
            documentId: engine.requests.last.documentId!,
            chunkId: 'current-source',
            startWordIndex: 8,
          );
        }
        await controller.selectVoiceById('af_heart');
        if (!paused) await until(() => engine.requests.length == 3);
        await controller.jumpBySeconds(1);
        if (paused) {
          await controller.startPlayback();
        }
        expect(engine.requests.last.chunkPlan!.chunks.first.startWordIndex, 8);
      },
    );
  }

  test(
    'current pre-ack failure retains historical effective choices and retry rejects old attempt ack',
    () async {
      final engine = _AssignmentEngine();
      final controller = await reader(engine);
      await controller.startPlayback();
      engine.acknowledge(engine.requests.last);
      engine.anchor = TtsPlaybackResumeAnchor(
        documentId: engine.requests.last.documentId!,
        chunkId: 'audible-source',
        startWordIndex: 4,
      );
      await controller.selectVoiceById('af_heart');
      await until(() => engine.requests.length == 2);
      final failed = engine.requests.last;
      engine.activity?.call(const TtsPlaybackActivity.idle());
      engine.error?.call('current B preparation failed');
      expect(
        controller.voiceAssignmentState.phase,
        VoiceAssignmentPhase.failed,
      );
      expect(
        controller.voiceAssignmentState.effectiveDefaultVoiceId,
        'af_bella',
      );
      expect(controller.voiceAssignmentState.hasPending, isTrue);
      engine.anchor = null;
      await controller.retryVoiceAssignments();
      final retry = engine.requests.last;
      expect(retry.chunkPlan!.chunks.first.startWordIndex, 4);
      engine.acknowledge(failed);
      expect(controller.voiceAssignmentState.hasPending, isTrue);
      engine.acknowledge(retry);
      expect(
        controller.voiceAssignmentState.effectiveDefaultVoiceId,
        'af_heart',
      );
      expect(controller.voiceAssignmentState.hasPending, isFalse);
    },
  );

  for (final paused in [false, true]) {
    test(
      'idle/paused selection does not autoplay and export uses it (paused=$paused)',
      () async {
        final engine = _AssignmentEngine();
        final controller = await reader(engine);
        if (paused) {
          await controller.startPlayback();
          engine.acknowledge(engine.requests.single);
          await controller.pausePlayback();
        }
        final count = engine.requests.length;
        await controller.selectVoiceById('af_heart');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(engine.requests.length, count);
        expect(controller.isPlaying, isFalse);
        expect(
          await controller.exportAudioToPath('/tmp/selected.wav'),
          isNotNull,
        );
        expect(
          engine.exports.single.planningContext!.realization.voiceId,
          'af_heart',
        );
        expect(engine.requests.length, count);
      },
    );
  }

  test(
    'active Reset automatically applies and replacement cancels an in-flight change',
    () async {
      final engine = _AssignmentEngine();
      final controller = await reader(engine);
      await controller.assignVoiceToCast('cast_narrator', 'am_fenrir');
      await controller.startPlayback();
      engine.acknowledge(engine.requests.single);
      await controller.clearCastVoiceOverride('cast_narrator');
      await until(() => engine.requests.length == 2);
      engine.acknowledge(engine.requests.last);
      expect(
        controller.voiceAssignmentState.effectiveCastVoices['cast_narrator'],
        'af_bella',
      );
      final barrier = _Barrier();
      engine.nextStop = barrier;
      await controller.selectVoiceById('af_heart');
      await barrier.started.future;
      final replacing = controller.loadDocument(
        DocumentImportService().importPastedText('A different work.'),
      );
      barrier.release.complete();
      await replacing;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(engine.requests, hasLength(2));
      expect(controller.isPlaying, isFalse);
      expect(controller.document.speakableText, contains('different work'));
    },
  );

  test(
    'preference owner snapshots maps and coalesces pending writes to latest choices',
    () async {
      final engine = _AssignmentEngine();
      final preferences = _SnapshotPreferences();
      final controller = await reader(engine, preferences: preferences);
      final barrier = _Barrier();
      preferences.nextWrite = barrier;
      final b = controller.selectVoiceById('af_heart');
      await barrier.started.future;
      final held = preferences.saved.last;
      final c = controller.selectVoiceById('am_fenrir');
      await Future<void>.delayed(Duration.zero);
      expect(held.selectedVoiceId, 'af_heart');
      expect(held.voiceSpeeds.containsKey('am_fenrir'), isFalse);
      expect(() => held.voiceSpeeds['mutated'] = 2, throwsUnsupportedError);
      barrier.release.complete();
      await Future.wait([b, c]);
      expect(preferences.saved.last.selectedVoiceId, 'am_fenrir');
      expect(
        controller.voiceAssignmentState.requestedDefaultVoiceId,
        'am_fenrir',
      );
    },
  );
}

class _SnapshotPreferences extends ReaderPreferencesService {
  final saved = <ReaderPreferences>[];
  _Barrier? nextWrite;
  @override
  Future<void> save({
    bool activityExpanded = false,
    String ttsEngineId = ReaderPreferences.defaultTtsEngineId,
    int voxtralQuantizationBits = 0,
    required String fontFamily,
    required double fontScale,
    required ReaderAppearanceMode appearanceMode,
    required bool multiVoiceEnabled,
    required Map<String, double> voiceSpeeds,
    required Map<String, Map<String, String>>
    storedDocumentCastVoiceAssignments,
    Map<String, String> sourceVoiceDocumentIds = const {},
    CharacterStoreSnapshot? characterSnapshot,
    ReaderResumeState? resumeState,
    String? selectedVoiceId,
    Map<String, String> narratorVoiceIds = const {},
    String? lastOpenedDocumentPath,
    String? lastOpenedDocumentAccessToken,
    String? lastOpenedDirectoryPath,
    String? lastOpenedDirectoryAccessToken,
  }) async {
    saved.add(
      ReaderPreferences(
        activityExpanded: activityExpanded,
        ttsEngineId: ttsEngineId,
        voxtralQuantizationBits: voxtralQuantizationBits,
        fontFamily: fontFamily,
        fontScale: fontScale,
        appearanceMode: appearanceMode,
        multiVoiceEnabled: multiVoiceEnabled,
        voiceSpeeds: voiceSpeeds,
        storedDocumentCastVoiceAssignments: storedDocumentCastVoiceAssignments,
        sourceVoiceDocumentIds: sourceVoiceDocumentIds,
        characterSnapshot: characterSnapshot,
        selectedVoiceId: selectedVoiceId,
        narratorVoiceIds: Map.of(narratorVoiceIds),
      ),
    );
    final barrier = nextWrite;
    nextWrite = null;
    if (barrier != null) {
      barrier.started.complete();
      await barrier.release.future;
    }
  }
}

class _Barrier {
  final started = Completer<void>();
  final release = Completer<void>();
}

TtsExportResult _result(TtsExportRequest request) => TtsExportResult(
  outputPath: request.outputPath,
  sidecarPath: '${request.outputPath}.json',
  duration: const Duration(seconds: 1),
  chunkCount: 1,
  voiceId: request.planningContext!.realization.voiceId,
  rate: request.planningContext!.realization.rate,
  engineId: 'fake',
  engineVersion: '1',
);

class _AssignmentEngine extends Fake
    implements
        TtsEngine,
        ResourcePreparationCapable,
        VoiceAssignmentPlaybackCapable,
        AudioExportCapable {
  static const voices = [
    VoiceProfile(id: 'af_bella', label: 'Bella', locale: 'en-US', rawValue: {}),
    VoiceProfile(id: 'af_heart', label: 'Heart', locale: 'en-US', rawValue: {}),
    VoiceProfile(
      id: 'am_fenrir',
      label: 'Fenrir',
      locale: 'en-US',
      rawValue: {},
    ),
  ];
  final requests = <TtsSpeakRequest>[];
  final selected = <String>[];
  final preparations = <List<PreparedVoiceBinding>>[];
  final exports = <TtsExportRequest>[];
  _Barrier? nextSelection;
  _Barrier? nextStop;
  Completer<TtsExportResult>? exportBarrier;
  TtsPlaybackResumeAnchor? anchor;
  int stops = 0;
  bool ready = false;
  void Function()? start;
  void Function(TtsPlaybackActivity)? activity;
  void Function(TtsProgressUpdate)? progress;
  void Function(String)? error;
  @override
  Future<void> initialize() async {}
  @override
  Future<List<VoiceProfile>> loadVoices() async => voices;
  @override
  Future<void> selectVoice(VoiceProfile voice) async {
    selected.add(voice.id);
    final barrier = nextSelection;
    nextSelection = null;
    if (barrier != null) {
      barrier.started.complete();
      await barrier.release.future;
    }
  }

  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVolume(double value) async {}
  @override
  Future<void> speak(TtsSpeakRequest request) async {
    requests.add(request);
    activity?.call(
      const TtsPlaybackActivity(phase: TtsPlaybackPhase.buffering),
    );
  }

  void acknowledge(TtsSpeakRequest request) {
    request.onPlaybackReady?.call(
      TtsPlaybackAcknowledgment(
        documentId: request.documentId!,
        assignmentRevision: request.assignmentRevision,
        generationId: 'generation-${request.assignmentRevision}',
        bindingFingerprints: request.preparedResources!
            .map((b) => b.fingerprint)
            .toSet(),
      ),
    );
    activity?.call(const TtsPlaybackActivity(phase: TtsPlaybackPhase.playing));
    start?.call();
  }

  @override
  Future<void> stop() async {
    ++stops;
    final barrier = nextStop;
    nextStop = null;
    if (barrier != null) {
      barrier.started.complete();
      await barrier.release.future;
    }
    activity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  Future<void> pause() async {
    activity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  TtsPlaybackResumeAnchor? get currentPlaybackResumeAnchor => anchor;
  @override
  bool get resourcesReady => ready;
  @override
  Future<List<PreparedVoiceBinding>> prepareDocumentResources({
    required String documentId,
    required int revision,
    required Set<String> voiceIds,
    required String pronunciationProfileId,
  }) async {
    final bindings = voiceIds
        .map(
          (v) => PreparedVoiceBinding(
            voiceId: v,
            voiceDigest: 'bytes-$v',
            modelDigest: 'model',
            engineVersion: '1',
            pronunciationProfileId: pronunciationProfileId,
            bindingRevision: revision,
            documentId: documentId,
          ),
        )
        .toList();
    preparations.add(bindings);
    ready = true;
    return bindings;
  }

  @override
  Future<void> releaseDocumentResources() async {
    ready = false;
  }

  @override
  Future<void> shutdownResources() async {
    ready = false;
  }

  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    exports.add(request);
    return exportBarrier == null ? _result(request) : exportBarrier!.future;
  }

  @override
  void dispose() {}
  @override
  set onStart(void Function()? value) => start = value;
  @override
  set onActivity(void Function(TtsPlaybackActivity)? value) => activity = value;
  @override
  set onStatus(void Function(String?)? value) {}
  @override
  set onComplete(void Function()? value) {}
  @override
  set onError(void Function(String)? value) => error = value;
  @override
  set onProgress(void Function(TtsProgressUpdate)? value) => progress = value;
  @override
  set onDebugTrace(void Function(TtsDebugTraceSnapshot)? value) {}
}
