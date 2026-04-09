import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chunk_plan.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';
import '../models/tts_artifact.dart';
import '../models/voice_profile.dart';
import 'english_speech_preprocessor.dart';
import 'english_suffix_allomorph_module.dart';
import 'exported_audio_assembler.dart';
import 'kokoro_assets.dart';
import 'kokoro_ipa_adapter.dart';
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
    implements TtsEngine, VoiceLibraryCapable, AudioExportCapable {
  KokoroTtsEngine({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  static const String _engineId = 'kokoro';
  static const String _engineVersion = '12';
  static const String _fallbackNormalizationVersion =
      'read-aloud-normalization-v1';
  static const int _targetChunkWordCount = 18;
  static const Duration _startupWarmupPollInterval = Duration(
    milliseconds: 40,
  );
  static const Duration _startupWarmupMaxWait = Duration(seconds: 5);

  final AudioPlayer _player;
  final PlaybackInstrumentationService _instrumentation =
      PlaybackInstrumentationService.instance;
  final ExportedAudioAssembler _exportAssembler =
      const ExportedAudioAssembler();
  final KokoroPronunciationTranslationService _pronunciationTranslationService =
      const KokoroPronunciationTranslationService();

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
  Tokenizer? _tokenizer;
  SpeechRuntime? _speechRuntime;

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
  Future<void> _audioQueueMutation = Future<void>.value();
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
        unawaited(_resetPlaybackState());
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

      _tokenizer ??= Tokenizer(
        config: const TokenizerConfig(lexiconPath: 'assets/lexicon.json'),
      );
      await _tokenizer!.ensureInitialized();
      final rootIsolateToken = ServicesBinding.rootIsolateToken;
      if (rootIsolateToken == null) {
        throw StateError('Kokoro requires a root isolate token.');
      }
      _speechRuntime = SpeechRuntime(
        engineId: _engineId,
        processor: await _createWorkerProcessor(rootIsolateToken),
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
  Future<void> setSpeechRate(double multiplier) async {
    _speechRate = multiplier.clamp(0.7, 1.4).toDouble();
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

    unawaited(_synthesizeAndPlay(requestToken, request));
  }

  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    await initialize();
    final assets = _assets;
    if (assets == null || !(assets.isReady)) {
      throw StateError(assets?.message ?? 'Kokoro is unavailable.');
    }

    final rootIsolateToken = ServicesBinding.rootIsolateToken;
    if (rootIsolateToken == null) {
      throw StateError('Kokoro export requires a root isolate token.');
    }

    final exportText = request.text.trim();
    if (exportText.isEmpty) {
      throw StateError('Audio export requires readable text.');
    }

    final chunks = await _prepareChunks(
      TtsSpeakRequest(
        text: exportText,
        documentId: request.documentId,
        sessionId: request.sessionId,
        normalizationVersion: request.normalizationVersion,
        chunkPlan: request.chunkPlan,
        speechDocument: request.speechDocument,
      ),
      languageTag: KokoroVoiceCatalog.languageTagForVoice(_selectedVoiceId),
    );
    if (chunks.isEmpty) {
      throw StateError('Kokoro could not prepare readable text for export.');
    }

    final runtime = SpeechRuntime(
      engineId: _engineId,
      runtimeId: 'export_runtime_${DateTime.now().microsecondsSinceEpoch}',
      processor: await _createWorkerProcessor(rootIsolateToken),
    );
    final sessionId =
        request.sessionId ??
        'export_session_${DateTime.now().microsecondsSinceEpoch}';
    final generationId =
        'export_generation_${DateTime.now().microsecondsSinceEpoch}';
    final completedChunks = <String, ExportedAudioChunk>{};
    final pendingChunksById = <String, _QueuedChunk>{
      for (final chunk in chunks) chunk.chunkId: chunk,
    };
    final completion = Completer<List<ExportedAudioChunk>>();

    late final StreamSubscription<SpeechRuntimeEvent> subscription;
    subscription = runtime.events.listen((event) {
      if (event.sessionId != null && event.sessionId != sessionId) {
        return;
      }

      switch (event.type) {
        case SpeechRuntimeEventType.chunkReady:
          final chunkId = event.chunkId;
          if (chunkId == null ||
              event.audioPath == null ||
              event.duration == null) {
            return;
          }
          final plannedChunk = pendingChunksById[chunkId];
          if (plannedChunk == null) {
            return;
          }
          completedChunks[chunkId] = ExportedAudioChunk(
            chunkId: chunkId,
            cacheKey: plannedChunk.runtimeCacheKey(
              isInitialChunk: chunkId == chunks.first.chunkId,
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
                    correctionApplied:
                        event.boundaryCorrectionApplied ?? false,
                    leadingSilenceBefore:
                        event.leadingSilenceBefore ?? Duration.zero,
                    leadingSilenceAfter: event.leadingSilence ?? Duration.zero,
                    trailingSilenceBefore:
                        event.trailingSilenceBefore ?? Duration.zero,
                    trailingSilenceAfter:
                        event.trailingSilence ?? Duration.zero,
                    joinSilenceBefore:
                        event.joinSilenceBefore ?? Duration.zero,
                    joinSilenceAfter:
                        event.joinSilenceAfter ?? Duration.zero,
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
              chunks
                  .map((chunk) => completedChunks[chunk.chunkId]!)
                  .toList(growable: false),
            );
          }
        case SpeechRuntimeEventType.chunkFailed:
          if (!completion.isCompleted) {
            completion.completeError(
              StateError(
                event.message ?? 'Kokoro failed to generate one export chunk.',
              ),
            );
          }
        case SpeechRuntimeEventType.runtimeFailed:
          if (!completion.isCompleted) {
            completion.completeError(
              StateError(
                event.message ?? 'Kokoro runtime failed during export.',
              ),
            );
          }
        case SpeechRuntimeEventType.sessionCancelled:
          if (!completion.isCompleted) {
            completion.completeError(
              StateError('Kokoro export was cancelled.'),
            );
          }
        case SpeechRuntimeEventType.runtimeInitialized:
        case SpeechRuntimeEventType.sessionActivated:
        case SpeechRuntimeEventType.chunkQueued:
        case SpeechRuntimeEventType.chunkCacheHit:
        case SpeechRuntimeEventType.chunkStageChanged:
        case SpeechRuntimeEventType.runtimeShutdown:
          return;
      }
    });

    try {
      await runtime.initializeRuntime(preferredVoiceId: _selectedVoiceId);
      await runtime.activateSession(
        SpeechRuntimeSessionDescriptor(
          sessionId: sessionId,
          documentId: request.documentId ?? 'export-document',
          engineId: _engineId,
          voiceId: _selectedVoiceId,
          rate: _speechRate,
          startSegmentId:
              _firstOrNull(chunks.first.segmentIds) ?? chunks.first.chunkId,
          normalizationVersion:
              request.normalizationVersion ?? _fallbackNormalizationVersion,
          isReplay: false,
          isResumedPlayback: false,
          narrationState: const <String, Object?>{},
        ),
      );

      await runtime.preparePriorityChunk(
        sessionId: sessionId,
        generationId: generationId,
        chunk: chunks.first.toRuntimeChunk(
          rate: _speechRate,
          languageTag: KokoroVoiceCatalog.languageTagForVoice(
            chunks.first.voiceId,
          ),
          isInitialChunk: true,
          isResumedChunk: false,
        ),
      );

      if (chunks.length > 1) {
        await runtime.prepareChunkPlan(
          sessionId: sessionId,
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

      final orderedChunks = await completion.future;
      return _exportAssembler.assemble(
        ExportedAudioAssemblyRequest(
          outputPath: request.outputPath,
          engineId: _engineId,
          engineVersion: _engineVersion,
          documentId: request.documentId ?? 'export-document',
          documentTitle:
              request.documentTitle ??
              request.documentId ??
              'Read Aloud Export',
          sourceDescription:
              request.sourceDescription ?? 'Audio export from Read Aloud',
          voiceId: _selectedVoiceId,
          rate: _speechRate,
          normalizationVersion:
              request.normalizationVersion ?? _fallbackNormalizationVersion,
          chunks: orderedChunks,
        ),
      );
    } finally {
      await subscription.cancel();
      await runtime.shutdownRuntime();
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
      final chunks = hasPlannedChunks
          ? preparedStartupWindow!.chunks
          : await _prepareChunks(request, languageTag: languageTag);
      if (chunks.isEmpty) {
        _onError?.call('Kokoro could not prepare readable text for synthesis.');
        return;
      }
      for (final chunk in chunks) {
        _recordPronunciationTrace(chunk);
      }

      final generationId = 'generation_$requestToken';
      _activeGenerationId = generationId;
      _firstPendingChunkId = chunks.first.chunkId;
      _firstChunkCompleter = Completer<_PlaybackChunk>();
      _pendingChunksById = <String, _QueuedChunk>{
        for (final chunk in chunks) chunk.chunkId: chunk,
      };
      _expectedChunkCount = hasPlannedChunks
          ? request.chunkPlan!.chunks.length
          : chunks.length;
      _remainingPlannedChunkCount = hasPlannedChunks
          ? request.chunkPlan!.chunks.length - chunks.length
          : 0;
      _audioQueueMutation = Future<void>.value();

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

      if (hasPlannedChunks && request.chunkPlan!.chunks.length > 1) {
        final remainingSpecs = request.chunkPlan!.chunks
            .skip(chunks.length)
            .toList(growable: false);
        unawaited(
          _queueRemainingPlannedChunks(
            requestToken: requestToken,
            request: request,
            generationId: generationId,
            languageTag: languageTag,
            specs: remainingSpecs,
            initialSearchOffset: preparedStartupWindow!.nextSearchOffset,
          ),
        );
      }

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

      final initialBufferedChunks = kokoroBuildInitialPlaybackQueue(
        firstChunk: firstChunk,
        stagedChunks: _drainStagedReadyChunks(),
        chunkIdOf: (chunk) => chunk.chunkId,
        startWordIndexOf: (chunk) => chunk.startWordIndex,
        startOffsetOf: (chunk) => chunk.startOffset,
      );
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
    final speechRuntime = _speechRuntime;
    final sessionId = _activeSessionId;
    if (speechRuntime == null || sessionId == null || specs.isEmpty) {
      _remainingPlannedChunkCount = 0;
      return;
    }

    var searchOffset = initialSearchOffset;
    try {
      for (final spec in specs) {
        if (requestToken != _requestToken ||
            generationId != _activeGenerationId ||
            sessionId != _activeSessionId) {
          return;
        }

        final prepared = await _preparePlannedChunk(
          request: request,
          spec: spec,
          searchOffset: searchOffset,
          languageTag: languageTag,
        );
        searchOffset = prepared.nextSearchOffset;
        final chunk = prepared.chunk;
        _recordPronunciationTrace(chunk);
        _pendingChunksById[chunk.chunkId] = chunk;

        await speechRuntime.prepareChunkPlan(
          sessionId: sessionId,
          generationId: generationId,
          chunks: <SpeechRuntimeChunkPayload>[
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
        _remainingPlannedChunkCount =
            (_remainingPlannedChunkCount - 1).clamp(0, _expectedChunkCount);
        await Future<void>.delayed(Duration.zero);
      }
    } catch (error) {
      _remainingPlannedChunkCount = 0;
      if (requestToken == _requestToken && generationId == _activeGenerationId) {
        _onError?.call('Kokoro could not prepare a later chunk: $error');
      }
    }
  }

  @override
  Future<void> pause() async {
    _requestToken += 1;
    await _cancelActiveGeneration();
    _activePlaybackToken = null;
    await _player.pause();
    _emitActivity(const TtsPlaybackActivity.idle());
  }

  @override
  Future<void> stop() async {
    _requestToken += 1;
    await _cancelActiveGeneration();
    await _resetPlaybackState();
  }

  void _handlePosition(Duration position) {
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
    _emitProgressForChunkWord(absoluteIndex, 0, elapsedInChunk: Duration.zero);
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

    await _appendReadyChunkToActiveQueue(
      playbackChunk,
      generationId: event.generationId,
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

    final remainingPending = _pendingChunksById.values
        .where((chunk) => chunk.generationOrder > failedChunk.generationOrder)
        .toList(growable: false)
      ..sort(
        (left, right) => left.generationOrder.compareTo(right.generationOrder),
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
    final localStartBoundary = failedChunk.wordBoundaries[slice.startWordOffset];
    final localEndBoundary =
        failedChunk.wordBoundaries[slice.endWordOffset - 1];
    final pieceText = failedChunk.text.substring(
      localStartBoundary.start,
      localEndBoundary.end,
    );
    final pieceWordBoundaries = _buildWordBoundaries(pieceText);
    final pieceStartWordIndex = failedChunk.startWordIndex + slice.startWordOffset;
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
      boundaryClass:
          sliceIndex == 0 ? failedChunk.boundaryClass : BreakClass.none,
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
      return;
    }

    final completer = _firstChunkCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('Kokoro generation was cancelled.'));
    }

    await _speechRuntime?.cancelSession(sessionId, reasonCode: 'cancelled');
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
  }

  Future<List<_QueuedChunk>> _prepareChunks(
    TtsSpeakRequest request, {
    required String languageTag,
  }) async {
    final chunkPlan = request.chunkPlan;
    if (chunkPlan != null && chunkPlan.chunks.isNotEmpty) {
      return _prepareChunksFromPlan(request, languageTag: languageTag);
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
      languageTag: languageTag,
    );
  }

  Future<List<_QueuedChunk>> _prepareChunksFromPlan(
    TtsSpeakRequest request, {
    required String languageTag,
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
      final translatedChunk = _pronunciationTranslationService.translate(
        chunkId: spec.chunkId,
        segments: spec.ttsSegments,
      );
      final tokenization = await _tokenizeTranslatedChunk(
        translatedChunk,
        languageTag,
      );
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
  }) async {
    final startOffset = _findChunkStartOffset(
      fullText: request.text,
      searchOffset: searchOffset,
      chunkText: spec.speakText,
    );
    final translatedChunk = _pronunciationTranslationService.translate(
      chunkId: spec.chunkId,
      segments: spec.ttsSegments,
    );
    final tokenization = await _tokenizeTranslatedChunk(
      translatedChunk,
      languageTag,
    );
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
  }) async {
    final chunks = <_QueuedChunk>[];
    var searchOffset = initialSearchOffset;
    for (final spec in specs) {
      final prepared = await _preparePlannedChunk(
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
      final tokenization = await _tokenizeSpeakText(text, languageTag);
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
    _activePlaybackToken = null;
    _currentChunkIndex = 0;
    _currentQueueBaseIndex = 0;
    _activeChunks = const <_PlaybackChunk>[];
    _lastProgressKey = null;
    _activeGenerationId = null;
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
    _audioQueueMutation = Future<void>.value();
    await _player.stop();
    await _player.clearAudioSources();
    _emitActivity(const TtsPlaybackActivity.idle());
  }

  Future<List<int>> _tokenizeSpeakText(
    String speakText,
    String languageTag,
  ) async {
    final tokenizer = _tokenizer;
    if (tokenizer == null) {
      throw StateError('Kokoro tokenizer is not initialized.');
    }

    final preparedSpeakText = prepareEnglishSpeechTextForPhonemizer(speakText);
    final phonemes = await tokenizer.phonemize(
      preparedSpeakText,
      lang: languageTag,
    );
    final tokens = tokenizer.tokenize(phonemes);
    if (tokens.isEmpty) {
      throw StateError('Kokoro could not derive speech tokens for this chunk.');
    }
    return tokens;
  }

  Future<_TokenizationTrace> _tokenizeTranslatedChunk(
    KokoroTranslatedChunk translatedChunk,
    String languageTag,
  ) async {
    final tokenizer = _tokenizer;
    if (tokenizer == null) {
      throw StateError('Kokoro tokenizer is not initialized.');
    }

    final tokens = <int>[];
    final traceLines = <String>[];
    final combinedPhonemes = <String>[];
    final plainTextBuffer = StringBuffer();

    Future<void> flushPlainTextBuffer() async {
      if (plainTextBuffer.isEmpty) {
        return;
      }
      final bufferedText = plainTextBuffer.toString();
      plainTextBuffer.clear();

      if (bufferedText.trim().isEmpty) {
        return;
      }

      final preparedSpeakText = prepareEnglishSpeechTextForPhonemizer(
        bufferedText,
      );
      final phonemes = await tokenizer.phonemize(
        preparedSpeakText,
        lang: languageTag,
      );
      tokens.addAll(tokenizer.tokenize(phonemes));
      combinedPhonemes.add(phonemes);
      traceLines.add(
        'plainText text=${jsonEncode(bufferedText)} prepared=${jsonEncode(preparedSpeakText)} phonemes=${jsonEncode(phonemes)}',
      );
    }

    for (final unit in translatedChunk.payloadUnits) {
      switch (unit.kind) {
        case KokoroEnginePayloadUnitKind.plainText:
          plainTextBuffer.write(unit.value);
        case KokoroEnginePayloadUnitKind.phonemeString:
          await flushPlainTextBuffer();
          if (unit.value.trim().isEmpty) {
            continue;
          }
          final enginePhonemes = adaptStandardIpaToKokoroPhonemes(unit.value);
          tokens.addAll(tokenizer.tokenize(enginePhonemes));
          combinedPhonemes.add(enginePhonemes);
          traceLines.add(
            enginePhonemes == unit.value
                ? 'directPhoneme phonemes=${jsonEncode(unit.value)} artifactIds=${jsonEncode(unit.artifactIds)}'
                : 'directPhoneme internalPhonemes=${jsonEncode(unit.value)} enginePhonemes=${jsonEncode(enginePhonemes)} artifactIds=${jsonEncode(unit.artifactIds)}',
          );
        case KokoroEnginePayloadUnitKind.englishSClassAllomorph:
          await flushPlainTextBuffer();
          final realization = englishSClassRealizationForToken(unit.value);
          if (realization == null) {
            plainTextBuffer.write(unit.value);
            continue;
          }
          final basePhonemes = await tokenizer.phonemize(
            prepareEnglishSpeechTextForPhonemizer(realization.baseSurfaceText),
            lang: languageTag,
          );
          final phonemeString =
              '$basePhonemes${englishSClassSuffixPhoneme(realization.allomorph)}';
          tokens.addAll(tokenizer.tokenize(phonemeString));
          combinedPhonemes.add(phonemeString);
          traceLines.add(
            'englishSClass token=${jsonEncode(unit.value)} base=${jsonEncode(realization.baseSurfaceText)} basePhonemes=${jsonEncode(basePhonemes)} suffix=${jsonEncode(englishSClassSuffixPhoneme(realization.allomorph))} combined=${jsonEncode(phonemeString)}',
          );
        case KokoroEnginePayloadUnitKind.explicitSuffixPhoneme:
          await flushPlainTextBuffer();
          final explicitSuffixPayload = _decodeExplicitSuffixPayload(unit.value);
          if (explicitSuffixPayload == null) {
            plainTextBuffer.write(unit.value);
            continue;
          }
          final basePhonemes = await tokenizer.phonemize(
            prepareEnglishSpeechTextForPhonemizer(
              explicitSuffixPayload.baseSurfaceText,
            ),
            lang: languageTag,
          );
          final phonemeString =
              '$basePhonemes${explicitSuffixPayload.suffixPhoneme}';
          tokens.addAll(tokenizer.tokenize(phonemeString));
          combinedPhonemes.add(phonemeString);
          traceLines.add(
            'explicitSuffix base=${jsonEncode(explicitSuffixPayload.baseSurfaceText)} basePhonemes=${jsonEncode(basePhonemes)} suffix=${jsonEncode(explicitSuffixPayload.suffixPhoneme)} combined=${jsonEncode(phonemeString)}',
          );
      }
    }

    await flushPlainTextBuffer();

    if (tokens.isEmpty) {
      throw StateError('Kokoro could not derive speech tokens for this chunk.');
    }
    return _TokenizationTrace(
      tokens: tokens,
      phonemeTraceLines: traceLines,
      finalPhonemeString: combinedPhonemes.join(' '),
    );
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
    await _player.seek(Duration.zero, index: nextRelativeIndex);
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

  Future<void> _awaitStartupWarmup({
    required _PlaybackChunk firstChunk,
  }) async {
    final deadline = DateTime.now().add(_startupWarmupMaxWait);
    while (_activeGenerationId != null && _activePlaybackToken == null) {
      if (_isStartupWarmEnough(firstChunk)) {
        return;
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
        return;
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
    );
  }

  List<_PlaybackChunk> _startupBufferedChunks(_PlaybackChunk firstChunk) {
    return kokoroBuildInitialPlaybackQueue(
      firstChunk: firstChunk,
      stagedChunks: _stagedReadyChunks,
      chunkIdOf: (chunk) => chunk.chunkId,
      startWordIndexOf: (chunk) => chunk.startWordIndex,
      startOffsetOf: (chunk) => chunk.startOffset,
    );
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
    _audioQueueMutation = _audioQueueMutation.then((_) async {
      if (generationId != _activeGenerationId) {
        return;
      }
      if (_activePlaybackToken == null) {
        _stageReadyChunk(playbackChunk);
        return;
      }
      if (_activeChunks.any((chunk) => chunk.chunkId == playbackChunk.chunkId)) {
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
      _recordMetric(
        'prefetchLeadTimeMs',
        chunkId: playbackChunk.chunkId,
        voiceId: playbackChunk.voiceId,
        value: <String, Object?>{
          'leadTimeMs': _bufferedLeadTime().inMilliseconds,
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
    await _audioQueueMutation;
  }

  Future<void> _discardFutureBufferedChunksFromStartWordIndex(
    int replacementStartWordIndex,
  ) async {
    _audioQueueMutation = _audioQueueMutation.then((_) async {
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
    await _audioQueueMutation;
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
    unawaited(_speechRuntime?.shutdownRuntime());
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
        : _bufferedLeadTime();
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
          'lowWaterLeadTimeMs':
              kokoroLowWaterBufferedLeadTime.inMilliseconds,
          'criticalLeadTimeMs':
              kokoroCriticalBufferedLeadTime.inMilliseconds,
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

class _TokenizationTrace {
  const _TokenizationTrace({
    required this.tokens,
    required this.phonemeTraceLines,
    required this.finalPhonemeString,
  });

  final List<int> tokens;
  final List<String> phonemeTraceLines;
  final String finalPhonemeString;
}

class _ExplicitSuffixPayload {
  const _ExplicitSuffixPayload({
    required this.baseSurfaceText,
    required this.suffixPhoneme,
  });

  final String baseSurfaceText;
  final String suffixPhoneme;
}

_ExplicitSuffixPayload? _decodeExplicitSuffixPayload(String rawValue) {
  try {
    final decoded = jsonDecode(rawValue);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final baseSurfaceText = decoded['baseSurfaceText'] as String?;
    final suffixPhoneme = decoded['suffixPhoneme'] as String?;
    if (baseSurfaceText == null ||
        baseSurfaceText.trim().isEmpty ||
        suffixPhoneme == null ||
        suffixPhoneme.trim().isEmpty) {
      return null;
    }
    return _ExplicitSuffixPayload(
      baseSurfaceText: baseSurfaceText,
      suffixPhoneme: suffixPhoneme,
    );
  } catch (_) {
    return null;
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
  final startWordComparison = left.startWordIndex.compareTo(right.startWordIndex);
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
  return chunks.fold(
    Duration.zero,
    (total, chunk) => total + chunk.duration,
  );
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
    final overlapEnd =
        endWordIndex < range.endWordIndex ? endWordIndex : range.endWordIndex;
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

  final fallbackSegmentId =
      segmentRanges.isEmpty ? 'recovered_segment' : segmentRanges.first.segmentId;
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
