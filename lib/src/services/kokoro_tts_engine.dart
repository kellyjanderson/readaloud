import 'kokoro_tokenization_worker.dart';
import 'speech_planning_supervisor.dart';
import 'synthesis_admission_owner.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chunk_plan.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';
import '../models/tts_artifact.dart';
import '../models/voice_profile.dart';
import '../models/prepared_voice_binding.dart';
import 'exported_audio_assembler.dart';
import 'kokoro_assets.dart';
import 'kokoro_playback_coordination.dart';
import 'kokoro_pronunciation_translation_service.dart';
import 'kokoro_speech_worker_processor.dart';
import 'kokoro_voice_catalog.dart';
import 'kokoro_voice_manager.dart';
import 'kokoro_voice_repository.dart';
import 'playback_instrumentation_service.dart';
import 'speech_runtime.dart';
import 'tts_debug_trace_session.dart';
import 'tts_engine.dart';

class KokoroTtsEngine
    implements
        TtsEngine,
        VoiceLibraryCapable,
        AudioExportCapable,
        ResourcePreparationCapable,
        SpeechRateNormalizationCapable {
  KokoroTtsEngine({AudioPlayer? player, this.beforeSynthesis})
    : _player = player ?? AudioPlayer(useLazyPreparation: false);
  final Future<void> Function()? beforeSynthesis;

  static const String _engineId = 'kokoro';
  static const String _engineVersion = '12';
  static const String _fallbackNormalizationVersion =
      'read-aloud-normalization-v1';
  static const int _targetChunkWordCount = 18;
  static const Duration _startupWarmupPollInterval = Duration(milliseconds: 40);
  static const Duration _startupWarmupMaxWait = Duration(seconds: 5);

  final AudioPlayer _player;
  final PlaybackInstrumentationService _instrumentation =
      PlaybackInstrumentationService.instance;
  final ExportedAudioAssembler _exportAssembler = ExportedAudioAssembler();

  void Function()? _onStart;
  void Function(String? message)? _onStatus;
  void Function(TtsProgressUpdate update)? _onProgress;
  void Function()? _onComplete;
  void Function(String message)? _onError;
  void Function(TtsPlaybackActivity activity)? _onActivity;
  void Function(TtsDebugTraceSnapshot trace)? _onDebugTrace;
  void Function()? _onVoiceLibraryChanged;
  TtsDebugTraceSession? _debugTraceSession;

  Future<void>? _initializationFuture;
  KokoroAssetBundle? _assets;
  KokoroVoiceRepository? _voiceRepository;
  KokoroVoiceManager? _voiceManager;
  KokoroTokenizationWorker? _playbackTokenizer;
  KokoroTokenizationWorker? _exportTokenizer;
  SpeechRuntime? _speechRuntime;
  KokoroSpeechWorkerChunkProcessor? _resourceProcessor;
  SynthesisAdmissionOwner? _admission;
  CancellableSynthesisLease? _playbackLease;
  CancellableSynthesisLease? _exportLease;
  final _nativePlaybackAdmission = KokoroBufferAdmission();
  final Set<Future<void>> _playbackPreparationTasks = {};
  int get pendingPlaybackPreparationTasks => _playbackPreparationTasks.length;

  void _ownPlaybackPreparation(Future<void> task, int requestToken) {
    _playbackPreparationTasks.add(task);
    unawaited(
      task.then<void>(
        (_) {
          _playbackPreparationTasks.remove(task);
        },
        onError: (Object error, StackTrace stack) {
          _playbackPreparationTasks.remove(task);
          if (requestToken == _requestToken) {
            _onError?.call('Playback preparation failed: $error');
          }
        },
      ),
    );
  }

  Future<void> _drainPlaybackPreparation() async {
    while (_playbackPreparationTasks.isNotEmpty) {
      await Future.wait(
        _playbackPreparationTasks.toList().map(
          (task) =>
              task.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        ),
      );
    }
  }

  final SpeechPlanningSupervisor _refillPlanner = SpeechPlanningSupervisor();
  Completer<void> _bufferChanged = Completer<void>();
  int _nextReadyWord = 0;
  _PlaybackChunk? _startupFirstChunk;
  void _signalBuffer() {
    final old = _bufferChanged;
    _bufferChanged = Completer<void>();
    if (!old.isCompleted) old.complete();
    _admission?.signal();
  }

  Future<void> _resourceTransition = Future<void>.value();
  bool _exportingResources = false;
  bool _exportCancelled = false;
  final _releaseResourcesAfterExport = KokoroDeferredResourceRelease();
  SpeechRuntime? _exportRuntime;
  String? _exportSession;
  Future<void> _cancelExport() async {
    _exportCancelled = true;
    _exportAssembler.cancel();
    _exportTokenizer?.cancel();
    final session = _exportSession;
    final cancellation = session == null
        ? null
        : _exportRuntime?.cancelSession(session);
    // Runtime cancellation invalidates publication; lease cancellation removes
    // native admission even when export has no playback-lead credit.
    _exportLease?.cancelPending();
    _signalBuffer();
    await cancellation;
    await _exportDrained?.future;
  }

  Completer<void>? _exportDrained;
  int _resourceRequest = 0;
  Future<void>? _resourceShutdown;
  bool _resourcesReady = false;
  List<PreparedVoiceBinding> _preparedBindings = const [];
  @override
  bool get resourcesReady => _resourcesReady;

  @override
  Future<List<PreparedVoiceBinding>> prepareDocumentResources({
    required String documentId,
    required int revision,
    required Set<String> voiceIds,
    required String pronunciationProfileId,
  }) => _prepareDocumentResources(
    documentId: documentId,
    revision: revision,
    voiceIds: voiceIds,
    pronunciationProfileId: pronunciationProfileId,
  );

  Future<List<PreparedVoiceBinding>> _prepareDocumentResources({
    required String documentId,
    required int revision,
    required Set<String> voiceIds,
    required String pronunciationProfileId,
    bool ownedByExport = false,
  }) async {
    if (_exportingResources && !ownedByExport) await _cancelExport();
    await initialize();
    if (ownedByExport && _exportCancelled) {
      throw StateError('Export cancelled.');
    }
    if (_resourceShutdown != null) {
      throw StateError('Speech resources are unavailable.');
    }
    final resourceRequest = ++_resourceRequest;
    final operation = _resourceTransition.then((_) async {
      if (resourceRequest != _resourceRequest) {
        throw StateError('Resource preparation superseded.');
      }
      final processor = _resourceProcessor;
      if (processor == null) {
        throw StateError('Speech resources failed to initialize.');
      }
      _resourcesReady = false;
      final bindings = await _admission!.exclusive(
        () => processor.prepareResources(
          documentId: documentId,
          revision: revision,
          voiceIds: voiceIds,
          pronunciationProfileId: pronunciationProfileId,
        ),
      );
      if (resourceRequest != _resourceRequest) {
        throw StateError('Resource preparation superseded.');
      }
      _resourcesReady = true;
      _preparedBindings = bindings;
      return bindings;
    });
    _resourceTransition = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  @override
  Future<void> releaseDocumentResources() {
    ++_resourceRequest;
    _resourcesReady = false;
    final operation = _resourceTransition.then((_) async {
      _resourcesReady = false;
      await _admission?.exclusive(() => _resourceProcessor!.releaseResources());
    });
    _resourceTransition = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  @override
  Future<void> shutdownResources() =>
      _resourceShutdown ??= _shutdownResources();
  Future<void> _shutdownResources() async {
    ++_resourceRequest;
    _resourcesReady = false;
    await Future.wait([_cancelExport(), stop()]);
    await _exportAssembler.shutdown();
    await _resourceTransition;
    await _speechRuntime?.shutdownRuntime();
    await _refillPlanner.shutdown();
    await _playbackTokenizer?.shutdown();
    await _exportTokenizer?.shutdown();
    await _admission?.shutdown();
    _resourcesReady = false;
  }

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;
  StreamSubscription<SpeechRuntimeEvent>? _runtimeEventSubscription;

  int _requestToken = 0;
  int? _activePlaybackToken;
  double _speechRate = 1.0;
  double _volume = 1.0;
  String _selectedVoiceId = KokoroVoiceCatalog.defaultVoiceId;
  List<_PlaybackChunk> _activeChunks = const <_PlaybackChunk>[];
  int _currentChunkIndex = 0;
  int _currentQueueBaseIndex = 0;
  bool _pruningHistory = false;
  bool _pruneScheduled = false;
  String? _lastProgressKey;
  String? _activeGenerationId;
  String? _activeDocumentId;
  String? _activeSessionId;
  String? _firstPendingChunkId;
  Completer<_PlaybackChunk>? _firstChunkCompleter;
  Map<String, _QueuedChunk> _pendingChunksById = <String, _QueuedChunk>{};
  final Map<String, DateTime> _queuedAtByChunkId = <String, DateTime>{};
  int _expectedChunkCount = 0;
  int _remainingPlannedChunkCount = 0;
  bool _waitingForUnderrunRecovery = false;
  final _audioQueueMutations = KokoroPlaylistMutationQueue();
  TtsBufferPressure _lastRecordedBufferPressure = TtsBufferPressure.none;
  final List<_PlaybackChunk> _stagedReadyChunks = <_PlaybackChunk>[];

  @override
  set onStart(void Function()? callback) => _onStart = callback;

  @override
  set onStatus(void Function(String? message)? callback) =>
      _onStatus = callback;

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
  set onDebugTrace(void Function(TtsDebugTraceSnapshot trace)? callback) {
    _onDebugTrace = callback;
    final session = _debugTraceSession;
    if (session != null) {
      session.onUpdated = callback;
      final trace = callback;
      if (trace != null) {
        trace(session.snapshot());
      }
    }
  }

  @override
  set onVoiceLibraryChanged(void Function()? callback) =>
      _onVoiceLibraryChanged = callback;

  @override
  List<VoiceLibraryEntry> get voiceLibrary =>
      _voiceManager?.voiceLibrary ?? const <VoiceLibraryEntry>[];

  @override
  Future<void> initialize() {
    _initializationFuture ??= _initializeInternal();
    return _initializationFuture!;
  }

  Future<void> _initializeInternal() async {
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (_activePlaybackToken == null) {
        return;
      }
      if (state.processingState == ProcessingState.completed) {
        _emitFinalProgress();
        final queueSnapshot = _playbackQueueSnapshot();
        if (kokoroShouldEnterUnderrunRecovery(queueSnapshot)) {
          _waitingForUnderrunRecovery = true;
          _recordMetric(
            'playbackUnderrun',
            value: <String, Object?>{
              'currentChunkIndex': _currentChunkIndex,
              'bufferedChunkCount': _activeChunks.length,
              'pendingChunkCount': _pendingChunksById.length,
              'hasBufferedFutureChunks': kokoroHasBufferedFutureChunks(
                queueSnapshot,
              ),
            },
          );
          _emitActivity(
            _playbackActivityForPhase(
              TtsPlaybackPhase.buffering,
              bufferedChunkCount: _activeChunks.length,
              totalChunkCount: _expectedChunkCount,
            ),
          );
          unawaited(_resumeAfterUnderrunIfPossible());
          return;
        }
        final reset = _resetPlaybackState();
        if (_exportingResources) {
          _releaseResourcesAfterExport.defer(
            resourceEpoch: _resourceRequest,
            playbackEpoch: _requestToken,
            resetDrained: reset,
          );
        } else {
          unawaited(releaseDocumentResources());
        }
        unawaited(
          reset.catchError((Object error, StackTrace stack) {
            _onError?.call('Audio playback cleanup failed: $error');
          }),
        );
        _onComplete?.call();
      }
    });

    _positionSubscription = _player.positionStream.listen(
      _handlePosition,
      onError: (Object error, StackTrace stackTrace) {
        _emitActivity(const TtsPlaybackActivity.idle());
        _onError?.call('Audio playback failed: $error');
      },
    );
    _currentIndexSubscription = _player.currentIndexStream.listen(
      _handleCurrentIndex,
    );

    try {
      _assets = await prepareKokoroAssets(onStatus: _onStatus);
      if (!(_assets?.isReady ?? false)) {
        _onError?.call(_assets?.message ?? 'Kokoro is unavailable.');
        return;
      }

      _voiceRepository = KokoroVoiceRepository(
        voicesDirectory: _assets!.voicesDirectory!,
      );
      _voiceManager = KokoroVoiceManager(
        voiceRepository: _voiceRepository!,
        cacheDirectory: _assets!.cacheDirectory!,
      )..onChanged = () => _onVoiceLibraryChanged?.call();
      await _voiceManager!.initialize();

      // The platform bridge obtains asset text only. Lexicon JSON decoding,
      // dictionary growth, CMU conversion and lazy G2P initialization all belong
      // to each pure-Dart tokenization owner, never this UI isolate.
      final tokenizerSources = await Future.wait([
        rootBundle.loadString('assets/tokenizer_vocab.json'),
        rootBundle.loadString('assets/lexicon.json').catchError((_) => '{}'),
        rootBundle.loadString('assets/us_gold.json'),
        rootBundle.loadString('assets/us_silver.json'),
        rootBundle.loadString('assets/cmudict.dict'),
      ]);
      final tokenizerAssets = KokoroTokenizerAssets(
        vocabularyJson: tokenizerSources[0],
        lexiconJson: tokenizerSources[1],
        goldJson: tokenizerSources[2],
        silverJson: tokenizerSources[3],
      );
      _playbackTokenizer = KokoroTokenizationWorker(
        assets: tokenizerAssets,
        rawDictionary: tokenizerSources[4],
        ownerId: 'playback-tokenizer',
      );
      _exportTokenizer = KokoroTokenizationWorker(
        assets: tokenizerAssets,
        rawDictionary: tokenizerSources[4],
        ownerId: 'export-tokenizer',
      );
      final rootIsolateToken = ServicesBinding.rootIsolateToken;
      if (rootIsolateToken == null) {
        throw StateError('Kokoro requires a root isolate token.');
      }
      _resourceProcessor = await _createWorkerProcessor(rootIsolateToken);
      _admission = SynthesisAdmissionOwner(
        _resourceProcessor!,
        beforeProcess: beforeSynthesis,
        playbackMayRun: () =>
            _activeGenerationId == null ||
            _nativePlaybackAdmission.admits(
              audioLead: _preparedLead(),
              outstandingChunks: 0,
              playerSpeed: _player.speed,
            ),
        exportMayRun: () =>
            _exportCancelled ||
            _activeGenerationId == null ||
            (_activePlaybackToken != null &&
                _playableBufferedLeadTime() >= kokoroLowWaterBufferedLeadTime),
      );
      _playbackLease = _admission!.lease(export: false);
      _speechRuntime = SpeechRuntime(
        engineId: _engineId,
        processor: _playbackLease!,
      );
      _runtimeEventSubscription = _speechRuntime!.events.listen(
        _handleRuntimeEvent,
      );
      await _speechRuntime!.initializeRuntime(
        preferredVoiceId: _selectedVoiceId,
      );
      if (!_speechRuntime!.capabilities.isEngineSupported) {
        _onError?.call(
          'Kokoro is not supported on this Flutter platform path.',
        );
        return;
      }

      _emitActivity(const TtsPlaybackActivity.idle());
      _onStatus?.call(null);
    } catch (error) {
      _emitActivity(const TtsPlaybackActivity.idle());
      _onError?.call('Kokoro could not be initialized: $error');
    }
  }

  @override
  Future<List<VoiceProfile>> loadVoices() async {
    await initialize();
    final voiceManager = _voiceManager;
    if (voiceManager == null) {
      return const <VoiceProfile>[];
    }
    return voiceManager.loadInstalledVoices();
  }

  @override
  Future<void> installVoice(String voiceId) async {
    await initialize();
    final voiceManager = _voiceManager;
    if (voiceManager == null) {
      throw StateError('Kokoro voice management is unavailable.');
    }
    await voiceManager.installVoice(voiceId);
  }

  @override
  Future<void> selectVoice(VoiceProfile voice) async {
    _selectedVoiceId = voice.id;
  }

  @override
  double normalizeSpeechRate(double requested) =>
      kokoroNormalizeSpeechRate(requested);

  @override
  Future<void> setSpeechRate(double multiplier) async {
    final effectiveRate = normalizeSpeechRate(multiplier);
    if ((_activeGenerationId != null || _playbackPreparationTasks.isNotEmpty) &&
        effectiveRate != _speechRate) {
      await stop();
    }
    _speechRate = effectiveRate;
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    await _player.setVolume(_volume);
  }

  @override
  Future<void> speak(TtsSpeakRequest request) async {
    await initialize();
    if (_speechRuntime == null || _voiceManager == null) {
      _onError?.call(_assets?.message ?? 'Kokoro is unavailable.');
      return;
    }

    await stop();

    final requestToken = ++_requestToken;
    _lastProgressKey = null;
    _activeDocumentId = request.documentId ?? 'unknown-document';
    _activeSessionId =
        request.sessionId ?? 'session_${DateTime.now().microsecondsSinceEpoch}';
    _queuedAtByChunkId.clear();
    _waitingForUnderrunRecovery = false;
    _currentQueueBaseIndex = 0;
    await _startDebugTraceSession(sessionId: _activeSessionId!);

    _ownPlaybackPreparation(
      _synthesizeAndPlay(requestToken, request),
      requestToken,
    );
  }

  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    if (_exportingResources || _resourceShutdown != null) {
      throw StateError('Speech resources are unavailable for export.');
    }
    _exportingResources = true;
    _exportCancelled = false;
    _exportDrained = Completer<void>();
    try {
      return await _exportAudioWithResources(request);
    } finally {
      try {
        // A natural document end waits for the export's resource lease. Pause
        // does not set this flag and keeps its prepared context resident.
        if (await _releaseResourcesAfterExport.takeIfCurrent(
          resourceEpoch: () => _resourceRequest,
          playbackEpoch: () => _requestToken,
          generationActive: () => _activeGenerationId != null,
        )) {
          await releaseDocumentResources();
        }
      } finally {
        _exportingResources = false;
        _exportDrained!.complete();
        _exportRuntime = null;
        _exportSession = null;
        _exportLease = null;
      }
    }
  }

  Future<TtsExportResult> _exportAudioWithResources(
    TtsExportRequest request,
  ) async {
    await initialize();
    if (_exportCancelled) throw StateError('Export cancelled.');
    final planner = SpeechPlanningSupervisor();
    final context = request.planningContext;
    final rate = context?.realization.rate ?? _speechRate;
    if (normalizeSpeechRate(rate) != rate) {
      throw StateError(
        'Export planning must use the effective supported speech rate.',
      );
    }
    final voiceId = context?.realization.voiceId ?? _selectedVoiceId;
    final requiredVoices = {
      ...?context?.routes?.castVoiceAssignments.assignments.map(
        (a) => a.effectiveVoiceId,
      ),
      voiceId,
      ...?request.chunkPlan?.chunks.map((c) => c.voiceId),
    };
    final supplied = request.preparedResources;
    if (supplied != null) {
      if (!_resourcesReady ||
          requiredVoices.any(
            (voice) => !supplied.any(
              (binding) =>
                  binding.voiceId == voice &&
                  binding.documentId == request.documentId &&
                  _preparedBindings.any(
                    (resident) =>
                        resident.voiceId == binding.voiceId &&
                        resident.documentId == binding.documentId &&
                        resident.bindingRevision == binding.bindingRevision &&
                        resident.fingerprint == binding.fingerprint,
                  ),
            ),
          )) {
        throw StateError('Export resource reference is stale.');
      }
    } else {
      if (_activeGenerationId != null) {
        throw StateError(
          'Export requires prepared resource references during playback.',
        );
      }
      await _prepareDocumentResources(
        documentId: request.documentId ?? 'export-document',
        revision: 0,
        voiceIds: requiredVoices,
        pronunciationProfileId:
            request.ttsArtifactSet?.selectedProfileId ?? 'kokoro-default',
        ownedByExport: true,
      );
    }
    if (_exportCancelled) throw StateError('Export cancelled.');
    _exportLease = _admission!.lease(export: true);
    final runtime = SpeechRuntime(
      engineId: _engineId,
      processor: _exportLease!,
    );
    final sessionId =
        request.sessionId ?? 'export_${DateTime.now().microsecondsSinceEpoch}';
    final generationId = '${sessionId}_generation';
    _exportRuntime = runtime;
    _exportSession = sessionId;
    final outputs = <ExportedAudioChunk>[];
    var completion = Completer<List<ExportedAudioChunk>>();
    final completedChunks = <String, ExportedAudioChunk>{};
    final pendingChunksById = <String, _QueuedChunk>{};
    var chunks = <_QueuedChunk>[];
    var initial = true;
    final subscription = runtime.events.listen((event) {
      if (event.sessionId != null && event.sessionId != sessionId) return;
      if (event.type == SpeechRuntimeEventType.chunkReady) {
        final chunkId = event.chunkId;
        final plannedChunk = pendingChunksById[chunkId];
        if (chunkId == null ||
            plannedChunk == null ||
            event.audioPath == null ||
            event.duration == null) {
          return;
        }
        completedChunks[chunkId] = ExportedAudioChunk(
          chunkId: chunkId,
          cacheKey: plannedChunk.runtimeCacheKey(
            isInitialChunk:
                initial && plannedChunk.chunkId == chunks.first.chunkId,
            isResumedChunk: false,
          ),
          audioPath: event.audioPath!,
          duration: event.duration!,
          segmentIds: plannedChunk.segmentIds,
          startWordIndex: plannedChunk.startWordIndex,
          endWordIndex: plannedChunk.endWordIndex,
          voiceId: plannedChunk.voiceId,
          routeId: plannedChunk.routeId,
          castId: plannedChunk.castId,
          dialogueSpanId: plannedChunk.dialogueSpanId,
          capabilityProfileId: plannedChunk.capabilityProfileId,
          missingFallbackWordCount: plannedChunk.missingFallbackWordCount,
          boundaryMetadata: event.boundaryClass == null
              ? null
              : ExportedBoundaryMetadata(
                  boundaryClass: event.boundaryClass!.name,
                  correctionApplied: event.boundaryCorrectionApplied ?? false,
                  leadingSilenceBefore:
                      event.leadingSilenceBefore ?? Duration.zero,
                  leadingSilenceAfter: event.leadingSilence ?? Duration.zero,
                  trailingSilenceBefore:
                      event.trailingSilenceBefore ?? Duration.zero,
                  trailingSilenceAfter: event.trailingSilence ?? Duration.zero,
                  joinSilenceBefore: event.joinSilenceBefore ?? Duration.zero,
                  joinSilenceAfter: event.joinSilenceAfter ?? Duration.zero,
                  isInitialChunk: event.isInitialChunk ?? false,
                  isResumedChunk: event.isResumedChunk ?? false,
                ),
          pronunciationArtifacts: _exportPronunciationArtifacts(
            plannedChunk.translatedPronunciationArtifacts,
          ),
        );
        if (!completion.isCompleted &&
            completedChunks.length == chunks.length) {
          completion.complete(
            chunks.map((c) => completedChunks[c.chunkId]!).toList(),
          );
        }
      } else if (event.type == SpeechRuntimeEventType.chunkFailed ||
          event.type == SpeechRuntimeEventType.runtimeFailed ||
          event.type == SpeechRuntimeEventType.sessionCancelled) {
        if (!completion.isCompleted) {
          completion.completeError(
            StateError(event.message ?? 'Export cancelled or failed.'),
          );
        }
      }
    });
    try {
      await runtime.initializeRuntime(preferredVoiceId: voiceId);
      await runtime.activateSession(
        SpeechRuntimeSessionDescriptor(
          sessionId: sessionId,
          documentId: request.documentId ?? 'export-document',
          engineId: _engineId,
          voiceId: voiceId,
          rate: rate,
          startSegmentId:
              request.chunkPlan?.chunks.first.segmentIds.first ?? 'export',
          normalizationVersion:
              request.normalizationVersion ?? _fallbackNormalizationVersion,
          isReplay: false,
          isResumedPlayback: false,
          narrationState: const {},
        ),
      );
      var plan = request.chunkPlan;
      var searchOffset = 0;
      while (true) {
        if (_exportCancelled) throw StateError('Export cancelled.');
        final speakRequest = TtsSpeakRequest(
          text: request.text,
          documentId: request.documentId,
          normalizationVersion: request.normalizationVersion,
          chunkPlan: plan,
          speechDocument: request.speechDocument,
        );
        if (plan == null) {
          chunks = await _prepareChunks(
            speakRequest,
            tokenWorker: _exportTokenizer,
            languageTag: KokoroVoiceCatalog.languageTagForVoice(voiceId),
          );
        } else {
          final prepared = await _preparePlannedChunkWindow(
            request: speakRequest,
            tokenWorker: _exportTokenizer,
            specs: plan.chunks,
            initialSearchOffset: searchOffset,
            languageTag: KokoroVoiceCatalog.languageTagForVoice(voiceId),
          );
          chunks = prepared.chunks;
          searchOffset = prepared.nextSearchOffset;
        }
        if (chunks.isEmpty) break;
        completion = Completer<List<ExportedAudioChunk>>();
        completedChunks.clear();
        pendingChunksById
          ..clear()
          ..addEntries(chunks.map((c) => MapEntry(c.chunkId, c)));
        final waiting = completion.future;
        // Observe failure immediately even while bounded admission is pending.
        unawaited(waiting.then<void>((_) {}, onError: (Object _) {}));
        await runtime.prepareChunkPlan(
          sessionId: sessionId,
          generationId: generationId,
          chunks: chunks
              .map(
                (c) => c.toRuntimeChunk(
                  rate: rate,
                  languageTag: KokoroVoiceCatalog.languageTagForVoice(
                    c.voiceId,
                  ),
                  isInitialChunk: initial && c.chunkId == chunks.first.chunkId,
                  isResumedChunk: false,
                ),
              )
              .toList(),
        );
        outputs.addAll(await waiting);
        initial = false;
        final next = plan?.nextSegmentId;
        if (next == null || context == null) break;
        plan = (await planner.plan(context, startSegmentId: next)).plan;
      }
      return await _exportAssembler.assemble(
        ExportedAudioAssemblyRequest(
          outputPath: request.outputPath,
          engineId: _engineId,
          engineVersion: _engineVersion,
          documentId: request.documentId ?? 'export-document',
          documentTitle: request.documentTitle ?? 'Read Aloud Export',
          sourceDescription: request.sourceDescription ?? 'Audio export',
          voiceId: voiceId,
          rate: rate,
          normalizationVersion:
              request.normalizationVersion ?? _fallbackNormalizationVersion,
          chunks: outputs,
        ),
      );
    } finally {
      await runtime.shutdownRuntime();
      await subscription.cancel();
      await planner.shutdown();
    }
  }

  Future<void> _synthesizeAndPlay(
    int requestToken,
    TtsSpeakRequest request,
  ) async {
    final speechRuntime = _speechRuntime;
    if (speechRuntime == null) {
      _onError?.call('Kokoro speech runtime is unavailable.');
      return;
    }

    try {
      if (request.planningContext != null &&
          request.planningContext!.realization.rate != _speechRate) {
        throw StateError(
          'Playback plan and effective synthesis rate do not match.',
        );
      }
      final requiredVoices = {
        ...?request.planningContext?.routes?.castVoiceAssignments.assignments
            .map((a) => a.effectiveVoiceId),
        _selectedVoiceId,
        ...?request.chunkPlan?.chunks.map((c) => c.voiceId),
      };
      final suppliedResources = request.preparedResources;
      if (suppliedResources != null) {
        if (!_resourcesReady ||
            requiredVoices.any(
              (voice) => !suppliedResources.any(
                (supplied) =>
                    supplied.voiceId == voice &&
                    supplied.documentId == request.documentId &&
                    _preparedBindings.any(
                      (current) =>
                          current.voiceId == supplied.voiceId &&
                          current.documentId == supplied.documentId &&
                          current.bindingRevision == supplied.bindingRevision &&
                          current.fingerprint == supplied.fingerprint,
                    ),
              ),
            )) {
          throw StateError(
            'Playback resource reference is stale. Prepare this document again.',
          );
        }
      } else {
        await prepareDocumentResources(
          documentId: request.documentId ?? 'unknown-document',
          revision: 0,
          voiceIds: requiredVoices,
          pronunciationProfileId:
              request.ttsArtifactSet?.selectedProfileId ?? 'kokoro-default',
        );
      }
      if (requestToken != _requestToken) return;
      final languageTag = KokoroVoiceCatalog.languageTagForVoice(
        _selectedVoiceId,
      );
      final hasPlannedChunks =
          request.chunkPlan != null && request.chunkPlan!.chunks.isNotEmpty;
      final preparedStartupWindow = hasPlannedChunks
          ? await _preparePlannedChunkWindow(
              request: request,
              specs: request.chunkPlan!.chunks
                  .take(kokoroStartupPreparedChunkWindow)
                  .toList(growable: false),
              initialSearchOffset: 0,
              languageTag: languageTag,
            )
          : null;
      final preparedChunks = hasPlannedChunks
          ? preparedStartupWindow!.chunks
          : await _prepareChunks(request, languageTag: languageTag);
      if (requestToken != _requestToken) return;
      if (preparedChunks.isEmpty) {
        _onError?.call('Kokoro could not prepare readable text for synthesis.');
        return;
      }
      for (final chunk in preparedChunks) {
        _recordPronunciationTrace(chunk);
      }
      final startupWindow = KokoroStartupChunkWindow(preparedChunks);
      final chunks = startupWindow.startup;

      final generationId = 'generation_$requestToken';
      _activeGenerationId = generationId;
      _firstPendingChunkId = chunks.first.chunkId;
      _nextReadyWord = chunks.first.startWordIndex;
      _startupFirstChunk = null;
      _firstChunkCompleter = Completer<_PlaybackChunk>();
      // Cancellation may arrive while initial admission is still awaiting the
      // runtime. Own its error immediately, before the later startup await.
      unawaited(
        _firstChunkCompleter!.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      _pendingChunksById = <String, _QueuedChunk>{
        for (final chunk in chunks) chunk.chunkId: chunk,
      };
      _expectedChunkCount = hasPlannedChunks
          ? request.chunkPlan!.chunks.length
          : preparedChunks.length;
      _remainingPlannedChunkCount = hasPlannedChunks
          ? request.chunkPlan!.chunks.length -
                chunks.length +
                (request.chunkPlan!.nextSegmentId == null ? 0 : 1)
          : startupWindow.tail.length;

      _emitActivity(
        _playbackActivityForPhase(
          TtsPlaybackPhase.buffering,
          totalChunkCount: _expectedChunkCount,
        ),
      );

      await speechRuntime.activateSession(
        SpeechRuntimeSessionDescriptor(
          sessionId: _activeSessionId!,
          documentId: _activeDocumentId!,
          engineId: _engineId,
          voiceId: _selectedVoiceId,
          rate: _speechRate,
          startSegmentId: chunks.first.segmentIds.first,
          normalizationVersion:
              request.normalizationVersion ?? _fallbackNormalizationVersion,
          isReplay: !request.isResumedPlayback,
          isResumedPlayback: request.isResumedPlayback,
          narrationState: const <String, Object?>{},
        ),
      );

      await speechRuntime.preparePriorityChunk(
        sessionId: _activeSessionId!,
        generationId: generationId,
        chunk: chunks.first.toRuntimeChunk(
          rate: _speechRate,
          languageTag: KokoroVoiceCatalog.languageTagForVoice(
            chunks.first.voiceId,
          ),
          isInitialChunk: true,
          isResumedChunk: request.isResumedPlayback,
        ),
      );

      if (chunks.length > 1) {
        await speechRuntime.prepareChunkPlan(
          sessionId: _activeSessionId!,
          generationId: generationId,
          chunks: chunks
              .skip(1)
              .map(
                (chunk) => chunk.toRuntimeChunk(
                  rate: _speechRate,
                  languageTag: KokoroVoiceCatalog.languageTagForVoice(
                    chunk.voiceId,
                  ),
                  isInitialChunk: false,
                  isResumedChunk: false,
                ),
              )
              .toList(growable: false),
        );
      }

      if (hasPlannedChunks &&
          (request.chunkPlan!.chunks.length > 1 ||
              request.chunkPlan!.nextSegmentId != null)) {
        final remainingSpecs = request.chunkPlan!.chunks
            .skip(chunks.length)
            .toList(growable: false);
        _ownPlaybackPreparation(
          _queueRemainingPlannedChunks(
            requestToken: requestToken,
            request: request,
            generationId: generationId,
            languageTag: languageTag,
            specs: remainingSpecs,
            initialSearchOffset: preparedStartupWindow!.nextSearchOffset,
          ),
          requestToken,
        );
      } else if (startupWindow.tail.isNotEmpty) {
        _ownPlaybackPreparation(
          _queueRemainingPreparedChunks(
            requestToken: requestToken,
            generationId: generationId,
            chunks: startupWindow.tail,
          ),
          requestToken,
        );
      }

      final firstChunk = await _firstChunkCompleter!.future;
      if (requestToken != _requestToken || _activeGenerationId == null) {
        return;
      }

      final startupWarmupStartedAt = DateTime.now();
      await _awaitStartupWarmup(firstChunk: firstChunk);
      if (requestToken != _requestToken || _activeGenerationId == null) {
        return;
      }
      final activeGenerationId = _activeGenerationId!;

      final initialBufferedChunks = _startupBufferedChunks(firstChunk);
      _stagedReadyChunks.removeWhere(
        (chunk) => initialBufferedChunks.any(
          (ready) => ready.chunkId == chunk.chunkId,
        ),
      );
      _nextReadyWord = initialBufferedChunks.last.endWordIndex;
      _recordMetric(
        'startupWarmup',
        chunkId: firstChunk.chunkId,
        voiceId: firstChunk.voiceId,
        value: <String, Object?>{
          'waitMillis': DateTime.now()
              .difference(startupWarmupStartedAt)
              .inMilliseconds,
          'bufferedChunkCount': initialBufferedChunks.length,
          'bufferedLeadTimeMs': _initialBufferedQueueLeadTime(
            initialBufferedChunks,
          ).inMilliseconds,
          'pendingChunkCount': _pendingChunksById.length,
          'remainingPlannedChunkCount': _remainingPlannedChunkCount,
        },
      );
      _activeChunks = initialBufferedChunks;
      _currentChunkIndex = 0;
      _currentQueueBaseIndex = 0;
      _waitingForUnderrunRecovery = false;
      await _player.setVolume(_volume);
      await _player.setAudioSources(
        initialBufferedChunks
            .map((chunk) => AudioSource.file(chunk.filePath))
            .toList(growable: false),
      );
      _activePlaybackToken = requestToken;
      await _flushStagedReadyChunksToActiveQueue(
        generationId: activeGenerationId,
      );
      _emitProgressForChunkWord(0, 0, elapsedInChunk: Duration.zero);
      _emitActivity(
        _playbackActivityForPhase(
          TtsPlaybackPhase.playing,
          bufferedChunkCount: _activeChunks.length,
          totalChunkCount: _expectedChunkCount,
        ),
      );
      _onStatus?.call(null);
      _onStart?.call();
      unawaited(_player.play());
    } catch (error) {
      if (requestToken == _requestToken) {
        await _cancelActiveGeneration();
        await _resetPlaybackState();
        _onError?.call('Kokoro synthesis failed: $error');
      }
    }
  }

  Future<void> _queueRemainingPlannedChunks({
    required int requestToken,
    required TtsSpeakRequest request,
    required String generationId,
    required String languageTag,
    required List<ChunkSpec> specs,
    required int initialSearchOffset,
  }) async {
    final runtime = _speechRuntime;
    final sessionId = _activeSessionId;
    if (runtime == null || sessionId == null) return;
    bool current() =>
        requestToken == _requestToken &&
        generationId == _activeGenerationId &&
        sessionId == _activeSessionId;
    var remaining = specs;
    var next = request.chunkPlan?.nextSegmentId;
    var offset = initialSearchOffset;
    final policy = KokoroBufferAdmission();
    try {
      while (current()) {
        for (final spec in remaining) {
          // A hard count cap complements the audio-duration watermark, including
          // tiny/zero-duration chunks. Only one translation runs ahead of credit.
          await _awaitPlaybackCredit(policy, current);
          if (!current()) return;
          final prepared = await _preparePlannedChunk(
            request: request,
            spec: spec,
            searchOffset: offset,
            languageTag: languageTag,
          );
          if (!current()) return;
          offset = prepared.nextSearchOffset;
          final chunk = prepared.chunk;
          _pendingChunksById[chunk.chunkId] = chunk;
          _recordPronunciationTrace(chunk);
          await runtime.prepareChunkPlan(
            sessionId: sessionId,
            generationId: generationId,
            chunks: [
              chunk.toRuntimeChunk(
                rate: _speechRate,
                languageTag: KokoroVoiceCatalog.languageTagForVoice(
                  chunk.voiceId,
                ),
                isInitialChunk: false,
                isResumedChunk: false,
              ),
            ],
          );
        }
        if (next == null || request.planningContext == null) break;
        while (current() &&
            kokoroPlayableLead(_preparedLead(), playerSpeed: _player.speed) >=
                kokoroTargetBufferedLeadTime) {
          await _bufferChanged.future;
        }
        if (!current()) return;
        final window = await _refillPlanner.plan(
          request.planningContext!,
          startSegmentId: next,
        );
        if (!current()) return;
        remaining = window.plan.chunks;
        next = window.plan.nextSegmentId;
        _expectedChunkCount += remaining.length;
      }
      if (current()) {
        _remainingPlannedChunkCount = 0;
        _signalBuffer();
      }
    } on PlanningCancelled {
      return;
    } catch (error) {
      if (current()) {
        await _terminatePreparationFailure(
          'Kokoro could not prepare a later chunk: $error',
        );
      }
    }
  }

  Duration _preparedLead() {
    if (_activePlaybackToken != null) return _bufferedLeadTime();
    final first = _startupFirstChunk;
    return first == null
        ? Duration.zero
        : _initialBufferedQueueLeadTime(_startupBufferedChunks(first));
  }

  Future<void> _awaitPlaybackCredit(
    KokoroBufferAdmission policy,
    bool Function() current,
  ) async {
    while (current() &&
        !policy.admits(
          audioLead: _preparedLead(),
          outstandingChunks:
              _pendingChunksById.length +
              _stagedReadyChunks.length +
              (_activePlaybackToken == null && _startupFirstChunk != null
                  ? 1
                  : 0) +
              (_activeChunks.length - _currentChunkIndex - 1).clamp(0, 1000000),
          playerSpeed: _player.speed,
        )) {
      await _bufferChanged.future;
    }
  }

  Future<void> _queueRemainingPreparedChunks({
    required int requestToken,
    required String generationId,
    required List<_QueuedChunk> chunks,
  }) async {
    final runtime = _speechRuntime;
    final session = _activeSessionId;
    if (runtime == null || session == null) return;
    bool current() =>
        requestToken == _requestToken &&
        generationId == _activeGenerationId &&
        session == _activeSessionId;
    final policy = KokoroBufferAdmission();
    try {
      for (final chunk in chunks) {
        await _awaitPlaybackCredit(policy, current);
        if (!current()) return;
        _pendingChunksById[chunk.chunkId] = chunk;
        await runtime.prepareChunkPlan(
          sessionId: session,
          generationId: generationId,
          chunks: [
            chunk.toRuntimeChunk(
              rate: _speechRate,
              languageTag: KokoroVoiceCatalog.languageTagForVoice(
                chunk.voiceId,
              ),
              isInitialChunk: false,
              isResumedChunk: false,
            ),
          ],
        );
      }
      if (current()) {
        _remainingPlannedChunkCount = 0;
        _signalBuffer();
      }
    } catch (error) {
      if (!current()) return;
      await _terminatePreparationFailure(
        'Kokoro could not prepare the remaining text: $error',
      );
    }
  }

  Future<void> _terminatePreparationFailure(String message) {
    late int terminalToken;
    return kokoroTerminatePreparationFailure(
      invalidate: () => terminalToken = ++_requestToken,
      isCurrent: () => terminalToken == _requestToken,
      cancel: _cancelActiveGeneration,
      reset: _resetPlaybackState,
      report: (cleanupErrors) {
        if (terminalToken != _requestToken) return;
        _onError?.call(
          cleanupErrors.isEmpty
              ? message
              : '$message; cleanup failed: ${cleanupErrors.join('; ')}',
        );
      },
    );
  }

  @override
  Future<void> pause() async {
    _requestToken += 1;
    _signalBuffer();
    _refillPlanner.cancel();
    _playbackTokenizer?.cancel();
    await _cancelActiveGeneration();
    await _drainPlaybackPreparation();
    _activePlaybackToken = null;
    await _player.pause();
    _emitActivity(const TtsPlaybackActivity.idle());
  }

  @override
  Future<void> stop() async {
    _requestToken += 1;
    _signalBuffer();
    _refillPlanner.cancel();
    _playbackTokenizer?.cancel();
    await _cancelActiveGeneration();
    await _drainPlaybackPreparation();
    await _resetPlaybackState();
  }

  void _handlePosition(Duration position) {
    if (_pruningHistory) return;
    _signalBuffer();
    if (_activePlaybackToken == null ||
        _activeChunks.isEmpty ||
        _waitingForUnderrunRecovery) {
      return;
    }

    final chunkIndex = _currentChunkIndex.clamp(0, _activeChunks.length - 1);
    final chunk = _activeChunks[chunkIndex];
    if (chunk.wordBoundaries.isEmpty || chunk.duration.inMilliseconds <= 0) {
      return;
    }

    final ratio = position.inMilliseconds / chunk.duration.inMilliseconds;
    final clampedRatio = ratio.clamp(0.0, 1.0);
    final wordIndex = (clampedRatio * chunk.wordBoundaries.length)
        .floor()
        .clamp(0, chunk.wordBoundaries.length - 1)
        .toInt();

    _emitProgressForChunkWord(chunkIndex, wordIndex, elapsedInChunk: position);
  }

  void _handleCurrentIndex(int? index) {
    if (_pruningHistory) return;
    if (_activePlaybackToken == null ||
        index == null ||
        _waitingForUnderrunRecovery) {
      return;
    }
    final absoluteIndex = _currentQueueBaseIndex + index;
    if (index < 0 ||
        absoluteIndex >= _activeChunks.length ||
        absoluteIndex == _currentChunkIndex) {
      return;
    }
    _currentChunkIndex = absoluteIndex;
    _signalBuffer();
    _emitProgressForChunkWord(absoluteIndex, 0, elapsedInChunk: Duration.zero);
    _prunePlayedHistory();
  }

  void _prunePlayedHistory() {
    if (_pruneScheduled || _currentChunkIndex <= 0) return;
    _pruneScheduled = true;
    final token = _activePlaybackToken;
    unawaited(
      _mutateAudioQueue(() async {
        try {
          if (token == null || token != _activePlaybackToken) return;
          final count = _player.currentIndex ?? 0;
          if (count <= 0 || count >= _activeChunks.length) return;
          // Remove only completed predecessors. Native current source/position
          // remains installed; suppress intermediate index notifications while the
          // platform rebases indexes, then read its settled index.
          _pruningHistory = true;
          await _player.removeAudioSourceRange(0, count);
          _activeChunks = _activeChunks.sublist(count);
          _currentQueueBaseIndex = 0;
          _currentChunkIndex = _player.currentIndex ?? 0;
          _lastProgressKey = null;
          _recordMetric(
            'playedHistoryPruned',
            value: <String, Object?>{
              'removed': count,
              'retained': _activeChunks.length,
              'positionMs': _player.position.inMilliseconds,
            },
          );
        } finally {
          _pruningHistory = false;
          _pruneScheduled = false;
          _signalBuffer();
        }
      }),
    );
  }

  Future<bool> _mutateAudioQueue(Future<void> Function() action) {
    final request = _requestToken;
    return _audioQueueMutations.run(
      action,
      onFailure: (error, stack) => _handleAudioQueueFailure(request, error),
    );
  }

  Future<void> _handleAudioQueueFailure(int request, Object error) async {
    if (request != _requestToken) return;
    ++_requestToken;
    _refillPlanner.cancel();
    _playbackTokenizer?.cancel();
    final failures = <Object>[error];
    try {
      await _cancelActiveGeneration();
    } catch (cleanupError) {
      failures.add(cleanupError);
    }
    _clearPlaybackStateFields();
    // This handler already owns the playlist-mutation slot. It must not call
    // reset(), which joins that same slot and would wait for itself.
    try {
      await _player.stop();
    } catch (cleanupError) {
      failures.add(cleanupError);
    }
    try {
      await _player.clearAudioSources();
    } catch (cleanupError) {
      failures.add(cleanupError);
    }
    _emitActivity(const TtsPlaybackActivity.idle());
    _onError?.call('Audio queue update failed: ${failures.join('; ')}');
  }

  void _emitProgressForChunkWord(
    int chunkIndex,
    int wordIndex, {
    required Duration elapsedInChunk,
  }) {
    if (chunkIndex < 0 || chunkIndex >= _activeChunks.length) {
      return;
    }
    final chunk = _activeChunks[chunkIndex];
    if (wordIndex < 0 || wordIndex >= chunk.wordBoundaries.length) {
      return;
    }

    final progressKey = '$chunkIndex:$wordIndex';
    if (_lastProgressKey == progressKey) {
      return;
    }

    _lastProgressKey = progressKey;
    final boundary = chunk.wordBoundaries[wordIndex];
    final absoluteWordIndex = chunk.startWordIndex + wordIndex;
    final segmentRange = chunk.segmentRangeForWordIndex(absoluteWordIndex);
    _onProgress?.call(
      TtsProgressUpdate(
        startOffset: chunk.startOffset + boundary.start,
        endOffset: chunk.startOffset + boundary.end,
        word: boundary.word,
        documentId: chunk.documentId,
        chunkId: chunk.chunkId,
        segmentId: segmentRange?.segmentId ?? chunk.segmentIds.firstOrNull,
        wordStartIndex: absoluteWordIndex,
        wordEndIndex: absoluteWordIndex + 1,
        elapsedInChunk: elapsedInChunk,
        chunkAudioDuration: chunk.duration,
        voiceId: chunk.voiceId,
        rate: chunk.rate,
        routeId: chunk.routeId,
        castId: chunk.castId,
        dialogueSpanId: chunk.dialogueSpanId,
      ),
    );
  }

  void _emitFinalProgress() {
    if (_activeChunks.isEmpty) {
      return;
    }
    final lastChunkIndex = _activeChunks.length - 1;
    final lastChunk = _activeChunks[lastChunkIndex];
    if (lastChunk.wordBoundaries.isEmpty) {
      return;
    }
    _emitProgressForChunkWord(
      lastChunkIndex,
      lastChunk.wordBoundaries.length - 1,
      elapsedInChunk: lastChunk.duration,
    );
  }

  void _handleRuntimeEvent(SpeechRuntimeEvent event) {
    if (event.sessionId != null &&
        _activeSessionId != null &&
        event.sessionId != _activeSessionId) {
      return;
    }

    switch (event.type) {
      case SpeechRuntimeEventType.runtimeInitialized:
      case SpeechRuntimeEventType.sessionActivated:
        return;
      case SpeechRuntimeEventType.chunkQueued:
        if (event.chunkId != null) {
          _queuedAtByChunkId.putIfAbsent(event.chunkId!, () => event.emittedAt);
        }
        _emitBufferingActivity();
      case SpeechRuntimeEventType.chunkCacheHit:
        if (event.chunkId != null) {
          _recordMetric(
            'chunkCacheHit',
            chunkId: event.chunkId,
            voiceId: event.voiceId,
            value: <String, Object?>{
              'cacheHit': true,
              'routeId': event.routeId,
              'castId': event.castId,
              'dialogueSpanId': event.dialogueSpanId,
            },
          );
        }
        _emitBufferingActivity();
      case SpeechRuntimeEventType.chunkStageChanged:
        _emitBufferingActivity();
      case SpeechRuntimeEventType.chunkReady:
        unawaited(_handleRuntimeChunkReady(event));
      case SpeechRuntimeEventType.chunkFailed:
        _handleRuntimeChunkFailure(event);
      case SpeechRuntimeEventType.sessionCancelled:
        _handleRuntimeSessionCancelled(event);
      case SpeechRuntimeEventType.runtimeFailed:
        _emitActivity(const TtsPlaybackActivity.idle());
        _onError?.call(
          'Kokoro runtime failed: ${event.message ?? event.errorCode ?? 'Unknown runtime failure.'}',
        );
      case SpeechRuntimeEventType.runtimeShutdown:
        _emitActivity(const TtsPlaybackActivity.idle());
    }
  }

  void _emitBufferingActivity() {
    final totalChunkCount = _expectedChunkCount;
    if (_activePlaybackToken == null) {
      _emitActivity(
        _playbackActivityForPhase(
          TtsPlaybackPhase.buffering,
          totalChunkCount: totalChunkCount,
        ),
      );
      return;
    }

    _emitActivity(
      _playbackActivityForPhase(
        TtsPlaybackPhase.playing,
        bufferedChunkCount: _activeChunks.length,
        totalChunkCount: totalChunkCount,
      ),
    );
  }

  Future<void> _handleRuntimeChunkReady(SpeechRuntimeEvent event) async {
    if (event.generationId != null &&
        _activeGenerationId != null &&
        event.generationId != _activeGenerationId) {
      return;
    }
    final chunkId = event.chunkId;
    if (chunkId == null) {
      return;
    }

    final chunk = _pendingChunksById.remove(chunkId);
    if (chunk == null || event.audioPath == null || event.duration == null) {
      return;
    }

    final playbackChunk = _PlaybackChunk(
      chunkId: chunk.chunkId,
      boundaryClass: chunk.boundaryClass,
      documentId: chunk.documentId,
      segmentIds: chunk.segmentIds,
      segmentRanges: chunk.segmentRanges,
      startWordIndex: chunk.startWordIndex,
      endWordIndex: chunk.endWordIndex,
      startOffset: chunk.startOffset,
      wordBoundaries: chunk.wordBoundaries,
      duration: event.duration!,
      filePath: event.audioPath!,
      leadingSilence: event.leadingSilence ?? Duration.zero,
      trailingSilence: event.trailingSilence ?? Duration.zero,
      voiceId: chunk.voiceId,
      rate: _speechRate,
      routeId: chunk.routeId,
      castId: chunk.castId,
      dialogueSpanId: chunk.dialogueSpanId,
    );

    final wasCacheHit = event.cacheHit ?? false;
    if (!wasCacheHit) {
      final queuedAt = _queuedAtByChunkId[chunkId];
      if (queuedAt != null && event.duration!.inMilliseconds > 0) {
        final elapsedMillis = event.emittedAt
            .difference(queuedAt)
            .inMilliseconds;
        _recordMetric(
          'generationRealTimeFactor',
          chunkId: chunkId,
          voiceId: chunk.voiceId,
          value: <String, Object?>{
            'factor': elapsedMillis / event.duration!.inMilliseconds,
            'generationMillis': elapsedMillis,
            'audioMillis': event.duration!.inMilliseconds,
            'routeId': chunk.routeId,
            'castId': chunk.castId,
            'dialogueSpanId': chunk.dialogueSpanId,
          },
        );
      }
      _recordMetric(
        'chunkRegenerated',
        chunkId: chunkId,
        voiceId: chunk.voiceId,
        value: true,
      );
    }
    _recordMetric(
      'boundaryCorrectionApplied',
      chunkId: chunkId,
      voiceId: chunk.voiceId,
      value: event.boundaryCorrectionApplied ?? false,
    );
    _recordMetric(
      'joinSilenceBeforeMs',
      chunkId: chunkId,
      voiceId: chunk.voiceId,
      value: event.joinSilenceBefore?.inMilliseconds ?? 0,
    );
    _recordMetric(
      'joinSilenceAfterMs',
      chunkId: chunkId,
      voiceId: chunk.voiceId,
      value: event.joinSilenceAfter?.inMilliseconds ?? 0,
    );

    if (chunkId == _firstPendingChunkId) {
      _firstPendingChunkId = null;
      _startupFirstChunk = playbackChunk;
      _signalBuffer();
      final completer = _firstChunkCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(playbackChunk);
      }
      return;
    }

    if (_activePlaybackToken == null) {
      _stageReadyChunk(playbackChunk);
      return;
    }

    _stageReadyChunk(playbackChunk);
    await _flushStagedReadyChunksToActiveQueue(
      generationId: event.generationId!,
    );
    final recoveryPlan = kokoroPlanForwardRecovery(_playbackQueueSnapshot());
    if (_activePlaybackToken != null &&
        _player.playerState.processingState == ProcessingState.completed &&
        recoveryPlan.action ==
            KokoroForwardRecoveryAction.resumeFromNextBufferedChunk) {
      _waitingForUnderrunRecovery = true;
    }
    await _resumeAfterUnderrunIfPossible();
  }

  void _handleRuntimeChunkFailure(SpeechRuntimeEvent event) {
    if (event.generationId != null &&
        _activeGenerationId != null &&
        event.generationId != _activeGenerationId) {
      return;
    }
    final chunkId = event.chunkId;
    if (chunkId == null) {
      return;
    }
    final failedChunk = _pendingChunksById.remove(chunkId);
    final failedWasPriorityChunk = chunkId == _firstPendingChunkId;
    final generationId = event.generationId;
    if (failedChunk != null && generationId != null) {
      _recordMetric(
        'recoverableChunkFailureDetected',
        chunkId: failedChunk.chunkId,
        voiceId: failedChunk.voiceId,
        value: <String, Object?>{
          'failedWasPriorityChunk': failedWasPriorityChunk,
          'duringStartupWarmup': _activePlaybackToken == null,
          'message': event.message,
          'routeId': failedChunk.routeId,
          'castId': failedChunk.castId,
          'dialogueSpanId': failedChunk.dialogueSpanId,
        },
      );
      unawaited(
        _attemptRecoverableChunkFailure(
          failedChunk: failedChunk,
          generationId: generationId,
          failedWasPriorityChunk: failedWasPriorityChunk,
          failureMessage: event.message,
        ),
      );
      return;
    }

    if (failedWasPriorityChunk) {
      final completer = _firstChunkCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          StateError(event.message ?? 'Kokoro failed to prepare audio.'),
        );
      }
      return;
    }

    if (_activePlaybackToken == null || _activeChunks.isEmpty) {
      _onError?.call(
        'Kokoro synthesis failed: ${event.message ?? 'Unknown worker failure.'}',
      );
      return;
    }

    _onError?.call(
      'Kokoro could not prepare a later chunk: '
      '${event.message ?? 'Unknown worker failure.'}',
    );
  }

  Future<void> _attemptRecoverableChunkFailure({
    required _QueuedChunk failedChunk,
    required String generationId,
    required bool failedWasPriorityChunk,
    required String? failureMessage,
  }) async {
    final speechRuntime = _speechRuntime;
    final sessionId = _activeSessionId;
    if (speechRuntime == null ||
        sessionId == null ||
        generationId != _activeGenerationId) {
      return;
    }

    // A bounded planner has an unmaterialized suffix. Rebuilding only admitted
    // chunks would silently truncate that suffix, so fail this session honestly.
    if (_remainingPlannedChunkCount > 0) {
      final error = StateError(
        'Synthesis failed before the remaining passage was prepared. Restart playback to retry.',
      );
      final first = _firstChunkCompleter;
      if (first != null && !first.isCompleted) first.completeError(error);
      _requestToken += 1;
      _refillPlanner.cancel();
      _playbackTokenizer?.cancel();
      await speechRuntime.cancelGeneration(generationId);
      await _resetPlaybackState();
      _onError?.call(error.message);
      return;
    }

    final recoveryChunks = await _buildRecoverableFailureChunks(failedChunk);
    if (recoveryChunks.isEmpty) {
      if (failedWasPriorityChunk) {
        final completer = _firstChunkCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(
            StateError(
              failureMessage ??
                  'Kokoro failed to prepare startup audio for this passage.',
            ),
          );
        }
      } else {
        _onError?.call(
          'Kokoro could not prepare a later chunk: recoverable fallback was unavailable for "${failedChunk.text}".',
        );
      }
      return;
    }

    _stagedReadyChunks.removeWhere(
      (chunk) => chunk.startWordIndex >= failedChunk.startWordIndex,
    );
    await _discardFutureBufferedChunksFromStartWordIndex(
      failedChunk.startWordIndex,
    );
    if (generationId != _activeGenerationId) return;

    final remainingPending =
        _pendingChunksById.values
            .where(
              (chunk) => chunk.generationOrder > failedChunk.generationOrder,
            )
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.generationOrder.compareTo(right.generationOrder),
          );

    final rebuiltPending = <_QueuedChunk>[
      ...recoveryChunks,
      for (final chunk in remainingPending) chunk,
    ];

    final rebuiltWithFreshIds = <_QueuedChunk>[];
    for (var index = 0; index < rebuiltPending.length; index += 1) {
      final chunk = rebuiltPending[index];
      rebuiltWithFreshIds.add(
        chunk.copyWith(
          chunkId:
              '${failedChunk.chunkId}_recovery_${DateTime.now().microsecondsSinceEpoch}_$index',
          generationOrder: index,
        ),
      );
    }

    await speechRuntime.cancelGeneration(generationId);

    final newGenerationId =
        '${generationId}_recovery_${DateTime.now().microsecondsSinceEpoch}';
    _activeGenerationId = newGenerationId;
    if (failedWasPriorityChunk) {
      _firstPendingChunkId = rebuiltWithFreshIds.first.chunkId;
    }
    _pendingChunksById = <String, _QueuedChunk>{
      for (final chunk in rebuiltWithFreshIds) chunk.chunkId: chunk,
    };
    _queuedAtByChunkId.removeWhere(
      (chunkId, _) => !_pendingChunksById.containsKey(chunkId),
    );
    _expectedChunkCount = _activeChunks.length + rebuiltWithFreshIds.length;
    _remainingPlannedChunkCount = 0;

    await speechRuntime.prepareChunkPlan(
      sessionId: sessionId,
      generationId: newGenerationId,
      chunks: rebuiltWithFreshIds
          .map(
            (chunk) => chunk.toRuntimeChunk(
              rate: _speechRate,
              languageTag: KokoroVoiceCatalog.languageTagForVoice(
                chunk.voiceId,
              ),
              isInitialChunk: false,
              isResumedChunk: false,
            ),
          )
          .toList(growable: false),
    );
    _emitBufferingActivity();
  }

  Future<List<_QueuedChunk>> _buildRecoverableFailureChunks(
    _QueuedChunk failedChunk,
  ) async {
    if (failedChunk.fallbackRecoveryDepth >= 2) {
      return const <_QueuedChunk>[];
    }

    final slices = kokoroPlanRecoverableChunkSlices(
      wordBoundaries: failedChunk.wordBoundaries
          .map(
            (boundary) => KokoroRecoveryWordBoundary(
              start: boundary.start,
              end: boundary.end,
              word: boundary.word,
            ),
          )
          .toList(growable: false),
    );
    if (slices.isEmpty) {
      return const <_QueuedChunk>[];
    }

    final recoveredChunks = <_QueuedChunk>[];
    for (var index = 0; index < slices.length; index += 1) {
      recoveredChunks.add(
        await _buildRecoverableFailureChunkPiece(
          failedChunk: failedChunk,
          slice: slices[index],
          sliceIndex: index,
        ),
      );
    }
    return recoveredChunks;
  }

  Future<_QueuedChunk> _buildRecoverableFailureChunkPiece({
    required _QueuedChunk failedChunk,
    required KokoroRecoveryWordSlice slice,
    required int sliceIndex,
  }) async {
    final localStartBoundary =
        failedChunk.wordBoundaries[slice.startWordOffset];
    final localEndBoundary =
        failedChunk.wordBoundaries[slice.endWordOffset - 1];
    final pieceText = failedChunk.text.substring(
      localStartBoundary.start,
      localEndBoundary.end,
    );
    final pieceWordBoundaries = _buildWordBoundaries(pieceText);
    final pieceStartWordIndex =
        failedChunk.startWordIndex + slice.startWordOffset;
    final pieceEndWordIndex = failedChunk.startWordIndex + slice.endWordOffset;
    final pieceSegmentRanges = _sliceSegmentRanges(
      segmentRanges: failedChunk.segmentRanges,
      startWordIndex: pieceStartWordIndex,
      endWordIndex: pieceEndWordIndex,
    );
    final tokenization = await _tokenizeSpeakText(
      pieceText,
      KokoroVoiceCatalog.languageTagForVoice(failedChunk.voiceId),
    );

    return _QueuedChunk(
      chunkId: '${failedChunk.chunkId}_recover_$sliceIndex',
      generationOrder: sliceIndex,
      segmentIds: pieceSegmentRanges
          .map((range) => range.segmentId)
          .toList(growable: false),
      cacheKey: _fallbackCacheKey(
        pieceText,
        voiceId: failedChunk.voiceId,
        rate: _speechRate,
        normalizationVersion: failedChunk.normalizationVersion,
      ),
      voiceId: failedChunk.voiceId,
      boundaryClass: sliceIndex == 0
          ? failedChunk.boundaryClass
          : BreakClass.none,
      documentId: failedChunk.documentId,
      normalizationVersion: failedChunk.normalizationVersion,
      text: pieceText,
      capabilityProfileId: '${failedChunk.capabilityProfileId}:fallback',
      engineSpeakText: pieceText,
      startOffset: failedChunk.startOffset + localStartBoundary.start,
      startWordIndex: pieceStartWordIndex,
      endWordIndex: pieceEndWordIndex,
      tokens: tokenization,
      segmentRanges: pieceSegmentRanges,
      ttsSegments: <TtsArtifactSegment>[
        TtsArtifactSegment(
          segmentId: pieceSegmentRanges.first.segmentId,
          speakText: pieceText,
          pronunciationArtifacts: const <RealizedPronunciationArtifact>[],
        ),
      ],
      translatedPronunciationArtifacts:
          const <KokoroTranslatedPronunciationArtifact>[],
      translatedPayloadUnits: const <KokoroEnginePayloadUnit>[],
      missingFallbackWordCount: pieceWordBoundaries.length,
      wordBoundaries: pieceWordBoundaries,
      finalPhonemeString: '',
      phonemeTraceLines: <String>[
        'recoveryFallback sourceChunk=${failedChunk.chunkId} depth=${failedChunk.fallbackRecoveryDepth + 1}',
      ],
      routeId: failedChunk.routeId,
      castId: failedChunk.castId,
      dialogueSpanId: failedChunk.dialogueSpanId,
      fallbackRecoveryDepth: failedChunk.fallbackRecoveryDepth + 1,
    );
  }

  void _handleRuntimeSessionCancelled(SpeechRuntimeEvent event) {
    if (event.generationId != null &&
        _activeGenerationId != null &&
        event.generationId != _activeGenerationId) {
      return;
    }
    final pendingChunkId = _firstPendingChunkId;
    if (pendingChunkId == null) {
      return;
    }
    _pendingChunksById.remove(pendingChunkId);
    final completer = _firstChunkCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('Kokoro generation was cancelled.'));
    }
  }

  Future<void> _cancelActiveGeneration() async {
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      _playbackLease?.cancelPending();
      _signalBuffer();
      return;
    }

    final completer = _firstChunkCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('Kokoro generation was cancelled.'));
    }

    final cancellation = _speechRuntime?.cancelSession(
      sessionId,
      reasonCode: 'cancelled',
    );
    _playbackLease?.cancelPending();
    await cancellation;
    _activeGenerationId = null;
    _firstPendingChunkId = null;
    _firstChunkCompleter = null;
    _pendingChunksById = <String, _QueuedChunk>{};
    _queuedAtByChunkId.clear();
    _expectedChunkCount = 0;
    _remainingPlannedChunkCount = 0;
    _waitingForUnderrunRecovery = false;
    _lastRecordedBufferPressure = TtsBufferPressure.none;
    _stagedReadyChunks.clear();
    // The generation changed after the earlier pause/stop signal. Export
    // admission must observe the settled state even if the player emits no
    // further position notification after pausing.
    _signalBuffer();
  }

  Future<List<_QueuedChunk>> _prepareChunks(
    TtsSpeakRequest request, {
    required String languageTag,
    KokoroTokenizationWorker? tokenWorker,
  }) async {
    final chunkPlan = request.chunkPlan;
    if (chunkPlan != null && chunkPlan.chunks.isNotEmpty) {
      return _prepareChunksFromPlan(
        request,
        languageTag: languageTag,
        tokenWorker: tokenWorker,
      );
    }

    final text = request.text;
    final units = RegExp(r'\S+\s*')
        .allMatches(text)
        .map(
          (match) => _ChunkUnit(
            text: text.substring(match.start, match.end),
            startOffset: match.start,
          ),
        )
        .toList(growable: false);

    return _buildChunksFromUnits(
      units.isEmpty
          ? <_ChunkUnit>[_ChunkUnit(text: text, startOffset: 0)]
          : units,
      documentId: request.documentId ?? 'legacy-runtime',
      normalizationVersion:
          request.normalizationVersion ?? _fallbackNormalizationVersion,
      baseStartWordIndex: 0,
      tokenWorker: tokenWorker,
      languageTag: languageTag,
    );
  }

  Future<List<_QueuedChunk>> _prepareChunksFromPlan(
    TtsSpeakRequest request, {
    required String languageTag,
    KokoroTokenizationWorker? tokenWorker,
  }) async {
    final chunkPlan = request.chunkPlan!;
    final prepared = <_QueuedChunk>[];
    var searchOffset = 0;

    for (final spec in chunkPlan.chunks) {
      final startOffset = _findChunkStartOffset(
        fullText: request.text,
        searchOffset: searchOffset,
        chunkText: spec.speakText,
      );
      final tokenization = await (tokenWorker ?? _playbackTokenizer!).prepare(
        spec,
        languageTag,
      );
      final translatedChunk = tokenization.translatedChunk!;
      final chunk = _QueuedChunk(
        chunkId: spec.chunkId,
        generationOrder: prepared.length,
        segmentIds: spec.segmentIds,
        cacheKey: spec.cacheKey,
        voiceId: spec.voiceId,
        boundaryClass: spec.boundaryClass,
        documentId: request.documentId ?? 'unknown-document',
        normalizationVersion:
            request.normalizationVersion ?? _fallbackNormalizationVersion,
        text: spec.speakText,
        capabilityProfileId: translatedChunk.capabilityProfileId,
        engineSpeakText: translatedChunk.speakText,
        startOffset: startOffset,
        startWordIndex: spec.startWordIndex,
        endWordIndex: spec.endWordIndex,
        segmentRanges: _segmentRangesForChunk(spec, request.speechDocument),
        ttsSegments: spec.ttsSegments,
        translatedPronunciationArtifacts:
            translatedChunk.pronunciationArtifacts,
        translatedPayloadUnits: translatedChunk.payloadUnits,
        missingFallbackWordCount: translatedChunk.missingFallbackWordCount,
        tokens: tokenization.tokens,
        wordBoundaries: _buildWordBoundaries(spec.speakText),
        finalPhonemeString: tokenization.finalPhonemeString,
        phonemeTraceLines: tokenization.phonemeTraceLines,
        routeId: spec.routeId,
        castId: spec.castId,
        dialogueSpanId: spec.dialogueSpanId,
        fallbackRecoveryDepth: 0,
      );
      prepared.add(chunk);
      searchOffset = _nextChunkSearchOffset(
        fullTextLength: request.text.length,
        startOffset: startOffset,
        chunkTextLength: spec.speakText.length,
      );
    }

    return prepared;
  }

  Future<_PreparedPlannedChunk> _preparePlannedChunk({
    required TtsSpeakRequest request,
    required ChunkSpec spec,
    required int searchOffset,
    required String languageTag,
    KokoroTokenizationWorker? tokenWorker,
  }) async {
    final startOffset = _findChunkStartOffset(
      fullText: request.text,
      searchOffset: searchOffset,
      chunkText: spec.speakText,
    );
    final tokenization = await (tokenWorker ?? _playbackTokenizer!).prepare(
      spec,
      languageTag,
    );
    final translatedChunk = tokenization.translatedChunk!;
    return _PreparedPlannedChunk(
      chunk: _QueuedChunk(
        chunkId: spec.chunkId,
        generationOrder: spec.startSegmentIndex,
        segmentIds: spec.segmentIds,
        cacheKey: spec.cacheKey,
        voiceId: spec.voiceId,
        boundaryClass: spec.boundaryClass,
        documentId: request.documentId ?? 'unknown-document',
        normalizationVersion:
            request.normalizationVersion ?? _fallbackNormalizationVersion,
        text: spec.speakText,
        capabilityProfileId: translatedChunk.capabilityProfileId,
        engineSpeakText: translatedChunk.speakText,
        startOffset: startOffset,
        startWordIndex: spec.startWordIndex,
        endWordIndex: spec.endWordIndex,
        segmentRanges: _segmentRangesForChunk(spec, request.speechDocument),
        ttsSegments: spec.ttsSegments,
        translatedPronunciationArtifacts:
            translatedChunk.pronunciationArtifacts,
        translatedPayloadUnits: translatedChunk.payloadUnits,
        missingFallbackWordCount: translatedChunk.missingFallbackWordCount,
        tokens: tokenization.tokens,
        wordBoundaries: _buildWordBoundaries(spec.speakText),
        finalPhonemeString: tokenization.finalPhonemeString,
        phonemeTraceLines: tokenization.phonemeTraceLines,
        routeId: spec.routeId,
        castId: spec.castId,
        dialogueSpanId: spec.dialogueSpanId,
        fallbackRecoveryDepth: 0,
      ),
      nextSearchOffset: _nextChunkSearchOffset(
        fullTextLength: request.text.length,
        startOffset: startOffset,
        chunkTextLength: spec.speakText.length,
      ),
    );
  }

  Future<_PreparedPlannedChunkWindow> _preparePlannedChunkWindow({
    required TtsSpeakRequest request,
    required List<ChunkSpec> specs,
    required int initialSearchOffset,
    required String languageTag,
    KokoroTokenizationWorker? tokenWorker,
  }) async {
    final chunks = <_QueuedChunk>[];
    var searchOffset = initialSearchOffset;
    for (final spec in specs) {
      final prepared = await _preparePlannedChunk(
        tokenWorker: tokenWorker,
        request: request,
        spec: spec,
        searchOffset: searchOffset,
        languageTag: languageTag,
      );
      chunks.add(prepared.chunk);
      searchOffset = prepared.nextSearchOffset;
    }
    return _PreparedPlannedChunkWindow(
      chunks: chunks,
      nextSearchOffset: searchOffset,
    );
  }

  Future<List<_QueuedChunk>> _buildChunksFromUnits(
    List<_ChunkUnit> units, {
    required String documentId,
    required String normalizationVersion,
    required int baseStartWordIndex,
    required String languageTag,
    KokoroTokenizationWorker? tokenWorker,
  }) async {
    final chunks = <_QueuedChunk>[];
    final currentUnits = <_ChunkUnit>[];
    var runningWordIndex = baseStartWordIndex;

    Future<void> flushCurrent() async {
      if (currentUnits.isEmpty) {
        return;
      }
      final text = currentUnits.map((item) => item.text).join();
      final wordCount = _buildWordBoundaries(text).length;
      final tokenization = await _tokenizeSpeakText(
        text,
        languageTag,
        tokenWorker: tokenWorker,
      );
      chunks.add(
        _QueuedChunk(
          chunkId: 'chunk_${chunks.length}',
          generationOrder: chunks.length,
          segmentIds: <String>['chunk_${chunks.length}'],
          cacheKey: _fallbackCacheKey(
            text,
            voiceId: _selectedVoiceId,
            rate: _speechRate,
            normalizationVersion: normalizationVersion,
          ),
          voiceId: _selectedVoiceId,
          boundaryClass: chunks.isEmpty ? BreakClass.none : BreakClass.sentence,
          documentId: documentId,
          normalizationVersion: normalizationVersion,
          text: text,
          capabilityProfileId: 'kokoro:${Platform.operatingSystem}:legacy',
          engineSpeakText: text,
          startOffset: currentUnits.first.startOffset,
          startWordIndex: runningWordIndex,
          endWordIndex: runningWordIndex + wordCount,
          tokens: tokenization,
          segmentRanges: <_ChunkSegmentRange>[
            _ChunkSegmentRange(
              segmentId: 'chunk_${chunks.length}',
              startWordIndex: runningWordIndex,
              endWordIndex: runningWordIndex + wordCount,
            ),
          ],
          ttsSegments: <TtsArtifactSegment>[
            TtsArtifactSegment(
              segmentId: 'chunk_${chunks.length}',
              speakText: text,
              pronunciationArtifacts: const <RealizedPronunciationArtifact>[],
            ),
          ],
          translatedPronunciationArtifacts:
              const <KokoroTranslatedPronunciationArtifact>[],
          translatedPayloadUnits: const <KokoroEnginePayloadUnit>[],
          missingFallbackWordCount: wordCount,
          wordBoundaries: _buildWordBoundaries(text),
          finalPhonemeString: '',
          phonemeTraceLines: const <String>[],
          routeId: null,
          castId: null,
          dialogueSpanId: null,
          fallbackRecoveryDepth: 0,
        ),
      );
      runningWordIndex += wordCount;
      currentUnits.clear();
    }

    for (final unit in units) {
      currentUnits.add(unit);
      if (currentUnits.length >= _targetChunkWordCount) {
        await flushCurrent();
      }
    }
    await flushCurrent();

    return chunks;
  }

  Future<void> _resetPlaybackState() async {
    await _playbackReset.reset();
  }

  late final _playbackReset = KokoroPlaybackResetBarrier(
    _resetPlaybackStateInternal,
  );

  Future<void> _resetPlaybackStateInternal() async {
    _activePlaybackToken = null;
    await _audioQueueMutations.drained;
    _clearPlaybackStateFields();
    await _player.stop();
    await _player.clearAudioSources();
    _emitActivity(const TtsPlaybackActivity.idle());
  }

  void _clearPlaybackStateFields() {
    _activePlaybackToken = null;
    _currentChunkIndex = 0;
    _currentQueueBaseIndex = 0;
    _activeChunks = const <_PlaybackChunk>[];
    _lastProgressKey = null;
    _activeGenerationId = null;
    _signalBuffer();
    _activeDocumentId = null;
    _activeSessionId = null;
    _firstPendingChunkId = null;
    _firstChunkCompleter = null;
    _pendingChunksById = <String, _QueuedChunk>{};
    _queuedAtByChunkId.clear();
    _expectedChunkCount = 0;
    _remainingPlannedChunkCount = 0;
    _waitingForUnderrunRecovery = false;
    _lastRecordedBufferPressure = TtsBufferPressure.none;
    _stagedReadyChunks.clear();
  }

  Future<List<int>> _tokenizeSpeakText(
    String text,
    String languageTag, {
    KokoroTokenizationWorker? tokenWorker,
  }) async {
    return (await (tokenWorker ?? _playbackTokenizer!).tokenizeText(
      text,
      languageTag,
    )).tokens;
  }

  Future<void> _resumeAfterUnderrunIfPossible() async {
    if (!_waitingForUnderrunRecovery) {
      return;
    }

    final recoveryPlan = kokoroPlanForwardRecovery(_playbackQueueSnapshot());
    if (recoveryPlan.action !=
        KokoroForwardRecoveryAction.resumeFromNextBufferedChunk) {
      return;
    }

    final nextChunkIndex = recoveryPlan.nextChunkIndex!;
    final nextRelativeIndex = nextChunkIndex - _currentQueueBaseIndex;
    _waitingForUnderrunRecovery = false;
    _currentChunkIndex = nextChunkIndex;

    await _player.setVolume(_volume);
    final recoveryToken = _activePlaybackToken;
    await _player.seek(Duration.zero, index: nextRelativeIndex);
    if (recoveryToken != _activePlaybackToken) return;
    _prunePlayedHistory();
    _emitProgressForChunkWord(nextChunkIndex, 0, elapsedInChunk: Duration.zero);
    _emitActivity(
      _playbackActivityForPhase(
        TtsPlaybackPhase.playing,
        bufferedChunkCount: _activeChunks.length - nextChunkIndex,
        totalChunkCount: _expectedChunkCount,
      ),
    );
    await _player.play();
  }

  Future<void> _awaitStartupWarmup({required _PlaybackChunk firstChunk}) async {
    final deadline = DateTime.now().add(_startupWarmupMaxWait);
    while (_activeGenerationId != null && _activePlaybackToken == null) {
      if (_isStartupWarmEnough(firstChunk)) {
        return;
      }
      if (KokoroBufferAdmission().startupCapacityExhausted(
        audioLead: _preparedLead(),
        bufferedChunkCount: _startupBufferedChunks(firstChunk).length,
        pendingChunkCount: _pendingChunksById.length,
        remainingPlannedChunkCount: _remainingPlannedChunkCount,
        playerSpeed: _player.speed,
      )) {
        throw StateError(
          'The startup target requires more than 64 audio chunks.',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        _recordMetric(
          'startupWarmupTimedOut',
          chunkId: firstChunk.chunkId,
          voiceId: firstChunk.voiceId,
          value: <String, Object?>{
            'bufferedChunkCount': _startupBufferedChunks(firstChunk).length,
            'pendingChunkCount': _pendingChunksById.length,
            'remainingPlannedChunkCount': _remainingPlannedChunkCount,
          },
        );
        throw TimeoutException('Startup buffer target not reached.');
      }
      await Future<void>.delayed(_startupWarmupPollInterval);
    }
  }

  bool _isStartupWarmEnough(_PlaybackChunk firstChunk) {
    final startupBufferedChunks = _startupBufferedChunks(firstChunk);
    return kokoroIsStartupWarmEnough(
      bufferedChunkCount: startupBufferedChunks.length,
      bufferedLeadTime: _initialBufferedQueueLeadTime(startupBufferedChunks),
      pendingChunkCount: _pendingChunksById.length,
      remainingPlannedChunkCount: _remainingPlannedChunkCount,
      playerSpeed: _player.speed,
    );
  }

  List<_PlaybackChunk> _startupBufferedChunks(_PlaybackChunk firstChunk) {
    final ordered = kokoroBuildInitialPlaybackQueue(
      firstChunk: firstChunk,
      stagedChunks: _stagedReadyChunks,
      chunkIdOf: (c) => c.chunkId,
      startWordIndexOf: (c) => c.startWordIndex,
      startOffsetOf: (c) => c.startOffset,
    );
    final contiguous = <_PlaybackChunk>[firstChunk];
    var end = firstChunk.endWordIndex;
    for (final chunk in ordered.skip(1)) {
      if (chunk.startWordIndex != end) break;
      contiguous.add(chunk);
      end = chunk.endWordIndex;
    }
    return contiguous;
  }

  void _stageReadyChunk(_PlaybackChunk playbackChunk) {
    final existingIndex = _stagedReadyChunks.indexWhere(
      (chunk) => chunk.chunkId == playbackChunk.chunkId,
    );
    if (existingIndex >= 0) {
      _stagedReadyChunks[existingIndex] = playbackChunk;
    } else {
      _stagedReadyChunks.add(playbackChunk);
    }
    _stagedReadyChunks.sort(_comparePlaybackChunkOrder);
    _signalBuffer();
  }

  List<_PlaybackChunk> _drainStagedReadyChunks() {
    if (_stagedReadyChunks.isEmpty) {
      return const <_PlaybackChunk>[];
    }
    final drained = List<_PlaybackChunk>.from(_stagedReadyChunks);
    _stagedReadyChunks.clear();
    return drained;
  }

  Future<void> _flushStagedReadyChunksToActiveQueue({
    required String generationId,
  }) async {
    final stagedChunks = _drainStagedReadyChunks();
    for (final chunk in stagedChunks) {
      await _appendReadyChunkToActiveQueue(chunk, generationId: generationId);
    }
  }

  Future<void> _appendReadyChunkToActiveQueue(
    _PlaybackChunk playbackChunk, {
    required String? generationId,
  }) async {
    await _mutateAudioQueue(() async {
      if (generationId != _activeGenerationId) {
        return;
      }
      if (_activePlaybackToken == null) {
        _stageReadyChunk(playbackChunk);
        return;
      }
      if (_activeChunks.any(
        (chunk) => chunk.chunkId == playbackChunk.chunkId,
      )) {
        return;
      }

      if (playbackChunk.startWordIndex != _nextReadyWord) {
        _stageReadyChunk(playbackChunk);
        return;
      }
      final insertIndex = kokoroPlaybackInsertIndex<_PlaybackChunk>(
        activeChunks: _activeChunks,
        incomingChunk: playbackChunk,
        chunkIdOf: (chunk) => chunk.chunkId,
        startWordIndexOf: (chunk) => chunk.startWordIndex,
        startOffsetOf: (chunk) => chunk.startOffset,
      );
      if (insertIndex <= _currentChunkIndex) {
        _recordMetric(
          'lateChunkDiscarded',
          chunkId: playbackChunk.chunkId,
          voiceId: playbackChunk.voiceId,
          value: <String, Object?>{
            'insertIndex': insertIndex,
            'currentChunkIndex': _currentChunkIndex,
            'startWordIndex': playbackChunk.startWordIndex,
          },
        );
        return;
      }

      final previousActiveChunkCount = _activeChunks.length;
      _activeChunks = List<_PlaybackChunk>.from(_activeChunks)
        ..insert(insertIndex, playbackChunk);
      final relativeInsertIndex = insertIndex - _currentQueueBaseIndex;
      if (relativeInsertIndex >= previousActiveChunkCount) {
        await _player.addAudioSource(AudioSource.file(playbackChunk.filePath));
      } else {
        await _player.insertAudioSource(
          relativeInsertIndex,
          AudioSource.file(playbackChunk.filePath),
        );
      }
      _nextReadyWord = playbackChunk.endWordIndex;
      _signalBuffer();
      _recordMetric(
        'prefetchLeadTimeMs',
        chunkId: playbackChunk.chunkId,
        voiceId: playbackChunk.voiceId,
        value: <String, Object?>{
          'leadTimeMs': _playableBufferedLeadTime().inMilliseconds,
          'pcmLeadTimeMs': _bufferedLeadTime().inMilliseconds,
          'playerSpeed': _player.speed,
          'insertIndex': insertIndex,
          'activeChunkCount': _activeChunks.length,
        },
      );
      _emitActivity(
        _playbackActivityForPhase(
          TtsPlaybackPhase.playing,
          bufferedChunkCount: _activeChunks.length,
          totalChunkCount: _expectedChunkCount,
        ),
      );
    });
  }

  Future<void> _discardFutureBufferedChunksFromStartWordIndex(
    int replacementStartWordIndex,
  ) async {
    await _mutateAudioQueue(() async {
      final pruneIndex = kokoroFirstFutureReplacementIndex<_PlaybackChunk>(
        activeChunks: _activeChunks,
        currentChunkIndex: _currentChunkIndex,
        replacementStartWordIndex: replacementStartWordIndex,
        startWordIndexOf: (chunk) => chunk.startWordIndex,
      );
      if (pruneIndex == null) {
        return;
      }

      final prunedChunks = _activeChunks.sublist(pruneIndex);
      _nextReadyWord = prunedChunks.first.startWordIndex;
      _activeChunks = List<_PlaybackChunk>.from(_activeChunks.take(pruneIndex));
      if (_activePlaybackToken != null) {
        final startRelativeIndex = pruneIndex - _currentQueueBaseIndex;
        final endRelativeIndex = startRelativeIndex + prunedChunks.length;
        await _player.removeAudioSourceRange(
          startRelativeIndex,
          endRelativeIndex,
        );
      }

      _recordMetric(
        'futureBufferedChunksPruned',
        value: <String, Object?>{
          'replacementStartWordIndex': replacementStartWordIndex,
          'pruneIndex': pruneIndex,
          'prunedChunkIds': prunedChunks
              .map((chunk) => chunk.chunkId)
              .toList(growable: false),
        },
      );
    });
  }

  KokoroPlaybackQueueSnapshot _playbackQueueSnapshot() {
    return KokoroPlaybackQueueSnapshot(
      activeChunkCount: _activeChunks.length,
      currentChunkIndex: _currentChunkIndex,
      currentQueueBaseIndex: _currentQueueBaseIndex,
      pendingChunkCount: _pendingChunksById.length,
      remainingPlannedChunkCount: _remainingPlannedChunkCount,
      playerRelativeIndex: _player.currentIndex,
    );
  }

  Duration _bufferedLeadTime() {
    if (_activeChunks.isEmpty) {
      return Duration.zero;
    }

    final clampedIndex = _currentChunkIndex.clamp(0, _activeChunks.length - 1);
    final currentChunk = _activeChunks[clampedIndex];
    final currentPosition = _player.position;
    var leadTime = currentChunk.duration - currentPosition;
    if (leadTime.isNegative) {
      leadTime = Duration.zero;
    }

    for (
      var index = clampedIndex + 1;
      index < _activeChunks.length;
      index += 1
    ) {
      leadTime += _activeChunks[index].duration;
    }
    return leadTime;
  }

  Duration _playableBufferedLeadTime() =>
      kokoroPlayableLead(_bufferedLeadTime(), playerSpeed: _player.speed);

  void _recordMetric(
    String metric, {
    String? chunkId,
    String? voiceId,
    Object? value,
  }) {
    final documentId = _activeDocumentId;
    final sessionId = _activeSessionId;
    if (documentId == null || sessionId == null) {
      return;
    }

    _instrumentation.recordMetric(
      metric: metric,
      documentId: documentId,
      sessionId: sessionId,
      voiceId: voiceId ?? _selectedVoiceId,
      engineId: _engineId,
      chunkId: chunkId,
      value: value,
    );
  }

  @override
  void dispose() {
    unawaited(stop());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_currentIndexSubscription?.cancel());
    unawaited(_runtimeEventSubscription?.cancel());
    unawaited(shutdownResources());
    _player.dispose();
  }

  void _emitActivity(TtsPlaybackActivity activity) {
    _onActivity?.call(activity);
  }

  TtsPlaybackActivity _playbackActivityForPhase(
    TtsPlaybackPhase phase, {
    int bufferedChunkCount = 0,
    int totalChunkCount = 0,
  }) {
    final leadTime = phase == TtsPlaybackPhase.idle
        ? Duration.zero
        : kokoroPlayableLead(_preparedLead(), playerSpeed: _player.speed);
    final pressure = phase == TtsPlaybackPhase.idle
        ? TtsBufferPressure.none
        : kokoroBufferPressureForLeadTime(leadTime);

    if (phase != TtsPlaybackPhase.idle &&
        pressure != _lastRecordedBufferPressure) {
      _recordMetric(
        'bufferPressureState',
        value: <String, Object?>{
          'state': pressure.name,
          'leadTimeMs': leadTime.inMilliseconds,
          'targetLeadTimeMs': kokoroTargetBufferedLeadTime.inMilliseconds,
          'lowWaterLeadTimeMs': kokoroLowWaterBufferedLeadTime.inMilliseconds,
          'criticalLeadTimeMs': kokoroCriticalBufferedLeadTime.inMilliseconds,
        },
      );
      _lastRecordedBufferPressure = pressure;
    } else if (phase == TtsPlaybackPhase.idle) {
      _lastRecordedBufferPressure = TtsBufferPressure.none;
    }

    return TtsPlaybackActivity(
      phase: phase,
      bufferedChunkCount: bufferedChunkCount,
      totalChunkCount: totalChunkCount,
      bufferPressure: pressure,
      bufferedLeadTime: leadTime,
    );
  }

  Future<KokoroSpeechWorkerChunkProcessor> _createWorkerProcessor(
    RootIsolateToken rootIsolateToken,
  ) async {
    final assets = _assets;
    if (assets == null ||
        assets.modelPath == null ||
        assets.voicesDirectory == null) {
      throw StateError('Kokoro assets are not ready.');
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return KokoroSpeechWorkerChunkProcessor(
      rootIsolateToken: rootIsolateToken,
      modelPath: assets.modelPath!,
      voicesDirectory: assets.voicesDirectory!,
      generatedAudioDirectory:
          '${supportDirectory.path}${Platform.pathSeparator}generated-audio',
      engineId: _engineId,
      engineVersion: _engineVersion,
    );
  }

  void _recordPronunciationTrace(_QueuedChunk chunk) {
    var directCount = 0;
    var approximatedCount = 0;
    var deferredCount = 0;
    for (final artifact in chunk.translatedPronunciationArtifacts) {
      switch (artifact.translationOutcome) {
        case KokoroPronunciationTranslationOutcome.direct:
          directCount += 1;
        case KokoroPronunciationTranslationOutcome.approximated:
          approximatedCount += 1;
        case KokoroPronunciationTranslationOutcome.deferred:
          deferredCount += 1;
      }
    }
    _recordMetric(
      'pronunciationTranslationTrace',
      chunkId: chunk.chunkId,
      voiceId: chunk.voiceId,
      value: <String, Object?>{
        'routeId': chunk.routeId,
        'castId': chunk.castId,
        'dialogueSpanId': chunk.dialogueSpanId,
        'routedVoiceId': chunk.voiceId,
        'capabilityProfileId': chunk.capabilityProfileId,
        'segmentIds': chunk.segmentIds,
        'engineSpeakText': chunk.engineSpeakText,
        'missingFallbackWordCount': chunk.missingFallbackWordCount,
        'artifactCount': chunk.translatedPronunciationArtifacts.length,
        'directCount': directCount,
        'approximatedCount': approximatedCount,
        'deferredCount': deferredCount,
        'artifacts': chunk.translatedPronunciationArtifacts
            .map((artifact) => artifact.toMap())
            .toList(growable: false),
      },
    );
    _debugTraceSession?.appendLines(<String>[
      '',
      '=== chunk ${chunk.chunkId} ===',
      'routeId: ${chunk.routeId ?? 'none'}',
      'castId: ${chunk.castId ?? 'none'}',
      'dialogueSpanId: ${chunk.dialogueSpanId ?? 'none'}',
      'routedVoiceId: ${chunk.voiceId}',
      'text: ${jsonEncode(chunk.text)}',
      'engineSpeakText: ${jsonEncode(chunk.engineSpeakText)}',
      'finalPhonemes: ${jsonEncode(chunk.finalPhonemeString)}',
      'payloadUnits: ${jsonEncode(chunk.translatedPayloadUnits.map((unit) => unit.toMap()).toList(growable: false))}',
      'artifacts: ${jsonEncode(chunk.translatedPronunciationArtifacts.map((artifact) => artifact.toMap()).toList(growable: false))}',
      'tokenCount: ${chunk.tokens.length}',
      ...chunk.phonemeTraceLines.map((line) => 'trace: $line'),
    ]);
  }

  Future<void> _startDebugTraceSession({required String sessionId}) async {
    try {
      final session = await TtsDebugTraceSession.create(
        voiceId: _selectedVoiceId,
        sessionId: sessionId,
      );
      session.onUpdated = _onDebugTrace;
      _debugTraceSession = session;
      _onDebugTrace?.call(session.snapshot());
    } catch (_) {
      // Debug trace capture is best-effort and should not block synthesis.
    }
  }
}

class _QueuedChunk {
  const _QueuedChunk({
    required this.chunkId,
    required this.generationOrder,
    required this.segmentIds,
    required this.cacheKey,
    required this.voiceId,
    required this.boundaryClass,
    required this.documentId,
    required this.normalizationVersion,
    required this.text,
    required this.capabilityProfileId,
    required this.engineSpeakText,
    required this.startOffset,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.tokens,
    required this.segmentRanges,
    required this.ttsSegments,
    required this.translatedPronunciationArtifacts,
    required this.translatedPayloadUnits,
    required this.missingFallbackWordCount,
    required this.wordBoundaries,
    required this.finalPhonemeString,
    required this.phonemeTraceLines,
    required this.routeId,
    required this.castId,
    required this.dialogueSpanId,
    required this.fallbackRecoveryDepth,
  });

  final String chunkId;
  final int generationOrder;
  final List<String> segmentIds;
  final String cacheKey;
  final String voiceId;
  final BreakClass boundaryClass;
  final String documentId;
  final String normalizationVersion;
  final String text;
  final String capabilityProfileId;
  final String engineSpeakText;
  final int startOffset;
  final int startWordIndex;
  final int endWordIndex;
  final List<int> tokens;
  final List<_ChunkSegmentRange> segmentRanges;
  final List<TtsArtifactSegment> ttsSegments;
  final List<KokoroTranslatedPronunciationArtifact>
  translatedPronunciationArtifacts;
  final List<KokoroEnginePayloadUnit> translatedPayloadUnits;
  final int missingFallbackWordCount;
  final List<_WordBoundary> wordBoundaries;
  final String finalPhonemeString;
  final List<String> phonemeTraceLines;
  final String? routeId;
  final String? castId;
  final String? dialogueSpanId;
  final int fallbackRecoveryDepth;

  _QueuedChunk copyWith({
    String? chunkId,
    int? generationOrder,
    BreakClass? boundaryClass,
  }) {
    return _QueuedChunk(
      chunkId: chunkId ?? this.chunkId,
      generationOrder: generationOrder ?? this.generationOrder,
      segmentIds: segmentIds,
      cacheKey: cacheKey,
      voiceId: voiceId,
      boundaryClass: boundaryClass ?? this.boundaryClass,
      documentId: documentId,
      normalizationVersion: normalizationVersion,
      text: text,
      capabilityProfileId: capabilityProfileId,
      engineSpeakText: engineSpeakText,
      startOffset: startOffset,
      startWordIndex: startWordIndex,
      endWordIndex: endWordIndex,
      tokens: tokens,
      segmentRanges: segmentRanges,
      ttsSegments: ttsSegments,
      translatedPronunciationArtifacts: translatedPronunciationArtifacts,
      translatedPayloadUnits: translatedPayloadUnits,
      missingFallbackWordCount: missingFallbackWordCount,
      wordBoundaries: wordBoundaries,
      finalPhonemeString: finalPhonemeString,
      phonemeTraceLines: phonemeTraceLines,
      routeId: routeId,
      castId: castId,
      dialogueSpanId: dialogueSpanId,
      fallbackRecoveryDepth: fallbackRecoveryDepth,
    );
  }

  SpeechRuntimeChunkPayload toRuntimeChunk({
    required double rate,
    required String languageTag,
    required bool isInitialChunk,
    required bool isResumedChunk,
  }) {
    return SpeechRuntimeChunkPayload(
      chunkId: chunkId,
      segmentIds: segmentIds,
      cacheKey: runtimeCacheKey(
        isInitialChunk: isInitialChunk,
        isResumedChunk: isResumedChunk,
      ),
      boundaryClass: boundaryClass,
      documentId: documentId,
      normalizationVersion: normalizationVersion,
      capabilityProfileId: capabilityProfileId,
      speakText: engineSpeakText,
      tokens: tokens,
      languageTag: languageTag,
      voiceId: voiceId,
      rate: rate,
      isInitialChunk: isInitialChunk,
      isResumedChunk: isResumedChunk,
      routeId: routeId,
      castId: castId,
      dialogueSpanId: dialogueSpanId,
      pronunciationArtifacts: translatedPronunciationArtifacts
          .map((artifact) => artifact.toMap())
          .toList(growable: false),
      missingFallbackWordCount: missingFallbackWordCount,
    );
  }

  String runtimeCacheKey({
    required bool isInitialChunk,
    required bool isResumedChunk,
  }) {
    return [
      cacheKey,
      _runtimeTranslationSignature(
        capabilityProfileId: capabilityProfileId,
        speakText: engineSpeakText,
        pronunciationArtifacts: translatedPronunciationArtifacts,
        payloadUnits: translatedPayloadUnits,
        missingFallbackWordCount: missingFallbackWordCount,
        finalPhonemeString: finalPhonemeString,
      ),
      boundaryClass.name,
      isInitialChunk ? (isResumedChunk ? 'resumed' : 'initial') : 'continued',
    ].join(':');
  }
}

List<ExportedPronunciationArtifact> _exportPronunciationArtifacts(
  List<KokoroTranslatedPronunciationArtifact> artifacts,
) {
  return artifacts
      .map(
        (artifact) => ExportedPronunciationArtifact(
          artifactId: artifact.artifactId,
          segmentId: artifact.segmentId,
          startWord: artifact.startWord,
          endWord: artifact.endWord,
          resolutionClass: artifact.resolutionClass,
          translationIntent: artifact.translationIntent,
          translationOutcome: artifact.translationOutcome.name,
          representationType: artifact.representationType,
          representationValue: artifact.representationValue,
          diagnosticCodes: artifact.diagnosticCodes,
        ),
      )
      .toList(growable: false);
}

class _PlaybackChunk {
  const _PlaybackChunk({
    required this.chunkId,
    required this.boundaryClass,
    required this.documentId,
    required this.segmentIds,
    required this.segmentRanges,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.startOffset,
    required this.wordBoundaries,
    required this.duration,
    required this.filePath,
    required this.leadingSilence,
    required this.trailingSilence,
    required this.voiceId,
    required this.rate,
    required this.routeId,
    required this.castId,
    required this.dialogueSpanId,
  });

  final String chunkId;
  final BreakClass boundaryClass;
  final String documentId;
  final List<String> segmentIds;
  final List<_ChunkSegmentRange> segmentRanges;
  final int startWordIndex;
  final int endWordIndex;
  final int startOffset;
  final List<_WordBoundary> wordBoundaries;
  final Duration duration;
  final String filePath;
  final Duration leadingSilence;
  final Duration trailingSilence;
  final String voiceId;
  final double rate;
  final String? routeId;
  final String? castId;
  final String? dialogueSpanId;

  _ChunkSegmentRange? segmentRangeForWordIndex(int absoluteWordIndex) {
    for (final range in segmentRanges) {
      if (absoluteWordIndex >= range.startWordIndex &&
          absoluteWordIndex < range.endWordIndex) {
        return range;
      }
    }
    return segmentRanges.isEmpty ? null : segmentRanges.last;
  }
}

int _comparePlaybackChunkOrder(_PlaybackChunk left, _PlaybackChunk right) {
  final startWordComparison = left.startWordIndex.compareTo(
    right.startWordIndex,
  );
  if (startWordComparison != 0) {
    return startWordComparison;
  }
  final startOffsetComparison = left.startOffset.compareTo(right.startOffset);
  if (startOffsetComparison != 0) {
    return startOffsetComparison;
  }
  return left.chunkId.compareTo(right.chunkId);
}

Duration _initialBufferedQueueLeadTime(List<_PlaybackChunk> chunks) {
  if (chunks.isEmpty) {
    return Duration.zero;
  }
  return chunks.fold(Duration.zero, (total, chunk) => total + chunk.duration);
}

class _ChunkUnit {
  const _ChunkUnit({required this.text, required this.startOffset});

  final String text;
  final int startOffset;
}

class _PreparedPlannedChunk {
  const _PreparedPlannedChunk({
    required this.chunk,
    required this.nextSearchOffset,
  });

  final _QueuedChunk chunk;
  final int nextSearchOffset;
}

class _PreparedPlannedChunkWindow {
  const _PreparedPlannedChunkWindow({
    required this.chunks,
    required this.nextSearchOffset,
  });

  final List<_QueuedChunk> chunks;
  final int nextSearchOffset;
}

class _WordBoundary {
  const _WordBoundary({
    required this.start,
    required this.end,
    required this.word,
  });

  final int start;
  final int end;
  final String word;
}

class _ChunkSegmentRange {
  const _ChunkSegmentRange({
    required this.segmentId,
    required this.startWordIndex,
    required this.endWordIndex,
  });

  final String segmentId;
  final int startWordIndex;
  final int endWordIndex;
}

List<_ChunkSegmentRange> _segmentRangesForChunk(
  ChunkSpec spec,
  SpeechDocument? speechDocument,
) {
  if (speechDocument == null) {
    return <_ChunkSegmentRange>[
      _ChunkSegmentRange(
        segmentId: _firstOrNull(spec.segmentIds) ?? spec.chunkId,
        startWordIndex: spec.startWordIndex,
        endWordIndex: spec.endWordIndex,
      ),
    ];
  }

  final ranges = <_ChunkSegmentRange>[];
  var running = spec.startWordIndex;
  for (final segmentId in spec.segmentIds) {
    final segmentIndex = speechDocument.segmentIndexById[segmentId];
    if (segmentIndex == null) {
      return <_ChunkSegmentRange>[
        _ChunkSegmentRange(
          segmentId: _firstOrNull(spec.segmentIds) ?? spec.chunkId,
          startWordIndex: spec.startWordIndex,
          endWordIndex: spec.endWordIndex,
        ),
      ];
    }
    final segment = speechDocument.segments[segmentIndex];
    ranges.add(
      _ChunkSegmentRange(
        segmentId: segment.segmentId,
        startWordIndex: running,
        endWordIndex: running + segment.wordCount,
      ),
    );
    running += segment.wordCount;
  }
  return ranges;
}

List<_ChunkSegmentRange> _sliceSegmentRanges({
  required List<_ChunkSegmentRange> segmentRanges,
  required int startWordIndex,
  required int endWordIndex,
}) {
  final slicedRanges = <_ChunkSegmentRange>[];
  for (final range in segmentRanges) {
    final overlapStart = startWordIndex > range.startWordIndex
        ? startWordIndex
        : range.startWordIndex;
    final overlapEnd = endWordIndex < range.endWordIndex
        ? endWordIndex
        : range.endWordIndex;
    if (overlapStart >= overlapEnd) {
      continue;
    }
    slicedRanges.add(
      _ChunkSegmentRange(
        segmentId: range.segmentId,
        startWordIndex: overlapStart,
        endWordIndex: overlapEnd,
      ),
    );
  }

  if (slicedRanges.isNotEmpty) {
    return slicedRanges;
  }

  final fallbackSegmentId = segmentRanges.isEmpty
      ? 'recovered_segment'
      : segmentRanges.first.segmentId;
  return <_ChunkSegmentRange>[
    _ChunkSegmentRange(
      segmentId: fallbackSegmentId,
      startWordIndex: startWordIndex,
      endWordIndex: endWordIndex,
    ),
  ];
}

T? _firstOrNull<T>(List<T> values) {
  if (values.isEmpty) {
    return null;
  }
  return values.first;
}

int _findChunkStartOffset({
  required String fullText,
  required int searchOffset,
  required String chunkText,
}) {
  final safeSearchOffset = searchOffset.clamp(0, fullText.length).toInt();
  final index = fullText.indexOf(chunkText, safeSearchOffset);
  if (index >= 0) {
    return index;
  }
  final fallbackIndex = fullText.indexOf(chunkText);
  return fallbackIndex >= 0 ? fallbackIndex : safeSearchOffset;
}

int _nextChunkSearchOffset({
  required int fullTextLength,
  required int startOffset,
  required int chunkTextLength,
}) {
  final rawNextOffset = startOffset + chunkTextLength;
  return rawNextOffset.clamp(0, fullTextLength).toInt();
}

String _fallbackCacheKey(
  String speakText, {
  required String voiceId,
  required double rate,
  required String normalizationVersion,
}) {
  final speakHash = crypto.sha256.convert(utf8.encode(speakText)).toString();
  return [
    KokoroTtsEngine._engineId,
    KokoroTtsEngine._engineVersion,
    voiceId,
    rate.toStringAsFixed(2),
    normalizationVersion,
    speakHash,
  ].join(':');
}

String _runtimeTranslationSignature({
  required String capabilityProfileId,
  required String speakText,
  required List<KokoroTranslatedPronunciationArtifact> pronunciationArtifacts,
  required List<KokoroEnginePayloadUnit> payloadUnits,
  required int missingFallbackWordCount,
  required String finalPhonemeString,
}) {
  final signaturePayload = jsonEncode(<String, Object?>{
    'capabilityProfileId': capabilityProfileId,
    'speakText': speakText,
    'missingFallbackWordCount': missingFallbackWordCount,
    'finalPhonemeString': finalPhonemeString,
    'payloadUnits': payloadUnits
        .map((payloadUnit) => payloadUnit.toMap())
        .toList(growable: false),
    'pronunciationArtifacts': pronunciationArtifacts
        .map((artifact) => artifact.toMap())
        .toList(growable: false),
  });
  return crypto.sha256.convert(utf8.encode(signaturePayload)).toString();
}

List<_WordBoundary> _buildWordBoundaries(String text) {
  return RegExp(r'\S+')
      .allMatches(text)
      .map(
        (match) => _WordBoundary(
          start: match.start,
          end: match.end,
          word: text.substring(match.start, match.end),
        ),
      )
      .toList(growable: false);
}
