import '../models/engine_session.dart';
import '../models/character.dart';
import '../services/modernbooknlp_character_adapter.dart';
import '../services/modernbooknlp_window.dart';
import '../services/character_route_refinement.dart';
import '../services/document_analysis_record.dart';
import '../services/modernbooknlp_analysis.dart';
import '../services/modernbooknlp_provider.dart';
import '../services/modernbooknlp_runtime.dart';
import '../services/character_analysis_adapter.dart';
import '../services/work_character_store.dart';
import '../models/speech_engine_catalog.dart';
import '../services/speech_planning_supervisor.dart';
import '../services/speech_audio_packet.dart';
import '../services/voice_assignment_coordinator.dart';
import '../models/voice_assignment_state.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_open/file_open.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/document_import_exception.dart';
import '../models/document_preparation.dart';
import '../models/prepared_voice_binding.dart';
import '../models/cast_voice_assignment.dart';
import '../models/character_cast_registry.dart';
import '../models/narration_state.dart';
import '../models/reading_focus_state.dart';
import '../models/reader_appearance_mode.dart';
import '../models/reader_document.dart';
import '../models/reader_resume_state.dart';
import '../models/display_document.dart';
import '../models/chunk_plan.dart';
import '../models/english_pronunciation_profile.dart';
import '../models/spoken_chunk_record.dart';
import '../models/spoken_selection.dart';
import '../models/speech_document.dart';
import '../models/tts_artifact.dart';
import '../models/voice_session_realization.dart';
import '../models/voice_preview_state.dart';
import '../models/voice_profile.dart';
import '../services/cast_aware_speech_route_service.dart';
import '../services/default_tts_engine.dart';
import '../services/document_access_service.dart';
import '../services/document_import_service.dart';
import '../services/document_preparation_supervisor.dart';
import '../services/english_pronunciation_profile_selector.dart';
import '../services/playback_instrumentation_service.dart';
import '../services/pronunciation_resource_layering_service.dart';
import '../services/reader_preferences_service.dart';
import '../services/reader_document_repository.dart';
import '../services/file_source_revision.dart';
import '../services/reader_document_serialization_service.dart';
import '../services/reader_document_codec.dart';
import '../services/share_intake_service.dart';
import '../services/spoken_selection_mapper_service.dart';
import '../services/tts_engine.dart';
import '../models/native_speech_turn.dart';
import '../models/radoc_audio_manifest.dart';
import '../services/radoc_audio_package.dart';
import '../services/radoc_export_staging.dart';
import '../services/audio_artifact_store.dart';
import '../services/rendered_scene_repository.dart';
import '../services/synthesis_boundary_policy.dart';
import '../models/speech_annotation.dart';

part 'reader_audio_book.dart';
part 'reader_audio_book_export.dart';

class ReaderController extends ChangeNotifier {
  static const int preparedRangeCapacity = 8;
  static final Set<String> _knownTtsEngineIds = speechEngineLabels.keys.toSet();
  static const Duration _healthyFollowerUpdateInterval = Duration(
    milliseconds: 100,
  );
  static const Duration _lowWaterFollowerUpdateInterval = Duration(
    milliseconds: 180,
  );
  static const Duration _criticalFollowerUpdateInterval = Duration(
    milliseconds: 250,
  );
  static const int _healthyFollowerSoftWordDelta = 2;
  static const int _lowWaterFollowerSoftWordDelta = 3;
  static const int _criticalFollowerSoftWordDelta = 4;
  static const int _followerHardResyncWordDelta = 10;

  ReaderController({
    ModernBookNlpAnalysis? characterAnalysis,
    DocumentImportService? importer,
    DocumentPreparationSupervisor? preparationSupervisor,
    ReaderDocumentRepository? documentRepository,
    DocumentAccessService? documentAccessService,
    ReaderPreferencesService? preferencesService,
    TtsEngine? ttsEngine,
    TtsEngine Function(String, int)? engineFactory,
    bool enablePlatformIntakeChannels = true,
    this.deferInitialSynthesis = false,
    RenderedSceneRepository? renderedSceneRepository,
  }) : characterAnalysis =
           characterAnalysis ??
           ModernBookNlpAnalysis.withRuntime(createModernBookNlpProvider),
       _preparation =
           preparationSupervisor ??
           DocumentPreparationSupervisor(
             testImporter: importer,
             repository: documentRepository,
           ),
       _useDefaultRepository =
           preparationSupervisor == null &&
           importer == null &&
           documentRepository == null,
       _documentAccessService =
           documentAccessService ?? createDocumentAccessService(),
       _preferencesService = preferencesService ?? ReaderPreferencesService(),
       _engineFactory = engineFactory,
       _providedTtsEngine = ttsEngine,
       _ttsEngine = ttsEngine ?? createDefaultTtsEngine(),
       _enablePlatformIntakeChannels = enablePlatformIntakeChannels,
       _document = ReaderDocument.sample(),
       _renderedScenes = renderedSceneRepository {
    this.characterAnalysis.onResult = _acceptCharacterAnalysis;
  }

  final ModernBookNlpAnalysis characterAnalysis;
  final bool deferInitialSynthesis;
  bool _synthesisInitialized = false;
  _ReaderAudioBook? _audioBook;
  Future<void>? _audioBookRetirement;
  int? _audioGapWord;
  bool get hasPublishedAudio => _audioBook != null;
  RenderedSceneRepository? _renderedScenes;
  void _notifyAudioBookChanged() => notifyListeners();
  ModernBookNlpWindow? _offeredAnalysisWindow;
  ModernBookNlpRequest? _offeredAnalysisRequest;
  String? _analysisContentSource;
  int? _analysisRangeSequence;
  List<SpeechSegment> _analysisTail = const [], _analysisLeading = const [];
  final Map<String, List<CharacterDialogueReference>> _futureCharacterRoutes =
      {};
  String get _characterSourceRevision =>
      _analysisContentSource ??
      _activeSourceRevision ??
      _voicePreferenceDocumentId;

  void _offerCharacterAnalysis() {
    characterAnalysis.repository ??= _preparation.repository?.analysis;
    final active = _activePreparedRange;
    final range = active != null && active.request.revision == _documentRevision
        ? active
        : _preparedRanges.firstOrNull;
    final document = range?.fragment ?? _document;
    final position = range == null || identical(range, active)
        ? _currentWordIndex
        : 0;
    if (_offeredAnalysisRequest?.analysisRevision == _documentRevision &&
        _analysisRangeSequence == range?.sequence &&
        _offeredAnalysisWindow?.coversPosition(document, position) == true) {
      return;
    }
    if (_analysisRangeSequence != range?.sequence) {
      _analysisLeading =
          range != null && range.sequence == (_analysisRangeSequence ?? -2) + 1
          ? _analysisTail
          : const [];
      _analysisRangeSequence = range?.sequence;
      var units = 0;
      final tail = <SpeechSegment>[];
      for (final s in document.speechDocument.segments.reversed.take(32)) {
        if (units + s.normalizedText.length + 1 > 4096) break;
        tail.insert(0, s);
        units += s.normalizedText.length + 1;
      }
      _analysisTail = List.unmodifiable(tail);
    }
    final window = ModernBookNlpWindow.at(
      document,
      wordIndex: position,
      previous: _analysisLeading,
    );
    if (window == null) return;
    final sequence = ++_characterDeltaSequence;
    final request = ModernBookNlpRequest(
      requestId: '$_preparationOwner-$_documentRevision-$sequence',
      ownerId: _preparationOwner,
      workId: _voicePreferenceDocumentId,
      sourceRevision: _characterSourceRevision,
      analysisRevision: _documentRevision,
      sequence: sequence,
      text: window.text,
      windowPolicy: 'paragraph-context-v2',
    );
    _offeredAnalysisWindow = window;
    _offeredAnalysisRequest = request;
    characterAnalysis.offer(request);
  }

  Future<void> _acceptCharacterAnalysis(
    ModernBookNlpRequest request,
    Map<String, dynamic> result,
    bool Function() current,
  ) async {
    bool owned() =>
        current() &&
        !_disposed &&
        request.analysisRevision == _documentRevision &&
        request.requestId == _offeredAnalysisRequest?.requestId;
    if (!owned()) return;
    final window = _offeredAnalysisWindow!;
    final registry = _characters.registry(
      _voicePreferenceDocumentId,
      documentId: _document.displayDocument.documentId,
    );
    // Parsing raw TSV/JSON, hashing and reconciliation stay off the UI isolate.
    // This awaited consumer shares the supervisor's one-active/latest-pending
    // lifetime. User selections/corrections are re-read by the store at apply.
    final delta = await projectModernBookNlpCharacters(
      request,
      result,
      registry,
      window,
    );
    if (!owned() || !_characters.apply(delta)) return;
    _refreshCharacterProjection();
    for (final ref in delta.dialogues) {
      _futureCharacterRoutes.remove(ref.dialogueSpanId);
    }
    for (final ref in delta.dialogues) {
      if (window.protectedSpanIds.contains(ref.dialogueSpanId)) continue;
      (_futureCharacterRoutes[ref.dialogueSpanId] ??= []).add(ref);
    }
    while (_futureCharacterRoutes.length > 128) {
      _futureCharacterRoutes.remove(_futureCharacterRoutes.keys.first);
    }
    // Do not restart, revoice or replace a captured active planning context.
    // The next ordinary planning request resolves newly admitted future routes.
    unawaited(_persistPreferences());
    notifyListeners();
  }

  DocumentPreparationSupervisor _preparation;
  final bool _useDefaultRepository;
  Future<void>? _repositoryInitialization;
  bool _preparationClosed = false;
  String? _activeSourceRevision;
  DocumentPreparationRequest? _activePreparationRequest;
  Future<File?>? _documentExportWork;
  Future<String?>? _sourceRevisionWork;

  Future<String> _snapshotRevision(
    int revision,
    DocumentPreparationKind kind,
    String? fileName,
    String? text,
    Uint8List? bytes,
  ) async {
    // A replaced request may drain one finite hash. Waiting callers recheck
    // ownership before admission, so only the latest can start another worker.
    while (_sourceRevisionWork != null) {
      try {
        await _sourceRevisionWork;
      } catch (_) {
        // An older request's hash failure cannot fail its replacement.
      }
      _requireRevision(revision);
    }
    _requireRevision(revision);
    final work = _capturedSourceRevision(kind, fileName, text, bytes);
    _sourceRevisionWork = work;
    try {
      return await work;
    } finally {
      if (identical(_sourceRevisionWork, work)) _sourceRevisionWork = null;
    }
  }

  Future<String?> _pathRevision(int revision, String path) async {
    while (_sourceRevisionWork != null) {
      try {
        await _sourceRevisionWork;
      } catch (_) {
        // An older probe cannot fail the latest request.
      }
      _requireRevision(revision);
    }
    _requireRevision(revision);
    final work = fileSourceRevision(path);
    _sourceRevisionWork = work;
    try {
      return await work;
    } finally {
      if (identical(_sourceRevisionWork, work)) _sourceRevisionWork = null;
    }
  }

  Future<void> _initializeRepository() async {
    if (!_useDefaultRepository) return;
    await (_repositoryInitialization ??= () async {
      try {
        final support = await getApplicationSupportDirectory();
        if (_disposed || _preparationClosed) return;
        _preparation = DocumentPreparationSupervisor(
          repository: ReaderDocumentRepository(
            p.join(support.path, 'prepared-documents'),
          ),
        );
      } on MissingPluginException {
        // A platform-free harness has no persistent application directory.
      }
    }());
  }

  final String _preparationOwner =
      'reader-${DateTime.now().microsecondsSinceEpoch}';
  int _documentRevision = 0;
  int _preparedDocumentRevision = 0;
  int get preparedDocumentRevision => _preparedDocumentRevision;
  String get preparationOwnerId => _preparationOwner;
  int _watchSession = 0;
  bool _disposed = false;
  bool _documentPrepared = true;
  final List<DocumentPreparationPublication> _preparedRanges = [];
  final Map<String, CastEntry> _discoveredCast = {};
  final Map<String, String> _castRedirects = {};
  final Map<PreparationStage, PreparationProgress> _preparationProgress = {};
  final Map<PreparationStage, int> _stageGenerations = {};
  Completer<void>? _rangeCredit;
  bool _preparationComplete = true;
  bool _hasCompleteDocumentSnapshot = true;
  int _publicationSequence = 0;
  int _preparedWordCount = 0;
  final Map<int, Future<DocumentPreparationPublication?>> _rangeReads = {};
  String? _sessionDocumentId;
  final Map<String, String> _documentIdentityRedirects = {};
  String? _startupError;
  Future<void>? _engineStartup;
  int _startupRevision = 0;
  bool _pendingPlayUntilReady = false;
  final Completer<void> _intakeReady = Completer<void>();
  final Completer<void> _preferencesReady = Completer<void>();
  bool _initializationStarted = false;
  Future<void> get intakeReady => _intakeReady.future;
  Future<void> Function()? _retryPreparation;
  bool _preparationFailed = false;
  Object? _preparationError;
  Completer<void> _rangesChanged = Completer<void>();
  DocumentPreparationPublication? _activePreparedRange;
  bool get canRetryDocumentPreparation =>
      !_disposed &&
      !_isImporting &&
      _preparationFailed &&
      _retryPreparation != null;
  bool get isPreparingDocument =>
      _isImporting ||
      (!_preparationComplete &&
          !_preparationFailed &&
          _publicationSequence > 0);

  void _signalRanges() {
    final changed = _rangesChanged;
    _rangesChanged = Completer<void>();
    if (!changed.isCompleted) changed.complete();
  }

  Future<void> cancelDocumentPreparation() async {
    if (_disposed || (!_isImporting && _preparationComplete)) return;
    ++_documentRevision;
    ++_playbackIntent;
    _preparation.cancel();
    _planning.cancel();
    _preparationFailed = true;
    _preparationError = StateError('Document preparation cancelled.');
    _pendingPlayUntilReady = false;
    _playbackStartPending = false;
    _resumeAfterPreparation = false;
    _activePlaybackDocumentId = null;
    _isPlaying = false;
    _isImporting = false;
    _documentPrepared = true;
    _playbackState = ReaderPlaybackPrimaryState.paused;
    _playbackActivity = const TtsPlaybackActivity.idle();
    _statusMessage = 'Document preparation cancelled. Retry to continue.';
    _preparationProgress.updateAll((_, progress) {
      return switch (progress.state) {
        PreparationWorkState.working ||
        PreparationWorkState.waiting ||
        PreparationWorkState.stalled => progress.withState(
          PreparationWorkState.cancelled,
        ),
        _ => progress,
      };
    });
    final credit = _rangeCredit;
    _rangeCredit = null;
    if (credit != null && !credit.isCompleted) credit.complete();
    _signalRanges();
    notifyListeners();
    await _ttsEngine.stop();
  }

  Future<void> retryDocumentPreparation() async {
    if (!canRetryDocumentPreparation) return;
    _preparationFailed = false;
    await _retryPreparation!();
  }

  List<DocumentPreparationPublication> get preparedRanges =>
      List.unmodifiable(_preparedRanges);
  Map<PreparationStage, PreparationProgress> get preparationProgress =>
      Map.unmodifiable(_preparationProgress);
  bool get isPreparationComplete => _preparationComplete;
  int get preparedRangeCount => _publicationSequence;
  int get preparedWordCount => _preparedWordCount;
  int? get activePreparedRangeSequence => _activePreparedRange?.sequence;
  bool get hasRangeDocument =>
      _activePreparationRequest != null &&
      _publicationSequence > 0 &&
      _preparedDocumentRevision == _documentRevision;
  int get pendingRangeReadCount => _rangeReads.length;

  /// Viewport and playback share immutable checkpoint data. At most eight
  /// reads are admitted/coalesced; waiting callers can cancel before admission.
  Future<DocumentPreparationPublication?> readPreparedRange(
    int sequence, {
    Future<void>? cancelled,
  }) async {
    final revision = _documentRevision;
    bool current() => !_disposed && revision == _documentRevision;
    Future<T> cancellable<T>(Future<T> work) => cancelled == null
        ? work
        : Future.any([
            work,
            cancelled.then<T>((_) => throw const PlanningCancelled()),
          ]);
    if (sequence < 1) throw ArgumentError.value(sequence, 'sequence');
    while (current()) {
      final existing = _rangeReads[sequence];
      if (existing != null) return cancellable(existing);
      if (_rangeReads.length < preparedRangeCapacity) break;
      final changed = _rangesChanged.future;
      await cancellable(
        Future.any<void>([
          changed,
          ..._rangeReads.values.map(
            (read) => read.then<void>((_) {}, onError: (Object _) {}),
          ),
        ]),
      );
    }
    if (!current()) return null;
    late Future<DocumentPreparationPublication?> work;
    work = _readPreparedRange(sequence, revision).whenComplete(() {
      if (identical(_rangeReads[sequence], work)) _rangeReads.remove(sequence);
    });
    _rangeReads[sequence] = work;
    return cancellable(work);
  }

  Future<DocumentPreparationPublication?> _readPreparedRange(
    int sequence,
    int revision,
  ) async {
    final request = _activePreparationRequest;
    if (request == null) return null;
    final book = _audioBook;
    if (book != null) return _readAudioBookRange(book, sequence, revision);
    bool current() => !_disposed && revision == _documentRevision;
    while (current()) {
      // Capture before any await/credit grant, so a publication cannot be lost.
      final changed = _rangesChanged.future;
      final resident = _preparedRanges
          .where((r) => r.sequence == sequence)
          .firstOrNull;
      if (resident != null) return resident;
      if (sequence <= _publicationSequence) {
        final repository = _preparation.repository;
        final cache = await repository?.open(
          sourceKey: request.effectiveSourceRevision,
          sourceRevision: request.effectiveSourceRevision,
        );
        if (!current()) return null;
        if (cache == null || sequence > cache.rangeCount) {
          throw StateError(
            'The requested text range is unavailable. Retry document preparation.',
          );
        }
        final publication = await cache.readRange(sequence, request: request);
        return current() ? publication : null;
      }
      if (_preparationError case final error?) throw error;
      if (_preparationComplete) return null;
      if (_rangeCredit != null) {
        // Demand from the viewport is independent of audio consumption. Earlier
        // committed ranges stay readable from disk, including for playback.
        releasePreparedRange(_publicationSequence - 1);
      }
      await changed;
    }
    return null;
  }

  bool get hasCompleteDocumentSnapshot =>
      _documentPrepared &&
      (_audioBook?.book.manifest.preparationComplete == true ||
          _hasCompleteDocumentSnapshot ||
          (_preparationComplete &&
              _activeSourceRevision != null &&
              _preparation.repository != null));
  String? get startupError => _startupError;
  bool get hasPendingPlaybackIntent =>
      _resumeAfterPreparation &&
      (_pendingPlayUntilReady ||
          _playbackStartPending ||
          _playbackStartDriver != null);
  List<CastEntry> get discoveredCastEntries =>
      List.unmodifiable(_discoveredCast.values);

  /// Session-wide evidence shared by casting UI and newly admitted speech.
  /// Already captured playback contexts and bindings remain immutable.
  CharacterCastRegistry get characterCastRegistry => _discoveredCast.isEmpty
      ? _document.characterCastRegistry
      : CharacterCastRegistry(
          documentId: sessionDocumentId,
          registryVersion: _document.characterCastRegistry.registryVersion,
          entries: _discoveredCast.values.toList(growable: false),
          castIdRedirects: _castRedirects,
        );
  Map<String, String> get castIdRedirects => Map.unmodifiable(_castRedirects);
  String get sessionDocumentId =>
      _sessionDocumentId ?? _document.displayDocument.documentId;
  Map<String, String> get documentIdentityRedirects =>
      Map.unmodifiable(_documentIdentityRedirects);

  Future<bool> reconcileDocumentIdentity(
    DocumentIdentityMigration migration,
  ) async {
    if (_disposed ||
        migration.ownerId != _preparationOwner ||
        migration.documentRevision != _documentRevision ||
        migration.sourceRevision !=
            (_activeSourceRevision ??
                '$_preparationOwner:$_documentRevision') ||
        migration.watchSession != _watchSession ||
        migration.provisionalDocumentId != sessionDocumentId ||
        migration.canonicalDocumentId.isEmpty) {
      return false;
    }
    final previous = sessionDocumentId;
    final canonical = migration.canonicalDocumentId;
    final preferenceOwner = _voicePreferenceDocumentId;
    _characters.associate(preferenceOwner, canonical);
    _documentIdentityRedirects[previous] = canonical;
    _sessionDocumentId = canonical;
    if (_activeSourceRevision case final source?) {
      _sourceVoiceDocumentIds[source] = canonical;
    }
    // Retain provisional keys for recovery; subsequent replay uses the updated
    // canonical owner. Current overrides and active speech remain intact.
    await _persistPreferences();
    if (!_disposed) notifyListeners();
    return true;
  }

  ReadingStageTicket beginReadingStage(
    PreparationStage stage, {
    required String producerId,
    required String scope,
  }) => ReadingStageTicket(
    ownerId: _preparationOwner,
    producerId: producerId,
    documentRevision: _documentRevision,
    sourceRevision: '$_preparationOwner:$_documentRevision',
    watchSession: _watchSession,
    stage: stage,
    generation: _stageGenerations.update(
      stage,
      (value) => value + 1,
      ifAbsent: () => 1,
    ),
    scope: scope,
  );

  /// Main-isolate publication route for planning/resources and the downstream
  /// synthesis/persistence owners. Counts are supplied by completed work.
  void publishReadingStage(
    ReadingStageTicket ticket,
    PreparationProgress progress,
  ) {
    if (_disposed ||
        ticket.ownerId != _preparationOwner ||
        ticket.documentRevision != _documentRevision ||
        ticket.sourceRevision != '$_preparationOwner:$_documentRevision' ||
        ticket.watchSession != _watchSession ||
        ticket.stage != progress.stage ||
        ticket.generation != _stageGenerations[ticket.stage]) {
      return;
    }
    _preparationProgress[ticket.stage] = PreparationProgress(
      stage: progress.stage,
      state: progress.state,
      completed: progress.completed,
      total: progress.total,
      unit: progress.unit,
      discovered: progress.discovered,
      waitingReason: progress.waitingReason,
      error: progress.error,
      workRevision: '${ticket.producerId}:${ticket.generation}',
      scope: ticket.scope,
    );
    notifyListeners();
  }

  /// C owns consumption. Releasing a committed range grants one producer credit;
  /// at most eight bounded fragments can be resident ahead of playback.
  void releasePreparedRange(int sequence) {
    _preparedRanges.removeWhere((range) => range.sequence <= sequence);
    final credit = _rangeCredit;
    _rangeCredit = null;
    if (credit != null && !credit.isCompleted) credit.complete();
  }

  void _resumePendingPlay() {
    if (!_pendingPlayUntilReady ||
        !isDocumentPrepared ||
        _isInitializing ||
        _startupError != null ||
        _disposed) {
      return;
    }
    _pendingPlayUntilReady = false;
    unawaited(startPlayback());
  }

  final SpeechPlanningSupervisor _planning = SpeechPlanningSupervisor();
  SpeechPlanningContext? _currentPlanningContext;
  SpeechPlanningSupervisor? _exportPlanner;
  List<PreparedVoiceBinding> _resourceBindings = const [];
  List<ResolvedPreparedVoiceReference> _resolvedResourceBindings = const [];
  int _resourceBindingIntent = 0;
  int _preparedAssignmentRevision = -1;
  final _voiceAssignments = VoiceAssignmentCoordinator();
  int? _assignmentReplayWord;
  bool _applyingVoiceAssignments = false;
  int _playbackIntent = 0;
  bool _playbackStartPending = false;
  Future<void>? _playbackStartDriver;
  Future<void>? _startupStop;
  bool _explicitVoiceRebuffer = false;
  int? _activeAssignmentRevision;
  int? _activePlaybackIntent;
  int? _acknowledgedPlaybackIntent;
  TtsPlaybackResumeAnchor? _pausedVoiceReplayAnchor;
  VoiceAssignmentState get voiceAssignmentState => _voiceAssignments.state;

  TtsPlaybackResumeAnchor? _localPlaybackResumeAnchor() {
    final engine = _ttsEngine;
    if (engine is! VoiceAssignmentPlaybackCapable) return null;
    final anchor =
        (engine as VoiceAssignmentPlaybackCapable).currentPlaybackResumeAnchor;
    if (anchor == null) return null;
    if (_activePreparedRange != null &&
        anchor.documentId == _activePlaybackDocumentId) {
      return TtsPlaybackResumeAnchor(
        documentId: _document.displayDocument.documentId,
        chunkId: anchor.chunkId,
        startWordIndex:
            anchor.startWordIndex - _activePreparedRange!.range.wordStart,
      );
    }
    return anchor;
  }

  Future<void> applyPendingVoiceAssignments() async {
    if (!voiceAssignmentState.hasPending || _applyingVoiceAssignments) return;
    final revision = voiceAssignmentState.requestedRevision;
    final anchor = _localPlaybackResumeAnchor();
    if (anchor != null &&
        anchor.documentId == _document.displayDocument.documentId) {
      _assignmentReplayWord = anchor.startWordIndex;
    } else {
      _assignmentReplayWord ??= _snapWordIndexToSegmentStart(_currentWordIndex);
    }
    _applyingVoiceAssignments = true;
    _explicitVoiceRebuffer = true;
    final applyIntent = ++_playbackIntent;
    final documentRevision = _documentRevision;
    _resumeAfterPreparation = true;
    _currentWordIndex = _assignmentReplayWord!;
    _playbackEndedAtDocumentEnd = false;
    _voiceAssignments.preparing(revision, initialBuffering: false);
    notifyListeners();
    try {
      await _stopSupersededStartup();
      if (_disposed ||
          !_resumeAfterPreparation ||
          applyIntent != _playbackIntent ||
          documentRevision != _documentRevision ||
          !_voiceAssignments.isCurrent(revision)) {
        return;
      }
      _isPlaying = false;
      _currentWordIndex = _assignmentReplayWord!;
      _invalidateResourceBindings();
      await startPlayback();
    } catch (error) {
      if (_disposed ||
          documentRevision != _documentRevision ||
          applyIntent != _playbackIntent ||
          !_resumeAfterPreparation) {
        return;
      }
      _voiceAssignments.fail(revision, error);
      notifyListeners();
    } finally {
      _applyingVoiceAssignments = false;
    }
  }

  Future<void> retryVoiceAssignments() => applyPendingVoiceAssignments();

  Future<void> _stopSupersededStartup() => _startupStop ??= _ttsEngine
      .stop()
      .whenComplete(() => _startupStop = null);

  bool get _isInitialVoiceBuffering =>
      _resumeAfterPreparation &&
      (_applyingVoiceAssignments ||
          (_acknowledgedPlaybackIntent != _playbackIntent &&
              (_playbackStartDriver != null ||
                  _playbackState ==
                      ReaderPlaybackPrimaryState.bufferingFirstChunk)));

  void _captureRequestedVoiceChoices({bool initialBuffering = false}) {
    final voiceId = _selectedVoiceId;
    final assignments = voiceId == null
        ? null
        : _resolveCastVoiceAssignments(preferredNarratorVoiceId: voiceId);
    _voiceAssignments.request(
      defaultVoiceId: voiceId,
      castVoices: {
        for (final a in assignments?.assignments ?? <CastVoiceAssignment>[])
          a.castId: a.effectiveVoiceId,
      },
      initialBuffering: initialBuffering,
    );
  }

  Future<void> _voiceChoicesEdited() async {
    _audioBook?.cancelRender();
    final initial = _isInitialVoiceBuffering;
    final retrying =
        _resumeAfterPreparation &&
        voiceAssignmentState.phase == VoiceAssignmentPhase.failed;
    _captureRequestedVoiceChoices(initialBuffering: initial);
    notifyListeners();
    if (initial) {
      final anchor = _pausedVoiceReplayAnchor;
      if (anchor != null &&
          anchor.documentId == _document.displayDocument.documentId) {
        _assignmentReplayWord ??= anchor.startWordIndex;
        _currentWordIndex = _assignmentReplayWord!;
        _explicitVoiceRebuffer = true;
      }
      ++_playbackIntent;
      _invalidateResourceBindings();
      _playbackStartPending = true;
      unawaited(_stopSupersededStartup());
      unawaited(_drivePlaybackStarts());
    } else if (retrying ||
        _isPlaying ||
        (_resumeAfterPreparation && _playbackActivity.isBuffering)) {
      // Reuse the single playback driver: selection is intent, while the
      // current request acknowledgment remains the authority for audible voice.
      unawaited(applyPendingVoiceAssignments());
    }
    await _persistPreferences();
  }

  List<PreparedVoiceBinding> get resourceBindings =>
      isResourcesReady ? _resourceBindings : const [];
  List<ResolvedPreparedVoiceReference> get resolvedResourceBindings =>
      isResourcesReady ? _resolvedResourceBindings : const [];
  void _invalidateResourceBindings() {
    ++_resourceBindingIntent;
    _planning.cancel();
    _exportPlanner?.cancel();
    _resourceBindings = const [];
    _resolvedResourceBindings = const [];
    _preparedAssignmentRevision = -1;
  }

  bool get isDisplayReady =>
      _document.displayHtml.isNotEmpty || _document.pdfData != null;
  bool get isDocumentPrepared => _documentPrepared;
  bool get isAudioReady => _playbackActivity.isPlaying;
  bool get isResourcesReady =>
      _ttsEngine is! ResourcePreparationCapable ||
      (_resourceBindings.isNotEmpty &&
          (_ttsEngine as ResourcePreparationCapable).resourcesReady);

  void _requireRevision(int revision) {
    if (_disposed || revision != _documentRevision) {
      throw const _SupersededPreparation();
    }
  }

  int _beginDocumentRequest() {
    characterAnalysis.loadBookRecord = null;
    final retiredBook = _audioBook;
    _audioBook = null;
    _audioGapWord = null;
    if (retiredBook != null) {
      retiredBook.current = false;
      unawaited(retiredBook.package.cancelAndDrain());
      _audioBookRetirement = (_audioBookRetirement ?? Future<void>.value())
          .then((_) async {
            await _ttsEngine.stop();
            await _renderedScenes?.cancelAndDrain();
            await retiredBook.dispose();
          });
    }
    characterAnalysis.invalidateWindow();
    _offeredAnalysisWindow = null;
    _offeredAnalysisRequest = null;
    _analysisContentSource = null;
    _analysisRangeSequence = null;
    _analysisTail = _analysisLeading = const [];
    _futureCharacterRoutes.clear();
    ++_playbackIntent;
    _playbackStartPending = false;
    _invalidateResourceBindings();
    _preparation.cancel();
    _pendingPlayUntilReady = false;
    _documentPrepared = false;
    _preparationComplete = false;
    _hasCompleteDocumentSnapshot = false;
    _activeSourceRevision = null;
    _activePreparationRequest = null;
    _sessionDocumentId = null;
    _preparationFailed = false;
    _preparationError = null;
    _activePreparedRange = null;
    _signalRanges();
    _publicationSequence = 0;
    _preparedWordCount = 0;
    _rangeReads.clear();
    _preparedRanges.clear();
    _characters.cancelAnalysis();
    _characterAnalysisKey = null;
    _discoveredCast.clear();
    _castRedirects.clear();
    _documentIdentityRedirects.clear();
    _preparationProgress.clear();
    _stageGenerations.clear();
    releasePreparedRange(0);
    return ++_documentRevision;
  }

  Future<ReaderDocument> _prepare(
    int revision,
    DocumentPreparationKind kind, {
    String? text,
    String? fileName,
    Uint8List? bytes,
    String? sourcePath,
    Future<Uint8List> Function()? acquireBytes,
  }) async {
    _requireRevision(revision);
    await _initializeRepository();
    _requireRevision(revision);
    var capturedBytes = bytes == null
        ? null
        : Uint8List.fromList(bytes).asUnmodifiableView();
    var byteAcquisition = acquireBytes;
    _retryPreparation = () => _runImportOperation((retryRevision) async {
      final document = await _prepare(
        retryRevision,
        kind,
        text: text,
        fileName: fileName,
        bytes: capturedBytes,
        sourcePath: sourcePath,
        acquireBytes: byteAcquisition,
      );
      await _replaceDocument(
        document,
        revision: retryRevision,
        sourcePath: sourcePath,
      );
    }, errorSourceLabel: fileName);
    final first = Completer<ReaderDocument>();
    DocumentAccessLease? sourceLease;
    var streamedPath =
        bytes != null || sourcePath == null || sourcePath.trim().isEmpty
        ? null
        : p.normalize(sourcePath.trim());
    // Virtual XFile providers can have a descriptive path without a native
    // file. Their byte adapter remains the supported acquisition boundary.
    if (streamedPath != null && !await File(streamedPath).exists()) {
      streamedPath = null;
    }
    _requireRevision(revision);
    final sourceFilePath = streamedPath;
    final watchSession = _watchSession;
    bool current() =>
        !_disposed &&
        revision == _documentRevision &&
        watchSession == _watchSession;
    // Callback-acquired bytes have no stable source identity until admission.
    // Keep acquisition under supervisor ownership; without a captured immutable
    // input, skip repository cache lookup for this request.
    final snapshotText = text;
    final snapshotBytes = capturedBytes;
    final sourceRevision = _preparation.repository == null
        ? null
        : streamedPath != null
        ? await _pathRevision(revision, streamedPath)
        : snapshotText == null && snapshotBytes == null
        ? null
        : await _snapshotRevision(
            revision,
            kind,
            fileName,
            snapshotText,
            snapshotBytes,
          );
    _requireRevision(revision);
    _activeSourceRevision = sourceRevision;
    final request = DocumentPreparationRequest(
      ownerId: _preparationOwner,
      revision: revision,
      kind: kind,
      text: text,
      fileName: fileName,
      bytes: capturedBytes,
      sourcePath: streamedPath,
      sourceRevision: sourceRevision,
      watchSession: watchSession,
    );
    _activePreparationRequest = request.identityOnly;
    final repository = _preparation.repository;
    final cache = repository == null || sourceRevision == null
        ? null
        : await repository.open(
            sourceKey: sourceRevision,
            sourceRevision: sourceRevision,
          );
    _requireRevision(revision);
    final cachedMigration = cache?.identityMigration(request);
    // Upgrade pre-alias preferences only from a validated range of this exact
    // source revision. Never guess a book by title or by matching cast names.
    if (sourceRevision != null &&
        !_sourceVoiceDocumentIds.containsKey(sourceRevision) &&
        _storedDocumentCastVoiceAssignments.isNotEmpty &&
        cache != null &&
        cache.rangeCount > 0) {
      try {
        final prior = await cache.readRange(1, request: request);
        _requireRevision(revision);
        final priorId =
            cachedMigration?.canonicalDocumentId ??
            prior.fragment.displayDocument.documentId;
        if (_storedDocumentCastVoiceAssignments.containsKey(priorId)) {
          _sourceVoiceDocumentIds[sourceRevision] = priorId;
        }
      } on FormatException {
        // Corrupt cache cannot establish preference ownership; rebuild input.
      }
    }
    _requireRevision(revision);
    final completion = _preparation.prepareRanges(
      request,
      cacheKey: sourceRevision,
      onIdentityMigration: (migration) async {
        if (!current()) return;
        await reconcileDocumentIdentity(migration);
      },
      acquireBytes: byteAcquisition,
      acquireSource: sourceFilePath == null
          ? null
          : () async {
              // Check access without reading the book. The lease, if recovery is
              // needed, belongs to this operation until worker/native drain.
              try {
                final handle = await File(sourceFilePath).open();
                await handle.close();
              } catch (error) {
                _requireRevision(revision);
                if (!_looksLikePermissionIssue(error)) rethrow;
                sourceLease = await _requestDirectoryAccessAfterReadFailure(
                  sourceLabel: 'document stream',
                  sourcePath: sourceFilePath,
                  initialError: error,
                  revision: revision,
                );
                if (sourceLease == null) rethrow;
              }
            },
      onDrained: () async {
        await sourceLease?.close();
      },
      onProgress: (progress) {
        if (!current()) return;
        _preparationProgress[progress.stage] = progress;
        _documentLoadStageLabel =
            '${progress.stage.name}: ${progress.completed} ${progress.unit}';
        _documentLoadStageProgress = progress.fraction;
        notifyListeners();
      },
      onCharacterDiscovery: (publication) {
        if (!current() ||
            publication.request.ownerId != _preparationOwner ||
            publication.request.revision != revision ||
            publication.request.effectiveSourceRevision !=
                request.effectiveSourceRevision ||
            publication.request.watchSession != watchSession ||
            publication.sequence != _publicationSequence + 1) {
          return;
        }
        if (_publicationSequence == 0) {
          _sessionDocumentId = publication.registry.documentId;
        }
        _mergeDiscoveredCast(publication.registry);
        _documentLoadStageLabel =
            'Discovered ${discoveredCastEntries.length - 1} characters; refining dialogue';
        notifyListeners();
      },
      onPublication: (publication) async {
        if (!current() ||
            publication.request.ownerId != _preparationOwner ||
            publication.request.revision != revision ||
            publication.request.effectiveSourceRevision !=
                request.effectiveSourceRevision ||
            publication.request.watchSession != watchSession ||
            publication.sequence != _publicationSequence + 1) {
          return;
        }
        if (_publicationSequence == 0) {
          _sessionDocumentId = publication.fragment.displayDocument.documentId;
          if (cachedMigration != null &&
              cachedMigration.provisionalDocumentId == _sessionDocumentId) {
            await reconcileDocumentIdentity(cachedMigration);
            if (!current()) return;
          }
        }
        // Validate the provider boundary before admitting the prepared range.
        _mergeDiscoveredCast(
          publication.fragment.characterCastRegistry,
          document: publication.fragment,
        );
        _publicationSequence = publication.sequence;
        _preparedWordCount = publication.range.wordEnd;
        _preparedRanges.add(publication);
        _offerCharacterAnalysis();
        _signalRanges();
        for (final progress in publication.progress) {
          if (publication.coverage.contains(progress.stage) ||
              progress.scope == 'cache' ||
              !_preparationProgress.containsKey(progress.stage)) {
            _preparationProgress[progress.stage] = progress;
          }
        }
        _documentLoadStageLabel =
            'Prepared ${publication.range.wordEnd} words; discovering remaining work';
        _documentLoadStageProgress = null;
        if (!first.isCompleted) first.complete(publication.fragment);
        notifyListeners();
        // A synchronous listener can cancel, replace or dispose this request.
        // Never install a producer wait after its owner has been invalidated.
        if (!current()) return;
        if (_preparedRanges.length >= preparedRangeCapacity &&
            !publication.isLast) {
          const reason =
              'Prepared reading window is full; continues as you read';
          final paused = <PreparationStage>[];
          for (final stage in [
            PreparationStage.acquisition,
            PreparationStage.parsing,
            PreparationStage.normalization,
            PreparationStage.mapping,
            PreparationStage.analysis,
            PreparationStage.pronunciation,
            PreparationStage.persistence,
          ]) {
            final progress = _preparationProgress[stage];
            if (progress != null &&
                progress.state != PreparationWorkState.complete) {
              paused.add(stage);
              _preparationProgress[stage] = progress.withState(
                PreparationWorkState.waiting,
                waitingReason: reason,
              );
            }
          }
          final credit = _rangeCredit = Completer<void>();
          _signalRanges(); // Wake demand that arrived before credit existed.
          notifyListeners();
          await credit.future;
          if (!current()) return;
          for (final stage in paused) {
            final progress = _preparationProgress[stage];
            if (progress?.waitingReason == reason) {
              _preparationProgress[stage] = progress!.withState(
                PreparationWorkState.working,
              );
            }
          }
          notifyListeners();
        }
      },
    );
    unawaited(
      completion.then((result) {
        if (!current()) {
          if (!first.isCompleted) {
            first.completeError(const _SupersededPreparation());
          }
          return;
        }
        if (result.outcome == DocumentPreparationOutcome.ready &&
            result.document != null) {
          _preparationComplete = true;
          _signalRanges();
          if (_publicationSequence <= 1) _hasCompleteDocumentSnapshot = true;
          if (!first.isCompleted) first.complete(result.document);
          // Completion covers only preparation. Resource/synthesis/persistence
          // progress belongs to the downstream owner, never this terminal event.
          for (final stage in const [
            PreparationStage.acquisition,
            PreparationStage.parsing,
            PreparationStage.normalization,
            PreparationStage.mapping,
            PreparationStage.analysis,
            PreparationStage.pronunciation,
          ]) {
            final prior = _preparationProgress[stage];
            if (prior != null) {
              _preparationProgress[stage] = PreparationProgress(
                stage: stage,
                state: PreparationWorkState.complete,
                completed: prior.completed,
                total: prior.completed,
                unit: prior.unit,
              );
            }
          }
        } else {
          final error = result.outcome == DocumentPreparationOutcome.cancelled
              ? const _SupersededPreparation()
              : result.importFailure ??
                    StateError(
                      result.error ?? 'Preparation ${result.outcome.name}',
                    );
          _preparationError = error;
          _preparationFailed = true;
          _signalRanges();
          if (!first.isCompleted) {
            first.completeError(error);
          } else {
            _statusMessage = '$error';
            _preparationProgress[PreparationStage.parsing] =
                PreparationProgress(
                  stage: PreparationStage.parsing,
                  state: PreparationWorkState.failed,
                  completed: _publicationSequence,
                  unit: 'ranges',
                  error: '$error',
                );
          }
        }
        notifyListeners();
      }),
    );
    return first.future;
  }

  final DocumentAccessService _documentAccessService;
  final ReaderPreferencesService _preferencesService;
  ReaderPreferences? _pendingPreferences;
  Future<void>? _preferenceSavePump;
  int _preferenceSnapshotRevision = 0;
  final TtsEngine? _providedTtsEngine;
  final TtsEngine Function(String, int)? _engineFactory;
  Future<void>? _engineSwitch;
  bool _runningEngineRetired = false;
  int _engineEpoch = 0;
  int _previewRevision = 0;
  String _loadingEngineId = ReaderPreferences.defaultTtsEngineId;
  int _loadingBits = 0;
  EngineSession _engineSession = const EngineSession();
  EngineSession get engineSession => _engineSession;
  final Map<String, String> _narratorVoiceIds = {};
  String get _narratorScope => _selectedTtsEngineId == 'voxtral_4b'
      ? '$_selectedTtsEngineId:$_voxtralQuantizationBits'
      : _selectedTtsEngineId;

  void _publishEnginePhase(EngineSessionPhase phase) {
    _engineSession = EngineSession(
      epoch: _engineEpoch,
      selected: EngineSessionIdentity(
        _selectedTtsEngineId,
        _voxtralQuantizationBits,
      ),
      active: phase == EngineSessionPhase.active ? _engineSession.active : null,
      lastWorking: _engineSession.lastWorking,
      phase: phase,
    );
  }

  bool _ownsEngine(TtsEngine engine, int epoch) =>
      !_disposed &&
      epoch == _engineEpoch &&
      !_runningEngineRetired &&
      identical(engine, _ttsEngine);
  bool get isSwitchingEngine => _engineSwitch != null;
  TtsEngine _createEngine(String id, int bits) =>
      _engineFactory?.call(id, id == 'voxtral_4b' ? bits : 0) ??
      createDefaultTtsEngine(engineId: id, voxtralQuantizationBits: bits);
  TtsEngine _ttsEngine;
  String _selectedTtsEngineId = ReaderPreferences.defaultTtsEngineId;
  int _voxtralQuantizationBits = 0;
  int _runningVoxtralQuantizationBits = 0;
  String _runningTtsEngineId = ReaderPreferences.defaultTtsEngineId;
  final bool _enablePlatformIntakeChannels;
  final EnglishPronunciationProfileSelector _pronunciationProfileSelector =
      const EnglishPronunciationProfileSelector();
  final PronunciationResourceLayeringService
  _pronunciationResourceLayeringService =
      const PronunciationResourceLayeringService();
  final SpokenSelectionMapperService _spokenSelectionMapperService =
      const SpokenSelectionMapperService();
  final PlaybackInstrumentationService _instrumentation =
      PlaybackInstrumentationService.instance;
  final ShareIntakeService _shareIntake = createShareIntakeService();
  VoiceLibraryCapable? _voiceLibraryCapable;

  ReaderDocument _document;
  List<VoiceProfile> _voices = const <VoiceProfile>[];
  List<VoiceLibraryEntry> _voiceLibrary = const <VoiceLibraryEntry>[];
  String? _selectedVoiceId;
  final Map<String, double> _voiceSpeeds = <String, double>{};
  String _fontFamily = ReaderPreferences.defaultFontFamily;
  double _fontScale = ReaderPreferences.defaultFontScale;
  ReaderAppearanceMode _appearanceMode = ReaderAppearanceMode.system;
  bool _isMultiVoiceEnabled = ReaderPreferences.defaultMultiVoiceEnabled;
  String? _lastOpenedDocumentPath;
  String? _lastOpenedDocumentAccessToken;
  String? _lastOpenedDirectoryPath;
  String? _lastOpenedDirectoryAccessToken;
  WorkCharacterStore _characters = WorkCharacterStore();
  Map<String, Map<String, String>> get _storedDocumentCastVoiceAssignments =>
      _characters.legacySelections;
  String? _characterAnalysisKey;
  int _characterDeltaSequence = 0;
  ReaderResumeState? _resumeState;
  String? _currentDocumentPath;
  String? _liveReadFilePath;
  StreamSubscription<FileSystemEvent>? _liveReadSubscription;
  Timer? _liveReadReloadDebounce;
  Timer? _resumePersistenceDebounce;
  Timer? _followerProgressDebounce;

  bool _isInitializing = true;
  bool _isImporting = false;
  bool _isExporting = false;
  bool _isPlaying = false;
  bool _isFadingOut = false;
  String? _activePreviewVoiceId;
  bool _isVoicePreviewLoading = false;
  bool _isVoicePreviewPlaying = false;
  String? _documentLoadStageLabel;
  double? _documentLoadStageProgress;
  bool _playbackEndedAtDocumentEnd = false;
  ReaderPlaybackPrimaryState _playbackState = ReaderPlaybackPrimaryState.idle;
  TtsPlaybackActivity _playbackActivity = const TtsPlaybackActivity.idle();

  String? _statusMessage;
  TtsResourceProgress? _speechResourceProgress;
  NarrationState _narrationState = NarrationState.initial();
  VoiceSessionRealization? _currentRealization;
  ChunkPlan? _currentChunkPlan;
  final Map<String, SpokenChunkRecord> _spokenChunkRecords =
      <String, SpokenChunkRecord>{};
  final Set<String> _editedCastIds = {};
  Map<String, String> get _castVoiceOverrides => Map.unmodifiable({
    for (final e in _characters.selections(_voicePreferenceDocumentId).entries)
      if (_editedCastIds.contains(e.key)) e.key: e.value,
  });
  final Map<String, String> _sourceVoiceDocumentIds = {};
  String? _activeSpokenChunkId;
  String? _ttsDebugTraceLogPath;
  DateTime? _ttsDebugTraceStartedAt;
  String? _ttsDebugTraceVoiceId;
  List<String> _ttsDebugTraceLines = const <String>[];
  SpokenSelection _spokenSelection = const SpokenSelection.none();
  ReadingFocusState _readingFocusState = const ReadingFocusState();
  String? _activePlaybackDocumentId;
  TtsProgressUpdate? _pendingFollowerProgressUpdate;
  DateTime? _lastFollowerProgressAppliedAt;

  int _currentWordIndex = 0;
  double _wordsPerSecond = 2.8;

  int _utteranceStartOffset = 0;
  int _utteranceStartWordIndex = 0;
  DateTime? _utteranceStartedAt;
  DateTime? _playbackRequestedAt;
  final Set<String> _latencyRecordedSessions = <String>{};
  final Set<String> _positionConfidenceRecordedSessions = <String>{};

  Duration? _sleepTimerDuration;
  DateTime? _sleepTimerEndsAt;
  Timer? _sleepTicker;
  StreamSubscription<List<Uri>>? _fileOpenSubscription;
  StreamSubscription<SharedIntake>? _shareSubscription;

  ReaderDocument get document => _document;
  List<VoiceProfile> get voices => _voices;
  List<VoiceLibraryEntry> get voiceLibrary => _voiceLibrary;
  bool get canManageVoices => _voiceLibraryCapable != null;
  bool get isInitializing => _isInitializing;
  bool get isImporting => _isImporting;
  bool get isExporting => _isExporting;
  bool get isPlaying => _isPlaying;
  bool get isMultiVoiceEnabled => _isMultiVoiceEnabled;
  String? get activePreviewVoiceId => _activePreviewVoiceId;
  bool get isCastProcessingVisible => _isImporting && _isMultiVoiceEnabled;
  String get documentLoadStageLabel =>
      _documentLoadStageLabel ?? 'Preparing cast and dialogue voices...';
  double? get documentLoadStageProgress => _documentLoadStageProgress;
  bool get isBufferingPlayback => _playbackActivity.isBuffering;
  bool get isFadingOut => _isFadingOut;
  ReaderPlaybackPrimaryState get playbackState => _playbackState;
  TtsPlaybackActivity get playbackActivity => _playbackActivity;
  String? get statusMessage => _statusMessage;
  TtsResourceProgress? get speechResourceProgress => _speechResourceProgress;
  NarrationState get narrationState => _narrationState;
  VoiceSessionRealization? get currentRealization => _currentRealization;
  ChunkPlan? get currentChunkPlan => _currentChunkPlan;
  TtsArtifactSet? get currentTtsArtifactSet =>
      _currentRealization?.ttsArtifactSet;
  int get currentWordIndex => _currentWordIndex;
  double get wordsPerSecond => _wordsPerSecond;
  List<SpokenChunkRecord> get spokenChunkRecords =>
      _spokenChunkRecords.values.toList(growable: false);
  String? get ttsDebugTraceLogPath => _ttsDebugTraceLogPath;
  DateTime? get ttsDebugTraceStartedAt => _ttsDebugTraceStartedAt;
  String? get ttsDebugTraceVoiceId => _ttsDebugTraceVoiceId;
  List<String> get ttsDebugTraceLines => _ttsDebugTraceLines;
  SpokenSelection get spokenSelection => _spokenSelection;
  ReadingFocusState get readingFocusState => _readingFocusState;
  CastVoiceAssignmentSet? get castVoiceAssignments {
    if (!_isMultiVoiceEnabled) {
      return null;
    }
    final voiceId = _selectedVoiceId;
    if (voiceId == null) {
      return null;
    }
    return _resolveCastVoiceAssignments(preferredNarratorVoiceId: voiceId);
  }

  bool get hasDistinctEffectiveCastVoices {
    final assignments = castVoiceAssignments;
    if (assignments == null) {
      return false;
    }
    return assignments.assignments
            .map((assignment) => assignment.effectiveVoiceId)
            .toSet()
            .length >
        1;
  }

  Duration? get sleepTimerDuration => _sleepTimerDuration;
  String get fontFamily => _fontFamily;
  double get fontScale => _fontScale;
  ReaderAppearanceMode get appearanceMode => _appearanceMode;
  bool get isLiveReadEnabled => _liveReadFilePath != null;
  String? get liveReadFilePath => _liveReadFilePath;
  bool get canExportAudio => _ttsEngine is AudioExportCapable;
  String get selectedTtsEngineId => _selectedTtsEngineId;
  int get voxtralQuantizationBits => _voxtralQuantizationBits;
  String get runningTtsEngineId => _runningTtsEngineId;
  bool get ttsEngineRestartRequired =>
      _selectedTtsEngineId != _runningTtsEngineId ||
      (_selectedTtsEngineId == 'voxtral_4b' &&
          _voxtralQuantizationBits != _runningVoxtralQuantizationBits);
  String get suggestedAudioExportFileName =>
      _defaultAudioExportFileName(_document.title, _selectedVoiceId);
  String get currentDocumentWindowLabel {
    final currentPath = _currentDocumentPath;
    if (currentPath != null && currentPath.trim().isNotEmpty) {
      return p.basename(currentPath);
    }
    final title = _document.title.trim();
    return title.isEmpty ? 'Untitled' : title;
  }

  String get windowTitle => 'Read Aloud - $currentDocumentWindowLabel';

  Duration? get sleepTimerRemaining {
    if (_sleepTimerEndsAt == null) return null;
    final remaining = _sleepTimerEndsAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  VoiceProfile? get selectedVoice {
    if (_selectedVoiceId == null) return null;
    for (final voice in _voices) {
      if (voice.id == _selectedVoiceId) return voice;
    }
    return null;
  }

  double get currentSpeed {
    final voiceId = _selectedVoiceId;
    if (voiceId == null) return 1.0;
    return _effectiveSpeechRate(_voiceSpeeds[voiceId] ?? 1.0);
  }

  double _effectiveSpeechRate(double requested) {
    if (!requested.isFinite || requested <= 0) {
      throw ArgumentError.value(requested, 'speechRate');
    }
    final engine = _ttsEngine;
    return engine is SpeechRateNormalizationCapable
        ? (engine as SpeechRateNormalizationCapable).normalizeSpeechRate(
            requested,
          )
        : requested;
  }

  VoicePreviewState previewStateForVoice(String voiceId) {
    if (_activePreviewVoiceId != voiceId) {
      return VoicePreviewState.idle;
    }
    if (_isVoicePreviewLoading) {
      return VoicePreviewState.loading;
    }
    if (_isVoicePreviewPlaying) {
      return VoicePreviewState.playing;
    }
    return VoicePreviewState.idle;
  }

  Future<void> initialize() async {
    _initializationStarted = true;
    late final ReaderPreferences preferences;
    try {
      preferences = await _preferencesService.load();
    } catch (error) {
      _startupError =
          'Could not read saved character choices. Stored data has been preserved. $error';
      _statusMessage = _startupError;
      _isInitializing = false;
      if (!_preferencesReady.isCompleted) _preferencesReady.complete();
      notifyListeners();
      return;
    }
    _voxtralQuantizationBits = preferences.voxtralQuantizationBits;
    _runningVoxtralQuantizationBits = _voxtralQuantizationBits;
    _selectedTtsEngineId = _knownTtsEngineIds.contains(preferences.ttsEngineId)
        ? preferences.ttsEngineId
        : ReaderPreferences.defaultTtsEngineId;
    final launchEngine = Platform.isMacOS
        ? Platform.environment['READALOUD_TTS_ENGINE']?.trim()
        : null;
    if (_providedTtsEngine == null &&
        _knownTtsEngineIds.contains(launchEngine)) {
      _selectedTtsEngineId = launchEngine!;
    }
    if (_providedTtsEngine == null) {
      _ttsEngine.dispose();
      _ttsEngine = _createEngine(
        _selectedTtsEngineId,
        _voxtralQuantizationBits,
      );
    }
    _runningTtsEngineId = _ttsEngine is TtsEngineIdentityCapable
        ? (_ttsEngine as TtsEngineIdentityCapable).engineId
        : _selectedTtsEngineId;
    _loadingEngineId = _runningTtsEngineId;
    _loadingBits = _voxtralQuantizationBits;
    _publishEnginePhase(EngineSessionPhase.loading);
    _bindEngineCallbacks();

    _narratorVoiceIds.addAll(preferences.narratorVoiceIds);
    // Migrate the saved legacy choice into its engine's scope once.
    if (preferences.selectedVoiceId case final voice?) {
      final legacyScope = preferences.ttsEngineId == 'voxtral_4b'
          ? '${preferences.ttsEngineId}:${preferences.voxtralQuantizationBits}'
          : preferences.ttsEngineId;
      _narratorVoiceIds.putIfAbsent(legacyScope, () => voice);
    }
    _selectedVoiceId = _narratorVoiceIds[_narratorScope];
    _voiceSpeeds
      ..clear()
      ..addAll(preferences.voiceSpeeds);
    _fontFamily = preferences.fontFamily;
    _fontScale = preferences.fontScale;
    _appearanceMode = preferences.appearanceMode;
    _isMultiVoiceEnabled = preferences.multiVoiceEnabled;
    _characters = preferences.characterSnapshot == null
        ? WorkCharacterStore()
        : preferences.characterSnapshot!.restore();
    if (preferences.characterSnapshot == null) {
      _characters.migrateLegacy(preferences.storedDocumentCastVoiceAssignments);
    }
    _sourceVoiceDocumentIds
      ..clear()
      ..addAll(preferences.sourceVoiceDocumentIds);
    _resumeState = preferences.resumeState;
    _lastOpenedDocumentPath = preferences.lastOpenedDocumentPath;
    _lastOpenedDocumentAccessToken = preferences.lastOpenedDocumentAccessToken;
    _lastOpenedDirectoryPath = preferences.lastOpenedDirectoryPath;
    _lastOpenedDirectoryAccessToken =
        preferences.lastOpenedDirectoryAccessToken;
    if (!_preferencesReady.isCompleted) _preferencesReady.complete();

    final startup = deferInitialSynthesis
        ? Future<void>.value()
        : retryInitialization();
    if (deferInitialSynthesis) _isInitializing = false;
    if (_enablePlatformIntakeChannels) {
      await _initializeIntakeChannels();
    }
    if (!_intakeReady.isCompleted) _intakeReady.complete();
    await startup;
  }

  void _bindEngineCallbacks() {
    final engine = _ttsEngine;
    final epoch = _engineEpoch;
    _ttsEngine.onStart = () {
      if (!_ownsEngine(engine, epoch)) return;
      if (_activePreviewVoiceId != null) {
        _isVoicePreviewLoading = false;
        _isVoicePreviewPlaying = true;
        notifyListeners();
        return;
      }
      if (_activePlaybackDocumentId == null) {
        return;
      }
      if (_activePlaybackIntent != _playbackIntent ||
          (_ttsEngine is VoiceAssignmentPlaybackCapable &&
              _acknowledgedPlaybackIntent != _playbackIntent)) {
        return;
      }
      _isPlaying = true;
      _playbackState = ReaderPlaybackPrimaryState.playing;
      _readingFocusState = _readingFocusState.copyWith(playbackActive: true);
      _recordFirstAudioLatency();
      notifyListeners();
    };
    _ttsEngine.onStatus = (message) {
      if (!_ownsEngine(engine, epoch)) return;
      if (_activePreviewVoiceId != null) {
        return;
      }
      _statusMessage = message;
      notifyListeners();
    };
    if (_ttsEngine is TtsResourceProgressCapable) {
      (_ttsEngine as TtsResourceProgressCapable).onResourceProgress =
          (progress) {
            if (!_ownsEngine(engine, epoch)) return;
            if (_disposed) return;
            _speechResourceProgress = progress;
            if (_isInitializing && progress != null) {
              _publishEnginePhase(
                progress.stage.toLowerCase().contains('download') ||
                        progress.stage == 'acquiring' ||
                        progress.stage == 'modelCache'
                    ? EngineSessionPhase.acquiring
                    : EngineSessionPhase.loading,
              );
            }
            notifyListeners();
          };
    }
    _ttsEngine.onComplete = () {
      if (!_ownsEngine(engine, epoch)) return;
      if (_activePreviewVoiceId != null) {
        _resetPreviewState();
        unawaited(_restoreSelectedVoiceEngineState());
        notifyListeners();
        return;
      }
      if (_activePlaybackDocumentId == null) {
        return;
      }
      if (_activePlaybackIntent != _playbackIntent) return;
      _flushPendingFollowerProgress();
      unawaited(_flushResumePersistence());
      _finalizeActiveSpokenChunk();
      _activePlaybackDocumentId = null;
      _isPlaying = false;
      _isFadingOut = false;
      _playbackRequestedAt = null;
      _playbackEndedAtDocumentEnd =
          _document.wordCount > 0 &&
          _currentWordIndex >= _document.wordCount - 1;
      _playbackState = _playbackEndedAtDocumentEnd
          ? ReaderPlaybackPrimaryState.completed
          : ReaderPlaybackPrimaryState.paused;
      _readingFocusState = _readingFocusState.copyWith(playbackActive: false);
      _narrationState = _narrationState.copyWith(
        recentBoundaryClass: _boundaryClassForCurrentPosition(),
        continuationPending: false,
        recentRate: currentSpeed,
      );
      notifyListeners();
    };
    _ttsEngine.onError = (message) {
      if (!_ownsEngine(engine, epoch)) return;
      if (_activePreviewVoiceId != null) {
        _resetPreviewState();
        unawaited(_restoreSelectedVoiceEngineState());
        _statusMessage = 'Voice preview failed.';
        notifyListeners();
        return;
      }
      if (_activePlaybackDocumentId == null) {
        if (_isInitializing && !_disposed) {
          _startupError = message;
          _statusMessage = message;
          notifyListeners();
        }
        return;
      }

      if (_activePlaybackIntent != _playbackIntent) return;
      _flushPendingFollowerProgress();
      if (voiceAssignmentState.hasPending &&
          _activeAssignmentRevision != null) {
        _voiceAssignments.fail(_activeAssignmentRevision!, message);
      }
      unawaited(_flushResumePersistence());
      _statusMessage = message;
      // A terminal error ends this intent, including late preparation/ready
      // callbacks. Play must create a new attempt, not toggle stale buffering.
      ++_playbackIntent;
      _resumeAfterPreparation = false;
      _pendingPlayUntilReady = false;
      _playbackStartPending = false;
      _activePlaybackDocumentId = null;
      _isPlaying = false;
      _isFadingOut = false;
      _playbackRequestedAt = null;
      _playbackActivity = const TtsPlaybackActivity.idle();
      _playbackState = ReaderPlaybackPrimaryState.failed;
      _readingFocusState = _readingFocusState.copyWith(playbackActive: false);
      notifyListeners();
    };
    _ttsEngine.onProgress = (progress) {
      if (_ownsEngine(engine, epoch)) {
        _handleProgress(progress);
      }
    };
    _ttsEngine.onActivity = (activity) {
      if (!_ownsEngine(engine, epoch)) return;
      if (_activePreviewVoiceId != null) {
        switch (activity.phase) {
          case TtsPlaybackPhase.buffering:
            _isVoicePreviewLoading = true;
            _isVoicePreviewPlaying = false;
            break;
          case TtsPlaybackPhase.playing:
            _isVoicePreviewLoading = false;
            _isVoicePreviewPlaying = true;
            break;
          case TtsPlaybackPhase.idle:
            _isVoicePreviewLoading = false;
            _isVoicePreviewPlaying = false;
            break;
        }
        notifyListeners();
        return;
      }
      if (_activePlaybackDocumentId == null &&
          activity.phase != TtsPlaybackPhase.idle) {
        return;
      }
      _playbackActivity = activity;
      if (activity.phase == TtsPlaybackPhase.buffering) {
        _playbackState = ReaderPlaybackPrimaryState.bufferingFirstChunk;
      } else if (activity.phase == TtsPlaybackPhase.playing) {
        _playbackState = ReaderPlaybackPrimaryState.playing;
      }
      notifyListeners();
    };
    _ttsEngine.onDebugTrace = (trace) {
      if (!_ownsEngine(engine, epoch)) return;
      _ttsDebugTraceLogPath = trace.logPath;
      _ttsDebugTraceStartedAt = trace.startedAt;
      _ttsDebugTraceVoiceId = trace.voiceId;
      _ttsDebugTraceLines = trace.recentLines;
      notifyListeners();
    };

    if (_ttsEngine is VoiceLibraryCapable) {
      _voiceLibraryCapable = _ttsEngine as VoiceLibraryCapable
        ..onVoiceLibraryChanged = () {
          if (_ownsEngine(engine, epoch)) _handleVoiceLibraryChanged();
        };
      _voiceLibrary = _voiceLibraryCapable!.voiceLibrary;
    }
  }

  void _detachEngineCallbacks(TtsEngine engine) {
    engine.onStart = null;
    engine.onStatus = null;
    engine.onComplete = null;
    engine.onError = null;
    engine.onProgress = null;
    engine.onActivity = null;
    engine.onDebugTrace = null;
    if (engine is TtsResourceProgressCapable) {
      (engine as TtsResourceProgressCapable).onResourceProgress = null;
    }
    if (engine is VoiceLibraryCapable) {
      (engine as VoiceLibraryCapable).onVoiceLibraryChanged = null;
    }
    _voiceLibraryCapable = null;
  }

  /// One startup attempt owns all callbacks and publication. Failed attempts
  /// expose their root cause independently of playback and can be retried.
  Future<void> retryInitialization() {
    if (_runningEngineRetired && _engineSwitch == null) return _switchEngine();
    return _engineStartup ??= _initializeEngine().whenComplete(
      () => _engineStartup = null,
    );
  }

  Future<void> _initializeEngine() async {
    final revision = ++_startupRevision;
    final epoch = _engineEpoch;
    final engine = _ttsEngine;
    final identity = EngineSessionIdentity(_loadingEngineId, _loadingBits);
    bool current() =>
        _ownsEngine(engine, epoch) && revision == _startupRevision;
    _isInitializing = true;
    _startupError = null;
    _synthesisInitialized = false;
    _publishEnginePhase(EngineSessionPhase.loading);
    notifyListeners();
    try {
      await engine.initialize().timeout(const Duration(seconds: 30));
      if (!current()) return;
      final voices = await engine.loadVoices();
      if (!current()) return;
      if (voices.isEmpty) {
        throw StateError('No installed speech voices are available.');
      }
      final requestedVoice =
          _selectedVoiceId ?? _narratorVoiceIds[_narratorScope];
      final savedVoice = voices
          .where((v) => v.id == requestedVoice)
          .firstOrNull;
      if (_audioBook != null && requestedVoice != null && savedVoice == null) {
        throw StateError(
          'Install the saved voice $requestedVoice to render this passage.',
        );
      }
      final initialVoice = savedVoice ?? voices.first;
      await engine.selectVoice(initialVoice);
      if (!current()) return;
      await engine.setSpeechRate(_voiceSpeeds[initialVoice.id] ?? 1.0);
      if (!current()) return;
      if (engine is ModelPreparationCapable) {
        await (engine as ModelPreparationCapable).prepareSelectedModel();
      }
      if (!current()) return;
      _publishEnginePhase(EngineSessionPhase.validating);
      notifyListeners();
      // Publish validated identity/voices together. An unavailable explicit
      // narrator remains unresolved; the temporary engine default is not intent.
      _voices = voices;
      _voiceLibrary = _voiceLibraryCapable?.voiceLibrary ?? _voiceLibrary;
      _selectedVoiceId = requestedVoice ?? initialVoice.id;
      _narratorVoiceIds.putIfAbsent(_narratorScope, () => initialVoice.id);
      _voiceSpeeds.putIfAbsent(_selectedVoiceId!, () => 1.0);
      _runningTtsEngineId = identity.engineId;
      _runningVoxtralQuantizationBits = identity.quantizationBits;
      _engineSession = EngineSession(
        epoch: epoch,
        selected: EngineSessionIdentity(
          _selectedTtsEngineId,
          _voxtralQuantizationBits,
        ),
        active: identity,
        lastWorking: identity,
        phase: EngineSessionPhase.active,
      );
      _startupError = null;
      _synthesisInitialized = true;
      _statusMessage = savedVoice == null && requestedVoice != null
          ? 'Saved narrator $requestedVoice is unavailable. Choose a voice to continue.'
          : null;
      unawaited(_persistPreferences());
    } catch (error) {
      if (!current()) return;
      _startupError = error is MissingPluginException
          ? 'Text to speech is unavailable on this platform.'
          : 'Speech startup failed: $error';
      _publishEnginePhase(EngineSessionPhase.failed);
      _statusMessage = _startupError;
      _pendingPlayUntilReady = false;
    } finally {
      if (current()) {
        _speechResourceProgress = null;
        _isInitializing = false;
        notifyListeners();
        _resumePendingPlay();
      }
    }
  }

  Future<void> importDocument() async {
    await _runImportOperation((revision) async {
      await stopLiveRead(clearStatus: true, cancelPreparation: false);
      _requireRevision(revision);
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        withData: false,
        initialDirectory: _lastOpenedDirectoryPath,
        allowedExtensions: DocumentImportService.supportedExtensions,
      );
      _requireRevision(revision);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.path == null && file.bytes == null) {
        throw StateError('The selected file could not be read.');
      }
      await _loadImportedBytes(
        revision: revision,
        fileName: file.name,
        bytes: file.bytes,
        acquireBytes: file.path == null
            ? null
            : () => _readBytesWithAccessRecovery(
                sourceLabel: 'picked file',
                sourcePath: file.path,
                readBytes: File(file.path!).readAsBytes,
                revision: revision,
              ),
        sourcePath: file.path,
      );
    }, errorSourceLabel: 'picked file');
  }

  Future<void> importDroppedFiles(List<XFile> files) =>
      _importXFiles(files, sourceLabel: 'Dropped');

  Future<void> importFilePaths(
    List<String> paths, {
    String sourceLabel = 'Opened',
    bool surfaceErrors = true,
  }) => _importXFiles(
    paths.map(XFile.new).toList(growable: false),
    sourceLabel: sourceLabel,
    surfaceErrors: surfaceErrors,
  );

  Future<void> importPastedText(String text) async {
    await _runImportOperation((revision) async {
      await stopLiveRead(clearStatus: false, cancelPreparation: false);
      _requireRevision(revision);
      if (text.trim().isEmpty) {
        throw StateError('Paste some text before importing it.');
      }
      final imported = await _prepare(
        revision,
        DocumentPreparationKind.pastedText,
        text: text.trim(),
      );
      await _replaceDocument(imported, revision: revision);
    });
  }

  Future<void> loadSampleDocument() async {
    await _runImportOperation((revision) async {
      await stopLiveRead(clearStatus: false, cancelPreparation: false);
      final document = await _prepare(revision, DocumentPreparationKind.sample);
      await _replaceDocument(document, revision: revision);
    });
  }

  Future<void> loadDocument(ReaderDocument document) async {
    await _runImportOperation((revision) async {
      await stopLiveRead(clearStatus: false, cancelPreparation: false);
      await _replaceDocument(document, revision: revision);
    });
  }

  Future<void> pickAndStartLiveRead() async {
    await _runImportOperation((revision) async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        withData: false,
        allowMultiple: false,
        initialDirectory: _lastOpenedDirectoryPath,
        allowedExtensions: DocumentImportService.supportedExtensions,
      );
      _requireRevision(revision);
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null || path.trim().isEmpty) {
        throw StateError('The selected live read file could not be accessed.');
      }
      await startLiveReadFromPath(path);
    }, errorSourceLabel: 'Live Feed');
  }

  Future<void> startLiveReadFromPath(String sourcePath) async {
    final revision = _beginDocumentRequest();
    final session = ++_watchSession;
    final normalizedPath = p.normalize(sourcePath.trim());
    await _runImportOperation(
      (revision) async {
        await _cancelLiveReadWatch();
        _requireRevision(revision);
        if (sourcePath.trim().isEmpty || !await File(normalizedPath).exists()) {
          _requireRevision(revision);
          throw StateError('Live read file was not found: $normalizedPath');
        }
        _requireRevision(revision);
        _liveReadFilePath = normalizedPath;
        await _reloadLiveReadFile(initialLoad: true, revision: revision);
        _requireRevision(revision);
        if (session != _watchSession) throw const _SupersededPreparation();
        await _rememberOpenedDocumentPath(normalizedPath, revision: revision);
        _requireRevision(revision);
        await _startLiveReadWatch(normalizedPath, session);
      },
      revision: revision,
      errorSourceLabel: 'live read file',
    );
  }

  Future<void> stopLiveRead({
    bool clearStatus = false,
    bool cancelPreparation = true,
  }) async {
    final wasLive = _liveReadFilePath != null || _liveReadSubscription != null;
    ++_watchSession;
    if (cancelPreparation && (wasLive || _isImporting)) {
      _beginDocumentRequest();
      _documentPrepared = true;
      _isImporting = false;
      _clearDocumentLoadStage();
    }
    _liveReadFilePath = null;
    final session = _watchSession;
    await _cancelLiveReadWatch();
    if (_disposed || session != _watchSession) return;
    if (clearStatus) {
      _statusMessage = null;
    } else if (wasLive) {
      _statusMessage = 'Live read mode stopped.';
    }
    notifyListeners();
  }

  Future<bool> restoreLastOpenedDocument() async {
    final lastPath = _lastOpenedDocumentPath;
    if (lastPath == null || lastPath.trim().isEmpty) {
      _logRestoreDiagnostic(
        'Skipped startup restore because no remembered document path exists.',
      );
      return false;
    }

    final revision = _beginDocumentRequest();
    final requestedPath = p.normalize(lastPath.trim());
    final requestedDirectoryPath = p.normalize(p.dirname(requestedPath));
    var restorePath = requestedPath;
    DocumentAccessLease? lease;
    var attemptedPersistentAccess = false;

    try {
      var directoryToken = _lastOpenedDirectoryAccessToken;
      var token = _lastOpenedDocumentAccessToken;
      _logRestoreDiagnostic(
        'Starting startup restore.',
        context: <String, Object?>{
          'requestedPath': requestedPath,
          'requestedDirectoryPath': requestedDirectoryPath,
          'hasStoredDirectoryToken':
              directoryToken != null && directoryToken.trim().isNotEmpty,
          'hasStoredToken': token != null && token.trim().isNotEmpty,
          'resumeDocumentPath': _resumeState?.documentPath,
        },
      );

      if (directoryToken != null && directoryToken.trim().isNotEmpty) {
        attemptedPersistentAccess = true;
        try {
          lease = await _documentAccessService.openPersistentRestoreToken(
            directoryToken,
          );
          _requireRevision(revision);
          if (lease != null) {
            final resolvedDirectoryPath = p.normalize(lease.path.trim());
            _lastOpenedDirectoryPath = resolvedDirectoryPath;
            _lastOpenedDirectoryAccessToken =
                lease.refreshedToken ?? directoryToken;
            _logRestoreDiagnostic(
              'Opened persistent directory access for startup restore.',
              context: <String, Object?>{
                'requestedDirectoryPath': requestedDirectoryPath,
                'resolvedDirectoryPath': resolvedDirectoryPath,
                'refreshedToken': lease.refreshedToken != null,
              },
            );
          } else {
            _logRestoreDiagnostic(
              'Persistent directory token did not resolve to a readable lease.',
              context: <String, Object?>{
                'requestedDirectoryPath': requestedDirectoryPath,
              },
            );
          }
        } catch (error) {
          _requireRevision(revision);
          _logRestoreDiagnostic(
            'Could not reopen persistent directory access for the remembered document.',
            context: <String, Object?>{
              'requestedDirectoryPath': requestedDirectoryPath,
            },
            error: error,
          );
        }
      }

      if (lease == null && (token == null || token.trim().isEmpty)) {
        try {
          final bootstrappedToken = await _documentAccessService
              .createPersistentRestoreToken(requestedPath);
          _requireRevision(revision);
          if (bootstrappedToken != null &&
              bootstrappedToken.trim().isNotEmpty) {
            token = bootstrappedToken;
            _lastOpenedDocumentAccessToken = bootstrappedToken;
            _logRestoreDiagnostic(
              'Bootstrapped a missing restore token from the remembered path.',
              context: <String, Object?>{'requestedPath': requestedPath},
            );
          } else {
            _logRestoreDiagnostic(
              'No restore token was available for the remembered path; falling back to path access.',
              context: <String, Object?>{'requestedPath': requestedPath},
            );
          }
        } catch (error) {
          _requireRevision(revision);
          _logRestoreDiagnostic(
            'Failed to bootstrap a restore token from the remembered path.',
            context: <String, Object?>{'requestedPath': requestedPath},
            error: error,
          );
        }
      }

      if (lease == null && token != null && token.trim().isNotEmpty) {
        attemptedPersistentAccess = true;
        try {
          lease = await _documentAccessService.openPersistentRestoreToken(
            token,
          );
          _requireRevision(revision);
          if (lease != null) {
            restorePath = p.normalize(lease.path.trim());
            _lastOpenedDocumentAccessToken = lease.refreshedToken ?? token;
            if (restorePath != requestedPath) {
              _lastOpenedDocumentPath = restorePath;
            }
            _logRestoreDiagnostic(
              'Opened persistent restore access.',
              context: <String, Object?>{
                'requestedPath': requestedPath,
                'resolvedPath': restorePath,
                'refreshedToken': lease.refreshedToken != null,
              },
            );
          } else {
            _logRestoreDiagnostic(
              'Persistent restore token did not resolve to a readable lease; falling back to path access.',
              context: <String, Object?>{'requestedPath': requestedPath},
            );
          }
        } catch (error) {
          _requireRevision(revision);
          _logRestoreDiagnostic(
            'Could not reopen persistent restore access for the remembered document.',
            context: <String, Object?>{'requestedPath': requestedPath},
            error: error,
          );
        }
      }

      if (lease == null) {
        try {
          _logRestoreDiagnostic(
            attemptedPersistentAccess
                ? 'Requesting explicit directory access after persistent access was unavailable.'
                : 'Requesting explicit directory access because no persistent restore token was available.',
            context: <String, Object?>{
              'requestedPath': requestedPath,
              'requestedDirectoryPath': requestedDirectoryPath,
            },
          );
          lease = await _documentAccessService.requestPersistentDirectoryAccess(
            requestedDirectoryPath,
          );
          _requireRevision(revision);
          if (lease != null) {
            final resolvedDirectoryPath = p.normalize(lease.path.trim());
            _lastOpenedDirectoryPath = resolvedDirectoryPath;
            _lastOpenedDirectoryAccessToken =
                lease.refreshedToken ?? _lastOpenedDirectoryAccessToken;
            _logRestoreDiagnostic(
              'User granted explicit directory access for startup reopen.',
              context: <String, Object?>{
                'requestedPath': requestedPath,
                'resolvedDirectoryPath': resolvedDirectoryPath,
              },
            );
          } else {
            _logRestoreDiagnostic(
              'Explicit directory access was not granted; startup restore will fall back to path access.',
              context: <String, Object?>{
                'requestedPath': requestedPath,
                'requestedDirectoryPath': requestedDirectoryPath,
              },
            );
          }
        } catch (error) {
          _requireRevision(revision);
          _logRestoreDiagnostic(
            'Explicit directory access request failed.',
            context: <String, Object?>{
              'requestedPath': requestedPath,
              'requestedDirectoryPath': requestedDirectoryPath,
            },
            error: error,
          );
        }
      }

      final previousDocumentId = _document.displayDocument.documentId;
      _requireRevision(revision);
      await _importXFiles(
        <XFile>[XFile(restorePath)],
        revision: revision,
        sourceLabel: 'Restored',
        surfaceErrors: false,
      );
      _requireRevision(revision);
      final restoredSuccessfully =
          _currentDocumentPath == restorePath &&
          _document.displayDocument.documentId != previousDocumentId;
      _logRestoreDiagnostic(
        restoredSuccessfully
            ? 'Startup restore imported the remembered document.'
            : 'Startup restore did not replace the current document.',
        context: <String, Object?>{
          'requestedPath': requestedPath,
          'restorePath': restorePath,
          'currentDocumentPath': _currentDocumentPath,
          'documentTitle': _document.title,
          'documentType': _document.type.name,
        },
      );
      if (!restoredSuccessfully) {
        return false;
      }
      _restoreRememberedReadingPositionIfPossible(restorePath);
      return true;
    } on _SupersededPreparation {
      return false;
    } finally {
      if (!_disposed && revision == _documentRevision) {
        _isImporting = false;
        _clearDocumentLoadStage();
        notifyListeners();
      }
      await lease?.close();
      if (!_disposed && revision == _documentRevision) {
        await _persistPreferences();
      }
    }
  }

  Future<void> togglePlayback() async {
    if (_playbackActivity.isBuffering || hasPendingPlaybackIntent) {
      await pausePlayback();
      return;
    }
    if (_isPlaying) {
      await pausePlayback();
      return;
    }
    await startPlayback();
  }

  Future<void> startPlayback() async {
    if (_disposed) return;
    _playbackRequestedAt ??= DateTime.now();
    if (_audioBook != null && isDocumentPrepared) {
      _audioBook?.cancelRender();
      _resumeAfterPreparation = true;
      ++_playbackIntent;
      _playbackStartPending = true;
      await _drivePlaybackStarts();
      return;
    }
    if (!_synthesisInitialized && !_isInitializing && _startupError == null) {
      _pendingPlayUntilReady = true;
      _resumeAfterPreparation = true;
      await retryInitialization();
      return;
    }
    if (!isDocumentPrepared || _isInitializing) {
      _pendingPlayUntilReady = true;
      _resumeAfterPreparation = true;
      _statusMessage = _isInitializing
          ? 'Preparing speech resources…'
          : 'Preparing the requested reading range…';
      notifyListeners();
      return;
    }
    if (_startupError != null) {
      _statusMessage = _startupError;
      notifyListeners();
      return;
    }
    _resumeAfterPreparation = true;

    final anchor = _pausedVoiceReplayAnchor;
    if (voiceAssignmentState.hasPending &&
        anchor != null &&
        anchor.documentId == _document.displayDocument.documentId) {
      _assignmentReplayWord ??= anchor.startWordIndex;
      _currentWordIndex = _assignmentReplayWord!;
      _playbackEndedAtDocumentEnd = false;
      _explicitVoiceRebuffer = true;
    }
    if (voiceAssignmentState.requestedDefaultVoiceId == null) {
      _captureRequestedVoiceChoices(initialBuffering: true);
    }
    ++_playbackIntent;
    _playbackStartPending = true;
    await _drivePlaybackStarts();
  }

  Future<void> _drivePlaybackStarts() =>
      _playbackStartDriver ??= _pumpPlaybackStarts().whenComplete(() {
        _playbackStartDriver = null;
        if (_playbackStartPending && !_disposed && _resumeAfterPreparation) {
          unawaited(_drivePlaybackStarts());
        }
      });

  Future<void> _pumpPlaybackStarts() async {
    while (_playbackStartPending && !_disposed && _resumeAfterPreparation) {
      _playbackStartPending = false;
      final intent = _playbackIntent;
      final assignment = voiceAssignmentState.requestedRevision;
      try {
        await _startupStop;
        if (intent != _playbackIntent) continue;
        await _startPlaybackOnce(intent);
      } catch (error) {
        if (intent != _playbackIntent ||
            !_resumeAfterPreparation ||
            _disposed) {
          continue;
        }
        _voiceAssignments.fail(assignment, error);
        _statusMessage = 'Could not prepare the requested voices: $error';
        _playbackState = ReaderPlaybackPrimaryState.failed;
        _isPlaying = false;
        notifyListeners();
      }
    }
  }

  Future<void> _startPlaybackOnce(int playbackIntent) async {
    if (_disposed || !isDocumentPrepared) return;
    if (_audioBook case final book?) {
      if (await _startAudioBookPlayback(book, playbackIntent)) return;
      if (playbackIntent != _playbackIntent || !_resumeAfterPreparation) return;
    }
    final documentRevision = _documentRevision;
    final assignmentRevision = voiceAssignmentState.requestedRevision;
    bool current() =>
        !_disposed &&
        _resumeAfterPreparation &&
        playbackIntent == _playbackIntent &&
        documentRevision == _documentRevision &&
        _voiceAssignments.isCurrent(assignmentRevision);
    _voiceAssignments.preparing(
      assignmentRevision,
      initialBuffering: !_explicitVoiceRebuffer,
    );
    _resumeAfterPreparation = true;
    if (_document.speakableText.trim().isEmpty) {
      _statusMessage = 'This document does not contain readable text yet.';
      notifyListeners();
      return;
    }

    final voice = selectedVoice;
    if (voice == null) {
      _statusMessage = 'Choose a voice before starting playback.';
      notifyListeners();
      return;
    }
    if (_preparedAssignmentRevision != assignmentRevision ||
        _resourceBindings.any(
          (binding) =>
              binding.documentId != _document.displayDocument.documentId,
        )) {
      _invalidateResourceBindings();
    }
    if (!isResourcesReady) {
      try {
        await _prepareResourceBindings(documentRevision, isCurrent: current);
      } on _SupersededPreparation {
        return;
      } catch (error) {
        if (!current()) return;
        _voiceAssignments.fail(assignmentRevision, error);
        _statusMessage = 'Speech resources unavailable: $error';
        notifyListeners();
        return;
      }
    }
    if (!current()) return;

    if (_currentWordIndex >= _document.wordCount && _document.wordCount > 0) {
      _currentWordIndex = 0;
    }
    if (_playbackEndedAtDocumentEnd && _document.wordCount > 0) {
      _currentWordIndex = 0;
      _utteranceStartWordIndex = 0;
      _utteranceStartOffset = 0;
      _utteranceStartedAt = null;
      _playbackEndedAtDocumentEnd = false;
      _activeSpokenChunkId = null;
      _spokenSelection = const SpokenSelection.none();
      _readingFocusState = const ReadingFocusState();
      _narrationState = _narrationState.reset(recentRate: currentSpeed);
    }

    _statusMessage = null;
    _resetFollowerProgressSynchronization();
    _narrationState = _narrationState.copyWith(
      currentSectionMode: _sectionModeForCurrentPosition(),
      discourseMode: _discourseModeForCurrentPosition(),
      recentRate: currentSpeed,
      localPronunciationChoices: const <String, String>{},
    );
    final requestedRate = currentSpeed;
    await _primePlaybackPreparation();
    if (!current() || requestedRate != currentSpeed) return;
    await _ttsEngine.selectVoice(voice);
    if (!current()) return;
    await _ttsEngine.setSpeechRate(currentSpeed);
    if (!current()) return;
    await _ttsEngine.setVolume(1.0);
    if (!current()) return;

    _utteranceStartWordIndex = _currentWordIndex;
    _utteranceStartOffset = _document.charOffsetForWord(_currentWordIndex);
    _utteranceStartedAt = DateTime.now();
    _playbackState = ReaderPlaybackPrimaryState.bufferingFirstChunk;
    _playbackRequestedAt ??= DateTime.now();
    _recordPositionMapConfidenceIfNeeded();
    _activePlaybackDocumentId = _document.displayDocument.documentId;
    _activeAssignmentRevision = assignmentRevision;
    _activePlaybackIntent = playbackIntent;
    _acknowledgedPlaybackIntent = null;
    final initialRange = _activePreparedRange;
    final playbackDocumentId = _activePlaybackDocumentId!;
    final continuation = initialRange == null
        ? null
        : _rangeContinuation(
            initialRange: initialRange,
            playbackDocumentId: playbackDocumentId,
            assignmentRevision: assignmentRevision,
            voiceId: voice.id,
            rate: requestedRate,
            current: () =>
                !_disposed &&
                _resumeAfterPreparation &&
                documentRevision == _documentRevision &&
                playbackIntent == _playbackIntent,
          );

    final speakableTail = _document.speakableText.substring(
      _utteranceStartOffset,
    );
    await _ttsEngine.speak(
      TtsSpeakRequest(
        text: speakableTail,
        documentId: _document.displayDocument.documentId,
        sessionId: _narrationState.sessionId,
        normalizationVersion: _document.speechDocument.normalizationVersion,
        chunkPlan: _currentChunkPlan,
        planningContext: _currentPlanningContext,
        assignmentRevision: assignmentRevision,
        rangeSequence: initialRange?.sequence ?? 0,
        sourceWordOffset: initialRange?.range.wordStart ?? 0,
        continuation: continuation,
        onRenderedScene: _renderedSceneWriter(),
        isCurrent: current,
        onPlaybackReady: (ack) {
          if (!current() ||
              ack.assignmentRevision != assignmentRevision ||
              ack.documentId != _document.displayDocument.documentId) {
            return;
          }
          final expected = _resourceBindings.map((b) => b.fingerprint).toSet();
          if (!setEquals(expected, ack.bindingFingerprints)) return;
          _voiceAssignments.acknowledge(assignmentRevision);
          _pausedVoiceReplayAnchor = null;
          _acknowledgedPlaybackIntent = playbackIntent;
          _assignmentReplayWord = null;
          _explicitVoiceRebuffer = false;
          notifyListeners();
        },
        isResumedPlayback: _currentWordIndex > 0,
        speechDocument: _document.speechDocument,
        ttsArtifactSet: _currentRealization?.ttsArtifactSet,
        preparedResources: _ttsEngine is ResourcePreparationCapable
            ? resourceBindings
            : null,
      ),
    );
    notifyListeners();
  }

  TtsRangeContinuation _rangeContinuation({
    required DocumentPreparationPublication initialRange,
    required String playbackDocumentId,
    required int assignmentRevision,
    required String voiceId,
    required double rate,
    required bool Function() current,
  }) {
    // One snapshot of transport-effective choices. Pending user edits cannot
    // silently alter the currently playing generation's future ranges.
    final overrides = Map<String, String>.of(_castVoiceOverrides);
    final stored = _currentStoredCastVoiceAssignments();
    final multiVoice = _isMultiVoiceEnabled;
    var sequence = initialRange.sequence;
    var wordEnd = initialRange.range.wordEnd;
    var pulling = false;
    late TtsRangeContinuation continuation;
    continuation = TtsRangeContinuation(
      next: (previous, cancelled) async {
        if (pulling || previous != sequence) {
          throw StateError('Duplicate or out-of-order prepared range demand.');
        }
        pulling = true;
        try {
          final publication = await readPreparedRange(
            sequence + 1,
            cancelled: cancelled,
          );
          if (current() && publication == null) return null;
          if (!current() || publication == null) {
            throw const PlanningCancelled();
          }
          final range = publication;
          if (range.request.ownerId != _preparationOwner ||
              range.request.revision != _documentRevision ||
              range.range.wordStart != wordEnd ||
              range.range.wordEnd <= range.range.wordStart ||
              !range.isPreparationReady) {
            throw StateError(
              'Prepared range has missing or stale source coverage.',
            );
          }
          final context = _planningContext(
            fromStart: true,
            document: range.fragment,
            voiceId: voiceId,
            rate: rate,
            overrides: overrides,
            stored: stored,
            multiVoice: multiVoice,
          );
          if (context == null) {
            throw StateError('Prepared range has no speech.');
          }
          final window = await _planning.plan(context, maxChunks: 3);
          if (!current()) throw const PlanningCancelled();
          final requiredVoices = {
            voiceId,
            ...?context.routes?.castVoiceAssignments.assignments.map(
              (assignment) => assignment.effectiveVoiceId,
            ),
          };
          final resourceEngine = _ttsEngine;
          if (resourceEngine is ResourcePreparationCapable &&
              requiredVoices.any(
                (voice) => !_resourceBindings.any(
                  (binding) => binding.voiceId == voice,
                ),
              )) {
            final bindings =
                await (resourceEngine as ResourcePreparationCapable)
                    .prepareDocumentResources(
                      documentId: playbackDocumentId,
                      revision: assignmentRevision,
                      voiceIds: {
                        ..._resourceBindings.map((b) => b.voiceId),
                        ...requiredVoices,
                      },
                      pronunciationProfileId:
                          context.realization.selectedProfile.profileId,
                    );
            if (!current()) throw const PlanningCancelled();
            _resourceBindings = List.unmodifiable(bindings);
          }
          sequence = range.sequence;
          wordEnd = range.range.wordEnd;
          return TtsSpeakRequest(
            text: range.fragment.speakableText,
            documentId: playbackDocumentId,
            sessionId: _narrationState.sessionId,
            normalizationVersion:
                range.fragment.speechDocument.normalizationVersion,
            speechDocument: range.fragment.speechDocument,
            chunkPlan: window.plan,
            planningContext: context,
            ttsArtifactSet: window.realization.ttsArtifactSet,
            preparedResources: resourceEngine is ResourcePreparationCapable
                ? resourceBindings
                : null,
            assignmentRevision: assignmentRevision,
            rangeSequence: range.sequence,
            sourceWordOffset: range.range.wordStart,
            continuation: continuation,
            onRenderedScene: _renderedSceneWriter(
              document: range.fragment,
              sourceWordOffset: range.range.wordStart,
            ),
            isCurrent: current,
            onRangeActive: () {
              if (!current() || identical(_activePreparedRange, range)) return;
              _flushPendingFollowerProgress();
              _finalizeActiveSpokenChunk();
              _document = range.fragment;
              _activePreparedRange = range;
              _currentWordIndex = 0;
              _offerCharacterAnalysis();
              _utteranceStartOffset = 0;
              _currentPlanningContext = context;
              _currentChunkPlan = window.plan;
              _currentRealization = window.realization;
              releasePreparedRange(range.sequence - 1);
              notifyListeners();
            },
          );
        } finally {
          pulling = false;
        }
      },
    );
    return continuation;
  }

  Future<void> pausePlayback() async {
    _audioBook?.cancelRender();
    unawaited(_audioBook?.package.cancelAndDrain());
    _pendingPlayUntilReady = false;
    final engine = _ttsEngine;
    if (engine is VoiceAssignmentPlaybackCapable) {
      final anchor = _localPlaybackResumeAnchor();
      if (anchor != null &&
          anchor.documentId == _document.displayDocument.documentId) {
        _pausedVoiceReplayAnchor = anchor;
      }
    }
    ++_playbackIntent;
    _planning.cancel();
    _playbackStartPending = false;
    _resumeAfterPreparation = false;
    _flushPendingFollowerProgress();
    _activePlaybackDocumentId = null;
    _isPlaying = false;
    _playbackState = ReaderPlaybackPrimaryState.paused;
    _playbackActivity = const TtsPlaybackActivity.idle();
    _readingFocusState = _readingFocusState.copyWith(playbackActive: false);
    notifyListeners(); // Intent cancellation must not wait for native drain.
    await _ttsEngine.pause();
    await _flushResumePersistence();
    _finalizeActiveSpokenChunk();
    _activePlaybackDocumentId = null;
    _isPlaying = false;
    _playbackState = ReaderPlaybackPrimaryState.paused;
    _readingFocusState = _readingFocusState.copyWith(playbackActive: false);
    notifyListeners();
  }

  Future<void> jumpBySeconds(int seconds) async {
    if (_document.wordCount == 0 || _playbackActivity.isBuffering) return;
    _pausedVoiceReplayAnchor = null;
    _assignmentReplayWord = null;
    _explicitVoiceRebuffer = false;
    final deltaWords = (seconds * _wordsPerSecond).round();
    final targetWord = (_currentWordIndex + deltaWords).clamp(
      0,
      math.max(_document.wordCount - 1, 0),
    );
    final snappedTarget = _snapWordIndexToSegmentStart(targetWord.toInt());
    _currentWordIndex = snappedTarget;
    _offeredAnalysisWindow = null;
    _offerCharacterAnalysis();
    _playbackEndedAtDocumentEnd = false;
    _activeSpokenChunkId = null;
    _resetFollowerProgressSynchronization();
    _spokenSelection = const SpokenSelection.none();
    _readingFocusState = const ReadingFocusState();
    _narrationState = _narrationState
        .reset(recentRate: currentSpeed)
        .copyWith(
          currentSectionMode: _sectionModeForCurrentPosition(),
          discourseMode: _discourseModeForCurrentPosition(),
        );
    _currentRealization = null;
    _currentChunkPlan = null;
    _statusMessage =
        'Jumped ${seconds.abs()} seconds ${seconds < 0 ? 'back' : 'forward'}.';
    _activePlaybackDocumentId = null;

    if (_isPlaying) {
      await _ttsEngine.stop();
      _isPlaying = false;
      await startPlayback();
      return;
    }

    _playbackState = ReaderPlaybackPrimaryState.paused;

    notifyListeners();
  }

  void suspendReaderFollow() {
    if (_readingFocusState.followMode ==
        ReadingFocusFollowMode.suspendedByUser) {
      return;
    }
    _readingFocusState = _readingFocusState.copyWith(
      followMode: ReadingFocusFollowMode.suspendedByUser,
    );
    notifyListeners();
  }

  void resumeReaderFollow() {
    final activeDisplayBlockId =
        _spokenSelection.displayBlockId ??
        _readingFocusState.activeDisplayBlockId;
    if (activeDisplayBlockId == null &&
        _readingFocusState.followMode == ReadingFocusFollowMode.following) {
      return;
    }
    _readingFocusState = _readingFocusState.copyWith(
      followMode: ReadingFocusFollowMode.following,
      activeDisplayBlockId: activeDisplayBlockId,
      recenterRequestTick: _readingFocusState.recenterRequestTick + 1,
    );
    notifyListeners();
  }

  Future<void> selectVoiceById(String? voiceId) async {
    if (voiceId == null ||
        _voices.every((v) => v.id != voiceId) ||
        voiceId == _selectedVoiceId) {
      return;
    }
    _selectedVoiceId = voiceId;
    _narratorVoiceIds[_narratorScope] = voiceId;
    _voiceSpeeds.putIfAbsent(voiceId, () => 1.0);
    await _voiceChoicesEdited();
  }

  Future<void> setMultiVoiceEnabled(bool enabled) async {
    if (_isMultiVoiceEnabled == enabled) {
      return;
    }
    _isMultiVoiceEnabled = enabled;
    await _voiceChoicesEdited();
  }

  Future<void> installVoice(String voiceId) async {
    final voiceLibraryCapable = _voiceLibraryCapable;
    if (voiceLibraryCapable == null) {
      return;
    }

    try {
      await voiceLibraryCapable.installVoice(voiceId);
      await _refreshVoiceLibraryState();
    } catch (error) {
      _statusMessage =
          'Could not install the selected voice right now. Try again.';
      notifyListeners();
    }
  }

  Future<void> toggleVoicePreview(String voiceId) async {
    if (_activePreviewVoiceId == voiceId &&
        (_isVoicePreviewLoading || _isVoicePreviewPlaying)) {
      await stopVoicePreview();
      return;
    }
    await previewVoice(voiceId);
  }

  Future<void> previewVoice(String voiceId) async {
    final engine = _ttsEngine;
    final epoch = _engineEpoch;
    final preview = ++_previewRevision;
    bool current() => _ownsEngine(engine, epoch) && preview == _previewRevision;
    if (_isPlaying || _playbackActivity.isBuffering) await pausePlayback();
    if (!current() || _isInitializing) return;
    final voice = _voices.where((v) => v.id == voiceId).firstOrNull;
    if (voice == null) return;
    if (_activePreviewVoiceId != null) {
      await engine.stop();
      if (!current()) return;
    }
    _activePreviewVoiceId = voiceId;
    _invalidateResourceBindings();
    _isVoicePreviewLoading = true;
    _isVoicePreviewPlaying = false;
    notifyListeners();
    try {
      await engine.selectVoice(voice);
      if (!current()) return;
      await engine.setSpeechRate(_voiceSpeeds[voiceId] ?? 1.0);
      if (!current()) return;
      await engine.setVolume(1.0);
      if (!current()) return;
      await engine.speak(
        const TtsSpeakRequest(
          text: 'Hello. This is Read Aloud previewing this voice.',
          documentId: 'voice-preview',
        ),
      );
    } catch (_) {
      if (!current()) return;
      _resetPreviewState();
      await _restoreSelectedVoiceEngineState();
      if (!current()) return;
      _statusMessage = 'Voice preview failed.';
      notifyListeners();
    }
  }

  Future<void> stopVoicePreview({bool notify = true}) async {
    ++_previewRevision;
    final engine = _ttsEngine;
    final epoch = _engineEpoch;
    if (_activePreviewVoiceId == null) return;
    _resetPreviewState();
    if (notify && !_disposed) notifyListeners();
    await engine.stop();
    if (!_ownsEngine(engine, epoch)) return;
    await _restoreSelectedVoiceEngineState();
  }

  Future<void> setVoiceSpeed(double speed) async {
    final voiceId = _selectedVoiceId;
    if (voiceId == null) return;
    final effectiveRate = _effectiveSpeechRate(speed);
    if (voiceAssignmentState.hasPending) {
      final initial = _isInitialVoiceBuffering;
      _voiceSpeeds[voiceId] = effectiveRate;
      await _voiceChoicesEdited();
      if (initial) await _drivePlaybackStarts();
      return;
    }
    final restart =
        _isPlaying ||
        _playbackStartDriver != null ||
        _playbackActivity.isBuffering ||
        _playbackState == ReaderPlaybackPrimaryState.bufferingFirstChunk;
    if (restart) {
      ++_playbackIntent;
      await _ttsEngine.stop();
      _isPlaying = false;
    }
    _planning.cancel();
    _voiceSpeeds[voiceId] = effectiveRate;
    await _ttsEngine.setSpeechRate(effectiveRate);
    _wordsPerSecond = _estimateWordsPerSecond(
      voiceId: voiceId,
      rate: effectiveRate,
    );
    await _persistPreferences();
    if (restart && currentSpeed == effectiveRate) {
      await startPlayback();
      return;
    }
    notifyListeners();
  }

  Future<void> assignVoiceToCast(String castId, String voiceId) async {
    if (_selectedVoiceId == null ||
        _voices.every((voice) => voice.id != voiceId)) {
      return;
    }
    // Selecting a voice expresses intent even when it matches today's
    // automatic assignment. Only Reset returns the role to automatic routing.
    _editedCastIds.add(castId);
    _storeCastVoiceAssignment(castId, voiceId);
    await _voiceChoicesEdited();
  }

  Future<void> clearCastVoiceOverride(String castId) async {
    final storedAssignments = _currentStoredCastVoiceAssignments();
    if (!_castVoiceOverrides.containsKey(castId) &&
        !storedAssignments.containsKey(castId)) {
      return;
    }
    _editedCastIds.remove(castId);
    _clearStoredCastVoiceAssignment(castId);
    await _voiceChoicesEdited();
  }

  Future<void> setFontFamily(String fontFamily) async {
    if (_fontFamily == fontFamily) {
      return;
    }
    _fontFamily = fontFamily;
    await _persistPreferences();
    notifyListeners();
  }

  Future<void> setTtsEngineId(String engineId) => _setTtsEngineId(engineId);

  Future<void> _setTtsEngineId(
    String engineId, {
    bool preserveBookPlay = false,
  }) async {
    await _preferencesReady.future;
    if (!_knownTtsEngineIds.contains(engineId)) return;
    if (_selectedTtsEngineId == engineId && _startupError == null) return;
    _rememberNarratorIntent();
    final publishedNarrator = preserveBookPlay ? _selectedVoiceId : null;
    _selectedTtsEngineId = engineId;
    if (publishedNarrator != null) {
      _narratorVoiceIds[_narratorScope] = publishedNarrator;
    }
    if (_providedTtsEngine != null && _engineFactory == null) {
      _publishEnginePhase(_engineSession.phase);
      await _persistPreferences();
      notifyListeners();
      return;
    }
    _requestEngineReplacement(preserveBookPlay: preserveBookPlay);
    final transition = _switchEngine();
    await _persistPreferences();
    await transition;
  }

  Future<void> setVoxtralQuantizationBits(int bits) async {
    await _preferencesReady.future;
    if (bits != 0 && bits != 4) return;
    if (_voxtralQuantizationBits == bits && _startupError == null) return;
    _rememberNarratorIntent();
    _voxtralQuantizationBits = bits;
    if (_providedTtsEngine != null && _engineFactory == null) {
      _publishEnginePhase(_engineSession.phase);
      await _persistPreferences();
      notifyListeners();
      return;
    }
    _requestEngineReplacement();
    final transition = _switchEngine();
    await _persistPreferences();
    await transition;
  }

  void _requestEngineReplacement({bool preserveBookPlay = false}) {
    ++_engineEpoch;
    ++_startupRevision;
    ++_previewRevision;
    ++_playbackIntent;
    _pendingPlayUntilReady = false;
    if (!preserveBookPlay) _resumeAfterPreparation = false;
    _playbackStartPending = false;
    _runningEngineRetired = true;
    _synthesisInitialized = false;
    _selectedVoiceId = _narratorVoiceIds[_narratorScope];
    _planning.cancel();
    _resetPreviewState();
    _publishEnginePhase(EngineSessionPhase.stopping);
    _startupError = null;
    _statusMessage = _isExporting
        ? 'Audio export cancelled because the speech engine changed.'
        : 'Switching speech engine…';
    notifyListeners();
    // Interrupt an in-flight model acquisition through the existing out-of-band
    // owner. The serialized replacement joins this same idempotent shutdown.
    final retiringEngine = _ttsEngine;
    if (_engineSwitch != null && retiringEngine is ResourcePreparationCapable) {
      unawaited(
        (retiringEngine as ResourcePreparationCapable)
            .shutdownResources()
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _switchEngine() {
    if (_providedTtsEngine != null && _engineFactory == null) {
      return Future.value();
    }
    return _engineSwitch ??= _replaceEngine().whenComplete(() {
      _engineSwitch = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _replaceEngine() async {
    _isInitializing = true;
    _invalidateResourceBindings();
    _currentRealization = null;
    notifyListeners();
    try {
      while (!_disposed &&
          (ttsEngineRestartRequired || _runningEngineRetired)) {
        final old = _ttsEngine;
        _detachEngineCallbacks(old);
        _publishEnginePhase(EngineSessionPhase.unloading);
        notifyListeners();
        if (old is ResourcePreparationCapable) {
          // This owner cancels export/generation out of band before joining
          // native release. Never queue a separate stop ahead of shutdown.
          await (old as ResourcePreparationCapable).shutdownResources();
        } else {
          await old.stop();
        }
        old.dispose();
        await _engineStartup;
        if (_disposed) return;
        _resetPreviewState();
        _isPlaying = false;
        _activePlaybackDocumentId = null;
        _playbackActivity = const TtsPlaybackActivity.idle();
        _playbackState = ReaderPlaybackPrimaryState.paused;
        _speechResourceProgress = null;
        _readingFocusState = _readingFocusState.copyWith(playbackActive: false);
        final epoch = _engineEpoch;
        _loadingEngineId = _selectedTtsEngineId;
        _loadingBits = _voxtralQuantizationBits;
        _ttsEngine = _createEngine(_loadingEngineId, _loadingBits);
        _runningEngineRetired = false;
        _voices = const [];
        _voiceLibrary = const [];
        _bindEngineCallbacks();
        await retryInitialization();
        // A current failed target waits for explicit retry. An obsolete target
        // drains and reloads the latest choice, including A → B → A.
        if (epoch == _engineEpoch) break;
      }
    } catch (error) {
      if (_disposed) return;
      _startupError = 'Speech engine switch failed: $error';
      _publishEnginePhase(EngineSessionPhase.failed);
      _statusMessage = _startupError;
    } finally {
      if (!_disposed) {
        _isInitializing = false;
        notifyListeners();
      }
    }
  }

  Future<void> setFontScale(double fontScale) async {
    final normalized = fontScale.clamp(0.9, 1.6).toDouble();
    if ((_fontScale - normalized).abs() < 0.001) {
      return;
    }
    _fontScale = normalized;
    await _persistPreferences();
    notifyListeners();
  }

  Future<void> setAppearanceMode(ReaderAppearanceMode appearanceMode) async {
    if (_appearanceMode == appearanceMode) {
      return;
    }
    _appearanceMode = appearanceMode;
    await _persistPreferences();
    notifyListeners();
  }

  void setSleepTimer(Duration? duration) {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepTimerDuration = duration;
    _sleepTimerEndsAt = duration == null ? null : DateTime.now().add(duration);

    if (duration != null) {
      _sleepTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
        final endsAt = _sleepTimerEndsAt;
        if (endsAt == null) {
          timer.cancel();
          return;
        }
        if (DateTime.now().isAfter(endsAt)) {
          timer.cancel();
          unawaited(_fadeOutSleepTimer());
          return;
        }
        notifyListeners();
      });
    }

    notifyListeners();
  }

  Future<void> clearStatus() async {
    _statusMessage = null;
    notifyListeners();
  }

  void showStatusMessage(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void _resetPreviewState() {
    _activePreviewVoiceId = null;
    _isVoicePreviewLoading = false;
    _isVoicePreviewPlaying = false;
  }

  Future<void> _restoreSelectedVoiceEngineState() async {
    if (voiceAssignmentState.hasPending ||
        _isPlaying ||
        _isInitialVoiceBuffering) {
      return;
    }
    final selected = selectedVoice;
    if (selected == null) {
      return;
    }
    final engine = _ttsEngine;
    final epoch = _engineEpoch;
    final preview = _previewRevision;
    try {
      await engine.selectVoice(selected);
      if (!_ownsEngine(engine, epoch) || preview != _previewRevision) return;
      await engine.setSpeechRate(currentSpeed);
    } catch (_) {
      if (!_ownsEngine(engine, epoch) || preview != _previewRevision) return;
      _statusMessage =
          'Could not restore the narrator voice. Choose a voice to retry.';
      notifyListeners();
    }
  }

  Future<TtsExportResult?> exportAudioToPath(String outputPath) async {
    if (!hasCompleteDocumentSnapshot) {
      _statusMessage =
          'A complete document snapshot is required before saving whole-document audio.';
      notifyListeners();
      return null;
    }
    final exporter = _ttsEngine is AudioExportCapable
        ? _ttsEngine as AudioExportCapable
        : null;
    if (exporter == null) {
      _statusMessage =
          'Saving audio is not available with the current speech engine.';
      notifyListeners();
      return null;
    }
    if (_isExporting) {
      return null;
    }
    if (_document.speakableText.trim().isEmpty) {
      _statusMessage = 'This document does not contain readable text yet.';
      notifyListeners();
      return null;
    }

    final voice = selectedVoice;
    if (voice == null) {
      _statusMessage = 'Choose a voice before saving audio.';
      notifyListeners();
      return null;
    }

    final normalizedPath = outputPath.trim();
    if (normalizedPath.isEmpty) {
      _statusMessage = 'Choose where to save the exported audio first.';
      notifyListeners();
      return null;
    }

    final exportEpoch = _engineEpoch;
    final exportEngine = _ttsEngine;
    final exportRevision = _documentRevision;
    final exportAssignmentRevision = voiceAssignmentState.requestedRevision;
    bool current() =>
        _ownsEngine(exportEngine, exportEpoch) &&
        exportRevision == _documentRevision;
    void requireCurrent() {
      if (!current()) throw const PlanningCancelled();
    }

    _isExporting = true;
    _statusMessage = 'Saving audio with ${voice.displayName}...';
    notifyListeners();

    try {
      await requirePreservedDocumentExportPath(
        normalizedPath,
        sourcePath: _currentDocumentPath,
      );
      requireCurrent();
      final document = await _completeExportDocument(exportRevision);
      requireCurrent();
      if (exportAssignmentRevision != voiceAssignmentState.requestedRevision) {
        throw const PlanningCancelled();
      }
      if (!isResourcesReady ||
          _preparedAssignmentRevision != exportAssignmentRevision ||
          !_hasCompleteDocumentSnapshot) {
        await _prepareResourceBindings(
          exportRevision,
          document: document,
          isCurrent: () =>
              current() &&
              exportRevision == _documentRevision &&
              _voiceAssignments.isCurrent(exportAssignmentRevision),
        );
      }

      requireCurrent();
      if (exportAssignmentRevision != voiceAssignmentState.requestedRevision) {
        throw StateError(
          'Voice choices changed before export preparation completed.',
        );
      }
      final exportRequest = await _buildExportRequest(
        normalizedPath,
        document: document,
      );
      requireCurrent();
      final result = await exporter.exportAudio(exportRequest);
      requireCurrent();
      if (current()) {
        _statusMessage = 'Saved audio to ${result.outputPath}.';
      }
      return result;
    } catch (error) {
      if (current()) {
        _recordCheckpointExportFailure(error);
        _statusMessage = _preparationFailed
            ? 'The prepared checkpoint is damaged. Retry document preparation before saving.'
            : 'Could not save audio right now. Try again.';
      }
      return null;
    } finally {
      _isExporting = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Exports a regular v4 snapshot that the normal Open Document route reads.
  /// Only a complete in-memory graph or complete committed checkpoint qualifies.
  /// Replacement/cancellation suppresses the atomic rename of a staged export.
  Future<File?> exportDocumentToPath(
    String outputPath, {
    bool audioBook = false,
  }) async {
    if (_documentExportWork != null) return null;
    final work = _exportDocumentToPath(outputPath, forceAudioBook: audioBook);
    _documentExportWork = work;
    try {
      return await work;
    } finally {
      if (identical(_documentExportWork, work)) _documentExportWork = null;
    }
  }

  Future<File?> _exportDocumentToPath(
    String outputPath, {
    bool forceAudioBook = false,
  }) async {
    if (!hasCompleteDocumentSnapshot || _isExporting) return null;
    final revision = _documentRevision;
    final epoch = _engineEpoch;
    final assignments = Map<String, String>.unmodifiable(
      _characters.selections(_voicePreferenceDocumentId),
    );
    final characters = _characters.registry(
      _voicePreferenceDocumentId,
      documentId: sessionDocumentId,
    );
    _isExporting = true;
    bool current() =>
        !_disposed && revision == _documentRevision && epoch == _engineEpoch;
    void requireCurrent() {
      if (!current()) throw const PlanningCancelled();
    }

    notifyListeners();
    try {
      await requirePreservedDocumentExportPath(
        outputPath,
        sourcePath: _currentDocumentPath,
      );
      requireCurrent();
      final audioBook = await _exportAudioBookToPath(
        outputPath,
        revision,
        force: forceAudioBook,
      );
      if (audioBook != null) return audioBook;
      final request = _activePreparationRequest;
      final repository = _preparation.repository;
      final recordMap = {
        for (final record in _document.analysisRecords) record.key: record,
      };
      if (repository != null) {
        for (final record in await repository.analysis.recordsForSource(
          request?.effectiveSourceRevision ??
              _document.normalizedImportResult.sourceFingerprint,
        )) {
          recordMap[record.key] = record;
        }
      }
      requireCurrent();
      final analysisRecords = List<DocumentAnalysisRecord>.unmodifiable(
        recordMap.values,
      );
      if (!_hasCompleteDocumentSnapshot &&
          request != null &&
          repository != null) {
        final cache = await repository.open(
          sourceKey: request.effectiveSourceRevision,
          sourceRevision: request.effectiveSourceRevision,
        );
        requireCurrent();
        if (cache == null) {
          throw const FormatException('Prepared checkpoint unavailable');
        }
        return await cache.exportToFile(
          request: request,
          documentId: sessionDocumentId,
          outputPath: outputPath,
          isCurrent: current,
          userVoiceAssignments: assignments,
          characters: characters,
          analysisRecords: analysisRecords,
        );
      }
      final document = await _completeExportDocument(revision);
      return await const ReaderDocumentSerializationService().writeToFile(
        document: document,
        outputPath: outputPath,
        isCurrent: current,
        userVoiceAssignments: assignments,
        characters: characters,
        analysisRecords: analysisRecords,
      );
    } catch (error) {
      if (current()) {
        _logDiagnostic('Document publication failed', error: error);
        _recordCheckpointExportFailure(error);
        _statusMessage = _preparationFailed
            ? 'The prepared checkpoint is damaged. Retry document preparation before saving.'
            : 'Could not save the complete document.';
      }
      return null;
    } finally {
      _isExporting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _recordCheckpointExportFailure(Object error) {
    if (error is! FormatException || _hasCompleteDocumentSnapshot) return;
    _preparationComplete = false;
    _preparationFailed = true;
    _preparationError = error;
    _signalRanges();
  }

  Future<ReaderDocument> _completeExportDocument(int revision) async {
    _requireRevision(revision);
    if (_hasCompleteDocumentSnapshot) return _document;
    final request = _activePreparationRequest;
    final repository = _preparation.repository;
    if (!_preparationComplete || request == null || repository == null) {
      throw StateError('A complete prepared checkpoint is required');
    }
    final cache = await repository.open(
      sourceKey: request.effectiveSourceRevision,
      sourceRevision: request.effectiveSourceRevision,
    );
    _requireRevision(revision);
    if (cache == null) {
      throw const FormatException('Prepared checkpoint unavailable');
    }
    // Resident audio resources belong to this playback identity, even when the
    // reader currently displays a later range. The saved radoc uses the session
    // identity separately so local user choices follow it on reopen.
    final documentId =
        _resourceBindings.firstOrNull?.documentId ??
        _activePlaybackDocumentId ??
        _document.displayDocument.documentId;
    return cache.readCompleteDocument(
      request: request,
      documentId: documentId,
      isCurrent: () => !_disposed && revision == _documentRevision,
    );
  }

  Future<void> _initializeIntakeChannels() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      _fileOpenSubscription = FileOpen.onOpened.listen((uris) {
        unawaited(importOpenedUris(uris));
      });
    }

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        final initialShare = await _shareIntake.getInitialShare();
        if (initialShare != null && initialShare.hasContent) {
          await _handleSharedData(
            initialShare,
            sourceLabel: 'Shared',
            clearAfterHandling: true,
          );
        }

        _shareSubscription = _shareIntake.getMediaStream().listen((sharedData) {
          unawaited(_handleSharedData(sharedData, sourceLabel: 'Shared'));
        });
      } on MissingPluginException {
        // Plugin is not wired for the current platform test harness.
      } catch (_) {
        // Leave share ingestion unavailable until native wiring exists.
      }
    }
  }

  Future<void> importOpenedUris(List<Uri> uris) async {
    final files = uris
        .where((uri) => uri.scheme.isEmpty || uri.scheme == 'file')
        .map((uri) => XFile(uri.toFilePath()))
        .toList(growable: false);

    if (files.isEmpty) {
      return;
    }

    await _importXFiles(files, sourceLabel: 'Opened');
  }

  Future<void> _handleSharedData(
    SharedIntake sharedData, {
    required String sourceLabel,
    bool clearAfterHandling = false,
  }) async {
    if (!sharedData.hasContent) {
      return;
    }

    if (sharedData.filePaths.isNotEmpty) {
      final files = sharedData.filePaths.map(XFile.new).toList(growable: false);
      await _importXFiles(files, sourceLabel: sourceLabel);
    } else if (sharedData.text?.trim().isNotEmpty ?? false) {
      await _runImportOperation((revision) async {
        await stopLiveRead(clearStatus: false, cancelPreparation: false);
        final document = await _prepare(
          revision,
          DocumentPreparationKind.sharedText,
          text: sharedData.text!,
        );
        await _replaceDocument(document, revision: revision);
      }, errorSourceLabel: sourceLabel);
    }

    if (clearAfterHandling) {
      await _shareIntake.clearSharedData();
    }
  }

  Future<void> _importXFiles(
    List<XFile> files, {
    int? revision,
    required String sourceLabel,
    bool surfaceErrors = true,
  }) async {
    if (files.isEmpty) return;
    await _runImportOperation(
      (revision) async {
        await stopLiveRead(clearStatus: false, cancelPreparation: false);
        _requireRevision(revision);
        final file = files.first;
        await _loadImportedBytes(
          revision: revision,
          fileName: file.name.isNotEmpty
              ? file.name
              : _fallbackFileName(file.path),
          acquireBytes: () => _readBytesWithAccessRecovery(
            sourceLabel: sourceLabel,
            sourcePath: file.path,
            readBytes: file.readAsBytes,
            revision: revision,
          ),
          sourcePath: file.path,
        );
      },
      revision: revision,
      errorSourceLabel: sourceLabel,
      surfaceErrors: surfaceErrors,
    );
  }

  Future<void> _loadImportedBytes({
    required int revision,
    required String fileName,
    Uint8List? bytes,
    Future<Uint8List> Function()? acquireBytes,
    String? sourcePath,
  }) async {
    await _audioBookRetirement;
    _requireRevision(revision);
    if (p.extension(fileName).toLowerCase() == '.radoc') {
      if (sourcePath != null &&
          await RadocAudioPackage.isPackage(File(sourcePath))) {
        _requireRevision(revision);
        await _openAudioBook(sourcePath, revision);
        return;
      }
      final serializedBytes = bytes ?? await acquireBytes!();
      _requireRevision(revision);
      late final ({
        ReaderDocument document,
        Map<String, String> userVoiceAssignments,
      })
      restored;
      try {
        final serialized = utf8.decode(serializedBytes, allowMalformed: false);
        restored = await _restoreDocumentOnWorker(serialized);
      } catch (error) {
        throw DocumentImportException(
          code: 'invalid_radoc',
          fileName: fileName,
          message:
              'This .radoc file is malformed or uses an unsupported format. '
              'Re-export it with a compatible Read Aloud version and try again.',
          cause: error,
        );
      }
      _requireRevision(revision);
      _preparationComplete = true;
      _hasCompleteDocumentSnapshot = true;
      _preparedRanges.clear();
      _publicationSequence = 0;
      await _replaceDocument(
        restored.document,
        sourcePath: sourcePath,
        revision: revision,
        restoredVoiceAssignments: restored.userVoiceAssignments,
        restoreCharacters: true,
      );
      _requireRevision(revision);
      await _persistPreferences();
      _requireRevision(revision);
      await _rememberOpenedDocumentPath(sourcePath, revision: revision);
      return;
    }
    // Security-scoped bookmark creation can update the source's ctime without
    // changing its bytes. Finish that metadata write before capturing the
    // immutable acquisition revision, and never repeat it during acquisition.
    String? preparedRestoreToken;
    if (sourcePath != null) {
      try {
        preparedRestoreToken =
            p.normalize(sourcePath) == _lastOpenedDocumentPath &&
                (_lastOpenedDocumentAccessToken?.isNotEmpty ?? false)
            ? _lastOpenedDocumentAccessToken
            : await _documentAccessService.createPersistentRestoreToken(
                sourcePath,
              );
      } catch (_) {
        // Access recovery and diagnostics remain owned by the import boundary.
      }
      _requireRevision(revision);
    }
    final imported = await _prepare(
      revision,
      DocumentPreparationKind.bytes,
      fileName: fileName,
      bytes: bytes,
      acquireBytes: acquireBytes,
      sourcePath: sourcePath,
    );
    await _replaceDocument(
      imported,
      sourcePath: sourcePath,
      revision: revision,
    );
    _requireRevision(revision);
    await _rememberOpenedDocumentPath(
      sourcePath,
      revision: revision,
      restoreTokenPrepared: true,
      preparedRestoreToken: preparedRestoreToken,
    );
  }

  Future<void> _prepareResourceBindings(
    int revision, {
    ReaderDocument? document,
    required bool Function() isCurrent,
  }) async {
    // One attempt per owner. The playback pump admits newer intent. An obsolete
    // document must not retry inside a suspended resource-preparation frame.
    _requireRevision(revision);
    if (!isCurrent()) throw const _SupersededPreparation();
    final resourceDocument = document ?? _document;
    final intent = _resourceBindingIntent;
    final assignmentRevision = voiceAssignmentState.requestedRevision;
    final resourceEngine = _ttsEngine;
    if (resourceEngine is ResourcePreparationCapable &&
        _selectedVoiceId != null) {
      final assignments = _resolveCastVoiceAssignments(
        preferredNarratorVoiceId: _selectedVoiceId!,
        document: resourceDocument,
      );
      final ticket = beginReadingStage(
        PreparationStage.resources,
        producerId: 'resident-speech-resources',
        scope: 'Current prepared range voice bindings',
      );
      publishReadingStage(
        ticket,
        const PreparationProgress(
          stage: PreparationStage.resources,
          state: PreparationWorkState.working,
          completed: 0,
          unit: 'voices',
        ),
      );
      void requireCurrent() {
        _requireRevision(revision);
        if (!isCurrent() ||
            intent != _resourceBindingIntent ||
            !_voiceAssignments.isCurrent(assignmentRevision)) {
          publishReadingStage(
            ticket,
            const PreparationProgress(
              stage: PreparationStage.resources,
              state: PreparationWorkState.cancelled,
              completed: 0,
              unit: 'voices',
            ),
          );
          throw const _SupersededPreparation();
        }
      }

      requireCurrent();
      final bindings = await (resourceEngine as ResourcePreparationCapable)
          .prepareDocumentResources(
            documentId: resourceDocument.displayDocument.documentId,
            revision: assignmentRevision,
            voiceIds: {
              _selectedVoiceId!,
              ...?assignments?.assignments.map((v) => v.effectiveVoiceId),
            },
            pronunciationProfileId: _selectedPronunciationProfile().profileId,
          )
          .catchError((Object error) {
            requireCurrent();
            publishReadingStage(
              ticket,
              PreparationProgress(
                stage: PreparationStage.resources,
                state: PreparationWorkState.failed,
                completed: 0,
                unit: 'voices',
                error: '$error',
              ),
            );
            throw error;
          });
      requireCurrent();
      if (bindings.any(
        (binding) =>
            binding.documentId != resourceDocument.displayDocument.documentId ||
            binding.bindingRevision != assignmentRevision ||
            binding.pronunciationProfileId !=
                _selectedPronunciationProfile().profileId,
      )) {
        throw StateError(
          'Prepared resource identity does not match the document.',
        );
      }
      _resourceBindings = List.unmodifiable(bindings);
      _preparedAssignmentRevision = assignmentRevision;
      _resolvedResourceBindings = List.unmodifiable([
        for (final assignment
            in assignments?.assignments ?? <CastVoiceAssignment>[])
          for (final binding in bindings)
            if (binding.voiceId == assignment.effectiveVoiceId)
              ResolvedPreparedVoiceReference(
                assignment: assignment,
                resource: binding,
                documentRevision: revision,
              ),
      ]);
      publishReadingStage(
        ticket,
        PreparationProgress(
          stage: PreparationStage.resources,
          state: PreparationWorkState.complete,
          completed: bindings.length,
          total: bindings.length,
          unit: 'voices',
        ),
      );
    }
  }

  Future<void> _replaceDocument(
    ReaderDocument document, {
    required int revision,
    String? statusMessage,
    String? sourcePath,
    Map<String, String> restoredVoiceAssignments = const {},
    bool restoreCharacters = false,
  }) async {
    _requireRevision(revision);
    _activePlaybackDocumentId = null;
    await _ttsEngine.stop();
    _requireRevision(revision);
    _finalizeActiveSpokenChunk();
    _document = document;
    characterAnalysis.restoreRecords(document.analysisRecords);
    _analysisContentSource = restoreCharacters
        ? document.analysisRecords
              .where((r) => r.reusable)
              .firstOrNull
              ?.sourceRevision
        : null;
    if (restoreCharacters ||
        _offeredAnalysisRequest?.sourceRevision != _characterSourceRevision) {
      _offeredAnalysisWindow = null;
      _offeredAnalysisRequest = null;
    }
    _activePreparedRange = _preparedRanges
        .where((range) => identical(range.fragment, document))
        .firstOrNull;
    if (_publicationSequence == 0) _preparationComplete = true;
    _hasCompleteDocumentSnapshot =
        _preparationComplete && _publicationSequence <= 1;
    final initialId = document.displayDocument.documentId;
    _sessionDocumentId = _documentIdentityRedirects[initialId] ?? initialId;
    if (restoreCharacters) {
      _characters.restoreDocument(
        _voicePreferenceDocumentId,
        document.characterCastRegistry,
      );
    }
    _characters.migrateLegacy({
      _voicePreferenceDocumentId: restoredVoiceAssignments,
    });
    _mergeDiscoveredCast(document.characterCastRegistry, document: document);
    _voiceAssignments.resetDocument();
    _pausedVoiceReplayAnchor = null;
    _assignmentReplayWord = null;
    _explicitVoiceRebuffer = false;
    _preparedDocumentRevision = revision;
    _documentPrepared = false;
    _resourceBindings = const [];
    _currentDocumentPath = (sourcePath == null || sourcePath.trim().isEmpty)
        ? null
        : p.normalize(sourcePath.trim());
    _currentWordIndex = 0;
    _wordsPerSecond = 2.8;
    _isPlaying = false;
    _isFadingOut = false;
    _playbackEndedAtDocumentEnd = false;
    _playbackState = ReaderPlaybackPrimaryState.idle;
    _playbackActivity = const TtsPlaybackActivity.idle();
    _spokenChunkRecords.clear();
    _activeSpokenChunkId = null;
    _resetFollowerProgressSynchronization();
    _spokenSelection = const SpokenSelection.none();
    _editedCastIds.clear();
    _readingFocusState = const ReadingFocusState();
    _utteranceStartOffset = 0;
    _utteranceStartWordIndex = 0;
    _utteranceStartedAt = null;
    _playbackRequestedAt = null;
    _latencyRecordedSessions.clear();
    _positionConfidenceRecordedSessions.clear();
    _narrationState = NarrationState.initial(recentRate: currentSpeed);
    _currentRealization = null;
    _currentChunkPlan = null;
    // Range mapping/analysis/pronunciation are already prepared by the worker.
    // Plan/resource binding is demanded by Play rather than gating display.
    _documentPrepared = true;

    _clearDocumentLoadStage();
    _statusMessage = statusMessage;
    if (_statusMessage == null && document.wordCount == 0) {
      _statusMessage =
          'Loaded ${document.title}, but no readable text was extracted yet.';
    }
    _offerCharacterAnalysis();
    notifyListeners();
    _resumePendingPlay();
  }

  Future<void> _fadeOutSleepTimer() async {
    _isFadingOut = true;
    notifyListeners();

    if (_isPlaying) {
      const steps = 12;
      for (var step = steps; step >= 0; step -= 1) {
        await _ttsEngine.setVolume(step / steps);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      await pausePlayback();
      await _ttsEngine.setVolume(1.0);
    }

    _sleepTimerDuration = null;
    _sleepTimerEndsAt = null;
    _isFadingOut = false;
    _statusMessage = 'Sleep timer finished with a fade-out.';
    notifyListeners();
  }

  void _handleVoiceLibraryChanged() {
    _voiceLibrary = _voiceLibraryCapable?.voiceLibrary ?? const [];
    if (_isInitializing) {
      notifyListeners();
      return;
    }
    unawaited(_refreshVoiceLibraryState());
  }

  Future<void> _refreshVoiceLibraryState() async {
    final engine = _ttsEngine;
    final epoch = _engineEpoch;
    final library = _voiceLibraryCapable;
    final voices = await engine.loadVoices();
    if (!_ownsEngine(engine, epoch)) return;
    _voiceLibrary = library?.voiceLibrary ?? const [];
    _voices = voices;
    if (_selectedVoiceId == null && voices.isNotEmpty) {
      _selectedVoiceId = voices.first.id;
      _narratorVoiceIds[_narratorScope] = voices.first.id;
      await engine.selectVoice(voices.first);
      if (!_ownsEngine(engine, epoch)) return;
      await engine.setSpeechRate(currentSpeed);
      if (!_ownsEngine(engine, epoch)) return;
      await _persistPreferences();
    }
    if (!_ownsEngine(engine, epoch)) return;
    notifyListeners();
  }

  void _handleProgress(TtsProgressUpdate update) {
    final activePlaybackDocumentId = _activePlaybackDocumentId;
    if (activePlaybackDocumentId == null) {
      return;
    }
    final updateDocumentId = update.documentId;
    if (updateDocumentId != null &&
        updateDocumentId != activePlaybackDocumentId) {
      return;
    }
    _recordProgress(update);
    final wordOffset = _activePreparedRange?.range.wordStart ?? 0;
    if (wordOffset != 0 && update.wordStartIndex != null) {
      update = TtsProgressUpdate(
        sceneTurns: update.sceneTurns,
        startOffset: update.startOffset,
        endOffset: update.endOffset,
        word: update.word,
        documentId: update.documentId,
        chunkId: update.chunkId,
        segmentId: update.segmentId,
        wordStartIndex: update.wordStartIndex! - wordOffset,
        wordEndIndex: update.wordEndIndex == null
            ? null
            : update.wordEndIndex! - wordOffset,
        elapsedInChunk: update.elapsedInChunk,
        chunkAudioDuration: update.chunkAudioDuration,
        voiceId: update.voiceId,
        rate: update.rate,
        routeId: update.routeId,
        castId: update.castId,
        dialogueSpanId: update.dialogueSpanId,
      );
    }
    final globalOffset = _utteranceStartOffset + update.endOffset;
    final nextWordIndex =
        update.wordEndIndex ?? _document.wordIndexForOffset(globalOffset);

    if (update.wordEndIndex == null) {
      final elapsed = _utteranceStartedAt == null
          ? 0.0
          : DateTime.now().difference(_utteranceStartedAt!).inMilliseconds /
                1000;
      final wordsRead = math.max(1, nextWordIndex - _utteranceStartWordIndex);

      if (elapsed > 0.5) {
        final observed = wordsRead / elapsed;
        _wordsPerSecond = (_wordsPerSecond * 0.8) + (observed * 0.2);
      }
    }

    _currentWordIndex = nextWordIndex.clamp(
      0,
      math.max(_document.wordCount - 1, 0),
    );
    _playbackEndedAtDocumentEnd = false;
    _narrationState = _narrationState.copyWith(
      currentSectionMode: _sectionModeForCurrentPosition(),
      discourseMode: _discourseModeForCurrentPosition(),
    );
    _offerCharacterAnalysis();
    _scheduleResumePersistence();
    _queueFollowerProgressUpdate(update);
  }

  @override
  void dispose() {
    characterAnalysis.dispose();
    unawaited(_planning.shutdown());
    unawaited(_exportPlanner?.shutdown());
    _disposed = true;
    ++_engineEpoch;
    ++_previewRevision;
    _publishEnginePhase(EngineSessionPhase.cancelled);
    final book = _audioBook;
    _audioBook = null;
    if (book != null) {
      book.current = false;
      unawaited(_ttsEngine.stop().then((_) => book.dispose()));
    }
    unawaited(_renderedScenes?.dispose());
    releasePreparedRange(_publicationSequence);
    ++_documentRevision;
    ++_watchSession;
    unawaited(_preparation.shutdown());
    _sleepTicker?.cancel();
    _fileOpenSubscription?.cancel();
    _shareSubscription?.cancel();
    _liveReadReloadDebounce?.cancel();
    _liveReadSubscription?.cancel();
    _resumePersistenceDebounce?.cancel();
    _followerProgressDebounce?.cancel();
    _ttsEngine.onStart = null;
    _ttsEngine.onStatus = null;
    if (_ttsEngine is TtsResourceProgressCapable) {
      (_ttsEngine as TtsResourceProgressCapable).onResourceProgress = null;
    }
    _ttsEngine.onProgress = null;
    _ttsEngine.onComplete = null;
    _ttsEngine.onError = null;
    _ttsEngine.onActivity = null;
    _ttsEngine.onDebugTrace = null;
    _ttsEngine.dispose();
    super.dispose();
  }

  void _rememberNarratorIntent() {
    if (!_runningEngineRetired && _selectedVoiceId != null) {
      _narratorVoiceIds[_narratorScope] = _selectedVoiceId!;
    }
  }

  Future<void> _persistPreferences() async {
    // Published book import may install narrator intent through the existing
    // document owner, so include that choice in the same scoped snapshot.
    _rememberNarratorIntent();
    _pendingPreferences = ReaderPreferences(
      voxtralQuantizationBits: _voxtralQuantizationBits,
      ttsEngineId: _selectedTtsEngineId,
      selectedVoiceId: _selectedVoiceId,
      narratorVoiceIds: Map.unmodifiable(_narratorVoiceIds),
      voiceSpeeds: Map.unmodifiable(_voiceSpeeds),
      fontFamily: _fontFamily,
      fontScale: _fontScale,
      appearanceMode: _appearanceMode,
      multiVoiceEnabled: _isMultiVoiceEnabled,
      storedDocumentCastVoiceAssignments: Map.unmodifiable({
        for (final entry in _storedDocumentCastVoiceAssignments.entries)
          entry.key: Map<String, String>.unmodifiable(entry.value),
      }),
      sourceVoiceDocumentIds: Map.unmodifiable(_sourceVoiceDocumentIds),
      characterSnapshot: _characters.snapshot(),
      resumeState: _resumeState,
      lastOpenedDocumentPath: _lastOpenedDocumentPath,
      lastOpenedDocumentAccessToken: _lastOpenedDocumentAccessToken,
      lastOpenedDirectoryPath: _lastOpenedDirectoryPath,
      lastOpenedDirectoryAccessToken: _lastOpenedDirectoryAccessToken,
    );
    ++_preferenceSnapshotRevision;
    await (_preferenceSavePump ??= _drainPreferenceSnapshots().whenComplete(() {
      _preferenceSavePump = null;
    }));
  }

  Future<void> _drainPreferenceSnapshots() async {
    while (_pendingPreferences != null) {
      final value = _pendingPreferences!;
      final revision = _preferenceSnapshotRevision;
      _pendingPreferences = null;
      try {
        await _preferencesService.save(
          voxtralQuantizationBits: value.voxtralQuantizationBits,
          ttsEngineId: value.ttsEngineId,
          selectedVoiceId: value.selectedVoiceId,
          narratorVoiceIds: value.narratorVoiceIds,
          voiceSpeeds: value.voiceSpeeds,
          fontFamily: value.fontFamily,
          fontScale: value.fontScale,
          appearanceMode: value.appearanceMode,
          multiVoiceEnabled: value.multiVoiceEnabled,
          storedDocumentCastVoiceAssignments:
              value.storedDocumentCastVoiceAssignments,
          sourceVoiceDocumentIds: value.sourceVoiceDocumentIds,
          characterSnapshot: value.characterSnapshot,
          resumeState: value.resumeState,
          lastOpenedDocumentPath: value.lastOpenedDocumentPath,
          lastOpenedDocumentAccessToken: value.lastOpenedDocumentAccessToken,
          lastOpenedDirectoryPath: value.lastOpenedDirectoryPath,
          lastOpenedDirectoryAccessToken: value.lastOpenedDirectoryAccessToken,
        );
      } catch (error) {
        if (!_disposed && revision == _preferenceSnapshotRevision) {
          _statusMessage = 'Could not save current preferences: $error';
          notifyListeners();
        }
      }
    }
  }

  void _scheduleResumePersistence() {
    _resumePersistenceDebounce?.cancel();
    _resumePersistenceDebounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_persistResumeStateNow()),
    );
  }

  Future<void> _flushResumePersistence() async {
    _resumePersistenceDebounce?.cancel();
    _resumePersistenceDebounce = null;
    await _persistResumeStateNow();
  }

  Future<void> _persistResumeStateNow() async {
    final currentPath = _currentDocumentPath;
    if (currentPath == null ||
        currentPath.trim().isEmpty ||
        _document.wordCount == 0) {
      return;
    }

    final clampedWordIndex = _currentWordIndex
        .clamp(0, math.max(_document.wordCount - 1, 0))
        .toInt();
    final segment = _document.segmentForWordIndex(clampedWordIndex);
    final segmentStartWordIndex = segment == null
        ? clampedWordIndex
        : _document.startWordIndexForSegment(segment);
    final wordIndexWithinSegment = math
        .max(0, clampedWordIndex - segmentStartWordIndex)
        .toInt();
    final anchorWordText = _document.wordSpans.isEmpty
        ? null
        : _document.speakableText.substring(
            _document.wordSpans[clampedWordIndex].start,
            _document.wordSpans[clampedWordIndex].end,
          );

    _resumeState = ReaderResumeState(
      documentPath: currentPath,
      wordIndex: clampedWordIndex,
      wordIndexWithinSegment: wordIndexWithinSegment,
      segmentTextAnchor: segment?.normalizedText,
      anchorWordText: anchorWordText,
    );
    await _persistPreferences();
  }

  void _restoreRememberedReadingPositionIfPossible(
    String documentPath, {
    bool surfaceSuccessMessage = false,
  }) {
    final resumeState = _resumeState;
    final normalizedPath = p.normalize(documentPath.trim());
    if (resumeState == null ||
        resumeState.documentPath != normalizedPath ||
        _document.wordCount == 0) {
      return;
    }

    final recoveredWordIndex = _recoverWordIndexFromResumeState(resumeState);
    if (recoveredWordIndex == null) {
      _currentWordIndex = 0;
      _focusReaderSurfaceOnWordIndex(0);
      final message =
          'Restored ${p.basename(normalizedPath)}, but the last heard position could not be recovered.';
      if (surfaceSuccessMessage) {
        _statusMessage = message;
      } else {
        _logDiagnostic(message);
      }
      notifyListeners();
      return;
    }

    _currentWordIndex = recoveredWordIndex;
    _focusReaderSurfaceOnWordIndex(recoveredWordIndex);
    if (surfaceSuccessMessage) {
      _statusMessage = recoveredWordIndex == 0 && resumeState.wordIndex > 0
          ? 'Restored ${p.basename(normalizedPath)}, but the last heard position could not be recovered.'
          : 'Restored ${p.basename(normalizedPath)} near your last heard position.';
    }
    notifyListeners();
  }

  void _focusReaderSurfaceOnWordIndex(int wordIndex) {
    final segment = _document.segmentForWordIndex(wordIndex);
    final blockId = segment?.blockId;
    _readingFocusState = _readingFocusState.copyWith(
      playbackActive: false,
      followMode: ReadingFocusFollowMode.following,
      activeDisplayBlockId: blockId,
      recenterRequestTick: _readingFocusState.recenterRequestTick + 1,
      clearActiveDisplayBlockId: blockId == null,
    );
  }

  int? _recoverWordIndexFromResumeState(ReaderResumeState resumeState) {
    final anchorText = resumeState.segmentTextAnchor?.trim();
    if (anchorText != null && anchorText.isNotEmpty) {
      for (final segment in _document.speechDocument.segments) {
        if (segment.normalizedText.trim() != anchorText) {
          continue;
        }
        final segmentStartWordIndex = _document.startWordIndexForSegment(
          segment,
        );
        return (segmentStartWordIndex + resumeState.wordIndexWithinSegment)
            .clamp(0, math.max(_document.wordCount - 1, 0))
            .toInt();
      }
    }

    if (resumeState.wordIndex < _document.wordCount) {
      return resumeState.wordIndex
          .clamp(0, math.max(_document.wordCount - 1, 0))
          .toInt();
    }

    return _document.wordCount > 0 ? _document.wordCount - 1 : null;
  }

  Future<void> _rememberOpenedDocumentPath(
    String? sourcePath, {
    required int revision,
    bool restoreTokenPrepared = false,
    String? preparedRestoreToken,
  }) async {
    _requireRevision(revision);
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return;
    }

    final normalizedPath = p.normalize(sourcePath.trim());
    final parent = p.dirname(normalizedPath);
    await _rememberOpenedDirectoryAccess(parent, revision: revision);
    _requireRevision(revision);

    final previousPath = _lastOpenedDocumentPath;
    final previousToken = _lastOpenedDocumentAccessToken;
    _lastOpenedDocumentPath = normalizedPath;
    try {
      final restoreToken = restoreTokenPrepared
          ? preparedRestoreToken
          : await _documentAccessService.createPersistentRestoreToken(
              normalizedPath,
            );
      _requireRevision(revision);
      if (restoreToken != null && restoreToken.trim().isNotEmpty) {
        _lastOpenedDocumentAccessToken = restoreToken;
        _logRestoreDiagnostic(
          'Persisted restore access for the opened document.',
          context: <String, Object?>{'path': normalizedPath},
        );
      } else if (previousPath != normalizedPath) {
        _lastOpenedDocumentAccessToken = null;
        _logRestoreDiagnostic(
          'Opened document path was remembered without a restore token.',
          context: <String, Object?>{'path': normalizedPath},
        );
      } else {
        _lastOpenedDocumentAccessToken = previousToken;
        _logRestoreDiagnostic(
          'Retained the previous restore token for the remembered document.',
          context: <String, Object?>{'path': normalizedPath},
        );
      }
    } catch (error) {
      _requireRevision(revision);
      _lastOpenedDocumentAccessToken = previousPath == normalizedPath
          ? previousToken
          : null;
      _logRestoreDiagnostic(
        'Could not persist startup-restore access for the opened document.',
        context: <String, Object?>{'path': normalizedPath},
        error: error,
      );
    }
    if (parent.isNotEmpty && parent != '.') {
      _lastOpenedDirectoryPath = parent;
    }
    await _persistPreferences();
  }

  Future<void> _rememberOpenedDirectoryAccess(
    String directoryPath, {
    required int revision,
  }) async {
    _requireRevision(revision);
    final normalizedDirectoryPath = p.normalize(directoryPath.trim());
    if (normalizedDirectoryPath.isEmpty || normalizedDirectoryPath == '.') {
      return;
    }

    final previousDirectoryPath = _lastOpenedDirectoryPath;
    final previousDirectoryToken = _lastOpenedDirectoryAccessToken;
    _lastOpenedDirectoryPath = normalizedDirectoryPath;

    if (previousDirectoryPath == normalizedDirectoryPath &&
        previousDirectoryToken != null &&
        previousDirectoryToken.trim().isNotEmpty) {
      return;
    }

    DocumentAccessLease? lease;
    try {
      final restoreToken = await _documentAccessService
          .createPersistentRestoreToken(normalizedDirectoryPath);
      _requireRevision(revision);
      if (restoreToken != null && restoreToken.trim().isNotEmpty) {
        _lastOpenedDirectoryAccessToken = restoreToken;
        _logRestoreDiagnostic(
          'Persisted directory access for the opened document folder without prompting.',
          context: <String, Object?>{'directoryPath': normalizedDirectoryPath},
        );
        await _persistPreferences();
        return;
      }

      lease = await _documentAccessService.requestPersistentDirectoryAccess(
        normalizedDirectoryPath,
      );
      _requireRevision(revision);
      if (lease != null) {
        _lastOpenedDirectoryPath = p.normalize(lease.path.trim());
        _lastOpenedDirectoryAccessToken =
            lease.refreshedToken ?? previousDirectoryToken;
        _logRestoreDiagnostic(
          'Persisted directory access for the opened document folder.',
          context: <String, Object?>{'directoryPath': _lastOpenedDirectoryPath},
        );
      } else if (previousDirectoryPath == normalizedDirectoryPath) {
        _lastOpenedDirectoryAccessToken = previousDirectoryToken;
        _logRestoreDiagnostic(
          'Directory access prompt was dismissed; retaining the previous directory token.',
          context: <String, Object?>{'directoryPath': normalizedDirectoryPath},
        );
      } else {
        _lastOpenedDirectoryAccessToken = null;
        _logRestoreDiagnostic(
          'Directory access was not granted for the newly opened document folder.',
          context: <String, Object?>{'directoryPath': normalizedDirectoryPath},
        );
      }
    } catch (error) {
      _requireRevision(revision);
      _lastOpenedDirectoryAccessToken =
          previousDirectoryPath == normalizedDirectoryPath
          ? previousDirectoryToken
          : null;
      _logRestoreDiagnostic(
        'Could not persist directory access for the opened document folder.',
        context: <String, Object?>{'directoryPath': normalizedDirectoryPath},
        error: error,
      );
    } finally {
      await lease?.close();
    }
  }

  Future<void> _startLiveReadWatch(String normalizedPath, int session) async {
    if (_disposed || session != _watchSession) return;
    final parentPath = p.dirname(normalizedPath);
    if (parentPath.isEmpty || parentPath == '.') {
      return;
    }

    final directory = Directory(parentPath);
    final targetBaseName = p.basename(normalizedPath);
    _liveReadSubscription = directory.watch().listen((event) {
      if (_disposed || session != _watchSession) return;
      final eventPath = p.normalize(event.path);
      final eventBaseName = p.basename(eventPath);
      if (eventPath != normalizedPath && eventBaseName != targetBaseName) {
        return;
      }
      _liveReadReloadDebounce?.cancel();
      _liveReadReloadDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!_disposed && session == _watchSession) {
          unawaited(_reloadLiveReadFile(initialLoad: false));
        }
      });
    });
  }

  Future<void> _cancelLiveReadWatch() async {
    _liveReadReloadDebounce?.cancel();
    _liveReadReloadDebounce = null;
    final subscription = _liveReadSubscription;
    _liveReadSubscription = null;
    await subscription?.cancel();
  }

  Future<void> _reloadLiveReadFile({
    required bool initialLoad,
    int? revision,
  }) async {
    final sourcePath = _liveReadFilePath;
    if (_disposed || sourcePath == null || sourcePath.trim().isEmpty) return;
    final session = _watchSession;
    final resume =
        !initialLoad && (_isPlaying || _playbackActivity.isBuffering);
    await _runImportOperation(
      (revision) async {
        await _flushResumePersistence();
        _requireRevision(revision);
        final imported = await _prepare(
          revision,
          DocumentPreparationKind.bytes,
          fileName: p.basename(sourcePath),
          sourcePath: sourcePath,
          acquireBytes: () => _readBytesWithAccessRecovery(
            sourceLabel: 'live read file',
            sourcePath: sourcePath,
            readBytes: File(sourcePath).readAsBytes,
            revision: revision,
          ),
        );
        if (session != _watchSession) throw const _SupersededPreparation();
        await _replaceDocument(
          imported,
          revision: revision,
          sourcePath: sourcePath,
          statusMessage:
              'Live read ${initialLoad ? 'connected to' : 'updated'} ${p.basename(sourcePath)}.',
        );
        _requireRevision(revision);
        if (!initialLoad) {
          _restoreRememberedReadingPositionIfPossible(
            sourcePath,
            surfaceSuccessMessage: false,
          );
        }
        // A user pause during refresh must not be reversed by old intent.
        if (resume && _resumeAfterPreparation) {
          _isImporting = false;
          await startPlayback();
        }
      },
      revision: revision,
      errorSourceLabel: 'live read file',
    );
  }

  Future<Uint8List> _readBytesWithAccessRecovery({
    required String sourceLabel,
    required String? sourcePath,
    required Future<Uint8List> Function() readBytes,
    required int revision,
  }) async {
    final normalizedPath = (sourcePath == null || sourcePath.trim().isEmpty)
        ? null
        : p.normalize(sourcePath.trim());

    try {
      return await readBytes();
    } catch (error) {
      _requireRevision(revision);
      if (!_looksLikePermissionIssue(error) || normalizedPath == null) {
        rethrow;
      }

      final lease = await _requestDirectoryAccessAfterReadFailure(
        sourceLabel: sourceLabel,
        sourcePath: normalizedPath,
        initialError: error,
        revision: revision,
      );
      if (lease == null) {
        rethrow;
      }

      try {
        _requireRevision(revision);
        return await readBytes();
      } finally {
        await lease.close();
      }
    }
  }

  Future<DocumentAccessLease?> _requestDirectoryAccessAfterReadFailure({
    required String sourceLabel,
    required String sourcePath,
    required Object initialError,
    required int revision,
  }) async {
    final directoryPath = p.normalize(p.dirname(sourcePath));
    if (directoryPath.isEmpty || directoryPath == '.') {
      return null;
    }

    _logDiagnostic(
      '[access-recovery] Read failed; requesting directory access and retrying. | sourceLabel=$sourceLabel, sourcePath=$sourcePath, directoryPath=$directoryPath',
      error: initialError,
    );

    try {
      final lease = await _documentAccessService
          .requestPersistentDirectoryAccess(directoryPath);
      if (_disposed || revision != _documentRevision) {
        await lease?.close();
        throw const _SupersededPreparation();
      }
      if (lease == null) {
        _logDiagnostic(
          '[access-recovery] Directory access prompt was dismissed. | sourcePath=$sourcePath, directoryPath=$directoryPath',
        );
        return null;
      }

      _lastOpenedDirectoryPath = p.normalize(lease.path.trim());
      _lastOpenedDirectoryAccessToken =
          lease.refreshedToken ?? _lastOpenedDirectoryAccessToken;
      await _persistPreferences();
      _logDiagnostic(
        '[access-recovery] Directory access granted; retrying read. | sourcePath=$sourcePath, directoryPath=$_lastOpenedDirectoryPath',
      );
      return lease;
    } catch (error) {
      _logDiagnostic(
        '[access-recovery] Directory access request failed. | sourcePath=$sourcePath, directoryPath=$directoryPath',
        error: error,
      );
      return null;
    }
  }

  bool _resumeAfterPreparation = true;

  Future<void> _runImportOperation(
    Future<void> Function(int) operation, {
    int? revision,
    String? errorSourceLabel,
    bool surfaceErrors = true,
  }) async {
    // Explicit user intake may arrive while startup is still loading settings.
    // It waits only for settings, never model/voice initialization, so delayed
    // preferences cannot overwrite newly imported session/assignment state.
    if (_initializationStarted && !_preferencesReady.isCompleted) {
      await _preferencesReady.future;
    }
    final current = revision ?? _beginDocumentRequest();
    if (_disposed || current != _documentRevision) return;
    _isImporting = true;
    _statusMessage = null;
    _documentLoadStageLabel = 'Preparing document, cast and dialogue...';
    _documentLoadStageProgress = null;
    notifyListeners();
    try {
      await operation(current);
    } on _SupersededPreparation {
      // All stale terminal paths, including cleanup, belong to their revision.
    } catch (error) {
      if (!_disposed && current == _documentRevision) {
        _pendingPlayUntilReady = false;
        final message = errorSourceLabel == null
            ? '$error'
            : _describeImportError(sourceLabel: errorSourceLabel, error: error);
        if (surfaceErrors) {
          _statusMessage = message;
        } else {
          _logDiagnostic(message, error: error);
        }
      }
    } finally {
      if (!_disposed && current == _documentRevision) {
        _isImporting = false;
        if (_preparedDocumentRevision != current) {
          // Failed/cancelled intake leaves the previous range usable, but does
          // not redirect pending Play to the previous document unexpectedly.
          _documentPrepared = true;
          _pendingPlayUntilReady = false;
        }

        if (_preparationComplete) _clearDocumentLoadStage();
        notifyListeners();
        _resumePendingPlay();
      }
    }
  }

  /// Call before disposal when a caller needs proof that preparation drained.
  Future<void> shutdownPreparation() async {
    _preparationClosed = true;
    _beginDocumentRequest();
    _isImporting = false;
    _clearDocumentLoadStage();
    if (!_disposed) notifyListeners();
    ++_watchSession;
    await _cancelLiveReadWatch();
    await _preparation.shutdown();
    await characterAnalysis.shutdown();
    await _sourceRevisionWork;
    await _documentExportWork;
    await _audioBookRetirement;
    await _renderedScenes?.cancelAndDrain();
  }

  void _clearDocumentLoadStage() {
    _documentLoadStageLabel = null;
    _documentLoadStageProgress = null;
  }

  void _logDiagnostic(String message, {Object? error}) {
    developer.log(message, name: 'read_aloud.reader', error: error);
  }

  void _logRestoreDiagnostic(
    String message, {
    Map<String, Object?> context = const <String, Object?>{},
    Object? error,
  }) {
    final details = context.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    final formattedMessage = details.isEmpty
        ? '[startup-restore] $message'
        : '[startup-restore] $message | $details';
    _logDiagnostic(formattedMessage, error: error);
  }

  String? _sectionModeForCurrentPosition() {
    final segment = _document.segmentForWordIndex(_currentWordIndex);
    if (segment == null) {
      return null;
    }
    final block = _blockForSegment(segment);
    return switch (block?.kind) {
      DisplayBlockKind.heading => 'heading',
      DisplayBlockKind.listItem => 'list',
      DisplayBlockKind.blockquote => 'aside',
      DisplayBlockKind.image => 'caption',
      _ => 'prose',
    };
  }

  String? _discourseModeForCurrentPosition() {
    final segment = _document.segmentForWordIndex(_currentWordIndex);
    if (segment == null) {
      return null;
    }
    final roles = _document.baseSpeechAnnotations
        .forSegment(segment.segmentId)
        .where((annotation) => annotation.discourseRole != null)
        .toList(growable: false);
    if (roles.isNotEmpty) {
      return roles.last.discourseRole;
    }
    return null;
  }

  DisplayBlock? _blockForSegment(SpeechSegment segment) {
    for (final block in _document.displayDocument.blocks) {
      if (block.blockId == segment.blockId) {
        return block;
      }
    }
    return null;
  }

  String? _boundaryClassForCurrentPosition() {
    final segment = _document.segmentForWordIndex(_currentWordIndex);
    if (segment == null) {
      return null;
    }
    final candidates = _document.baseSpeechAnnotations
        .forSegment(segment.segmentId)
        .where((annotation) => annotation.breakClass != null)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.last.breakClass!.name;
  }

  SpeechPlanningContext? _planningContext({
    bool fromStart = false,
    ReaderDocument? document,
    String? voiceId,
    double? rate,
    Map<String, String>? overrides,
    Map<String, String>? stored,
    bool? multiVoice,
  }) {
    document ??= _document;
    voiceId ??= _selectedVoiceId;
    final start = fromStart
        ? document.speechDocument.segments.firstOrNull
        : document.segmentForWordIndex(_currentWordIndex);
    if (voiceId == null || start == null) return null;
    final profile = _selectedPronunciationProfile(voiceId: voiceId);
    final assignments =
        (multiVoice ?? _isMultiVoiceEnabled) && _voices.isNotEmpty
        ? _characters.resolve(
            workId: _voicePreferenceDocumentId,
            engineId: _runningTtsEngineId,
            voices: _voices,
            narratorVoiceId: voiceId,
            evidence: _castingRegistryFor(document),
            editedCastIds: overrides?.keys.toSet() ?? _editedCastIds,
            capturedChoices: overrides == null && stored == null
                ? null
                : {...?stored, ...?overrides},
          )
        : null;
    return SpeechPlanningContext(
      realization: VoiceSessionRealizationInput(
        speechDocument: document.speechDocument,
        baseAnnotations: document.baseSpeechAnnotations,
        basePronunciationArtifacts: document.basePronunciationArtifacts,
        startSegmentId: start.segmentId,
        voiceId: voiceId,
        engineId: _engineId(),
        rate: rate ?? currentSpeed,
        narrationState: _narrationState,
        selectedProfile: profile,
        mergedPronunciationResources: _mergedPronunciationResources(profile),
      ),
      engineVersion: _engineVersion(),
      routes: assignments == null
          ? null
          : CastAwareSpeechRouteInput(
              documentVoiceAttribution: refineCharacterRoutes(
                document.documentVoiceAttribution,
                _futureCharacterRoutes.values.expand((refs) => refs),
              ),
              castVoiceAssignments: assignments,
            ),
    );
  }

  Future<void> _primePlaybackPreparation() async {
    final context = _planningContext();
    if (context == null) {
      _currentRealization = null;
      _currentChunkPlan = null;
      return;
    }
    final revision = _documentRevision;
    final intent = _resourceBindingIntent;
    final ticket = beginReadingStage(
      PreparationStage.planning,
      producerId: 'speech-planning-worker',
      scope: 'Current playback window',
    );
    publishReadingStage(
      ticket,
      const PreparationProgress(
        stage: PreparationStage.planning,
        state: PreparationWorkState.working,
        completed: 0,
        unit: 'chunks',
      ),
    );
    try {
      final window = await _planning.plan(context, maxChunks: 3);
      if (_disposed ||
          revision != _documentRevision ||
          intent != _resourceBindingIntent) {
        return;
      }
      _currentPlanningContext = context;
      _currentRealization = window.realization;
      _currentChunkPlan = window.plan;
      publishReadingStage(
        ticket,
        PreparationProgress(
          stage: PreparationStage.planning,
          state: PreparationWorkState.complete,
          completed: window.plan.chunks.length,
          total: window.plan.chunks.length,
          unit: 'chunks',
        ),
      );
    } on PlanningCancelled {
      publishReadingStage(
        ticket,
        const PreparationProgress(
          stage: PreparationStage.planning,
          state: PreparationWorkState.cancelled,
          completed: 0,
          unit: 'chunks',
        ),
      );
      return;
    } catch (error) {
      publishReadingStage(
        ticket,
        PreparationProgress(
          stage: PreparationStage.planning,
          state: PreparationWorkState.failed,
          completed: 0,
          unit: 'chunks',
          error: '$error',
        ),
      );
      rethrow;
    }
  }

  String _engineId() {
    final identity = _ttsEngine;
    if (identity is TtsEngineIdentityCapable) {
      return (identity as TtsEngineIdentityCapable).engineId;
    }
    final runtime = _ttsEngine.runtimeType.toString().toLowerCase();
    return runtime.contains('kokoro') ? 'kokoro' : 'generic';
  }

  String _engineVersion() {
    final identity = _ttsEngine;
    if (identity is TtsEngineIdentityCapable) {
      return (identity as TtsEngineIdentityCapable).engineVersion;
    }
    return _engineId() == 'kokoro' ? '2' : '1';
  }

  EnglishPronunciationProfile _selectedPronunciationProfile({String? voiceId}) {
    final effectiveVoiceId = voiceId ?? _selectedVoiceId;
    final voiceLocale = effectiveVoiceId == null
        ? null
        : _voices
              .where((voice) => voice.id == effectiveVoiceId)
              .map((voice) => voice.locale)
              .firstOrNull;
    return _pronunciationProfileSelector.select(
      EnglishPronunciationProfileSelectionInput(
        engineId: _engineId(),
        voiceId: effectiveVoiceId,
        voiceLocaleTag: voiceLocale,
      ),
    );
  }

  MergedPronunciationResources _mergedPronunciationResources(
    EnglishPronunciationProfile profile,
  ) {
    return _pronunciationResourceLayeringService.merge(
      PronunciationResourceLayeringInput(profile: profile),
    );
  }

  Future<TtsExportRequest> _buildExportRequest(
    String outputPath, {
    required ReaderDocument document,
  }) async {
    final revision = _documentRevision;
    final intent = _resourceBindingIntent;
    final bindings = resourceBindings;
    final context = _planningContext(fromStart: true, document: document);
    final planner = SpeechPlanningSupervisor();
    _exportPlanner = planner;
    try {
      final window = context == null ? null : await planner.plan(context);
      _requireRevision(revision);
      if (intent != _resourceBindingIntent) throw const PlanningCancelled();
      return TtsExportRequest(
        text: document.speakableText,
        outputPath: outputPath,
        documentId: document.displayDocument.documentId,
        documentTitle: document.title,
        sourceDescription: document.sourceDescription,
        sessionId: 'export_${DateTime.now().microsecondsSinceEpoch}',
        normalizationVersion: document.speechDocument.normalizationVersion,
        chunkPlan: window?.plan,
        speechDocument: document.speechDocument,
        ttsArtifactSet: window?.realization.ttsArtifactSet,
        planningContext: context,
        preparedResources: _ttsEngine is ResourcePreparationCapable
            ? bindings
            : null,
      );
    } finally {
      if (identical(_exportPlanner, planner)) _exportPlanner = null;
      await planner.shutdown();
    }
  }

  CastVoiceAssignmentSet? _resolveCastVoiceAssignments({
    required String preferredNarratorVoiceId,
    ReaderDocument? document,
  }) {
    if (!_isMultiVoiceEnabled || _voices.isEmpty) {
      return null;
    }

    return _characters.resolve(
      workId: _voicePreferenceDocumentId,
      engineId: _runningTtsEngineId,
      voices: _voices,
      narratorVoiceId: preferredNarratorVoiceId,
      editedCastIds: _editedCastIds,
      evidence: document == null
          ? characterCastRegistry
          : _castingRegistryFor(document),
    );
  }

  Map<String, String> _currentStoredCastVoiceAssignments() {
    return Map<String, String>.unmodifiable(
      _storedDocumentCastVoiceAssignments[_voicePreferenceDocumentId] ??
          const <String, String>{},
    );
  }

  void _mergeDiscoveredCast(
    CharacterCastRegistry registry, {
    ReaderDocument? document,
  }) {
    final key = _voicePreferenceDocumentId;
    if (_activeSourceRevision case final source?) {
      _sourceVoiceDocumentIds.putIfAbsent(source, () => key);
    }
    final analysisKey =
        '$_documentRevision:${_characters.workId(key)}:$_characterSourceRevision';
    if (_characterAnalysisKey != analysisKey) {
      _characterAnalysisKey = analysisKey;
      _characters.begin(
        workId: key,
        sourceRevision: _characterSourceRevision,
        analysisRevision: _documentRevision,
      );
    }
    const adapter = CharacterAnalysisAdapter();
    final delta = document == null
        ? adapter.discovery(
            workId: key,
            sourceRevision: _characterSourceRevision,
            analysisRevision: _documentRevision,
            sequence: ++_characterDeltaSequence,
            registry: registry,
          )
        : adapter.refined(
            workId: key,
            sourceRevision: _characterSourceRevision,
            analysisRevision: _documentRevision,
            sequence: ++_characterDeltaSequence,
            document: document,
          );
    _characters.apply(delta);
    _refreshCharacterProjection();
    _castRedirects
      ..clear()
      ..addAll(_characters.redirects(key));
  }

  CharacterCastRegistry _castingRegistryFor(ReaderDocument document) {
    if (_discoveredCast.isEmpty) return document.characterCastRegistry;
    return CharacterCastRegistry(
      documentId: document.characterCastRegistry.documentId,
      registryVersion: document.characterCastRegistry.registryVersion,
      entries:
          {
                for (final entry in document.characterCastRegistry.entries)
                  entry.castId: entry,
                ..._discoveredCast,
              }.values
              .where((entry) => !_castRedirects.containsKey(entry.castId))
              .toList(),
      castIdRedirects: {
        ...document.characterCastRegistry.castIdRedirects,
        ..._castRedirects,
      },
    );
  }

  String get _voicePreferenceDocumentId =>
      _sourceVoiceDocumentIds[_activeSourceRevision] ?? sessionDocumentId;

  void _storeCastVoiceAssignment(String castId, String voiceId) {
    final key = _voicePreferenceDocumentId;
    if (_activeSourceRevision case final source?) {
      _sourceVoiceDocumentIds[source] = key;
    }
    _characters.select(key, castId, voiceId);
    _refreshCharacterProjection();
  }

  void _clearStoredCastVoiceAssignment(String castId) {
    _characters.select(_voicePreferenceDocumentId, castId, null);
    _refreshCharacterProjection();
  }

  void _refreshCharacterProjection() {
    _discoveredCast
      ..clear()
      ..addEntries(
        _characters
            .entries(_voicePreferenceDocumentId)
            .map((e) => MapEntry(e.castId, e)),
      );
  }

  void _recordFirstAudioLatency() {
    final startedAt = _playbackRequestedAt;
    final sessionId = _narrationState.sessionId;
    final voiceId = _selectedVoiceId;
    if (startedAt == null ||
        voiceId == null ||
        !_latencyRecordedSessions.add(sessionId)) {
      _playbackRequestedAt = null;
      return;
    }

    _recordMetric(
      metric: 'firstAudioLatencyMs',
      value: DateTime.now().difference(startedAt).inMilliseconds,
    );
    _playbackRequestedAt = null;
  }

  void _recordPositionMapConfidenceIfNeeded() {
    final sessionId = _narrationState.sessionId;
    if (!_positionConfidenceRecordedSessions.add(sessionId)) {
      return;
    }

    final entries = _document.positionMap.entries;
    if (entries.isEmpty) {
      _recordMetric(
        metric: 'positionMapConfidence',
        value: <String, Object?>{
          'averageConfidence': 0.0,
          'minimumConfidence': 0.0,
          'entryCount': 0,
          'lowConfidenceEntryCount': 0,
          'documentType': _document.type.name,
        },
      );
      return;
    }

    var confidenceTotal = 0.0;
    var minimumConfidence = 1.0;
    var lowConfidenceCount = 0;
    for (final entry in entries) {
      confidenceTotal += entry.confidence;
      if (entry.confidence < minimumConfidence) {
        minimumConfidence = entry.confidence;
      }
      if (entry.confidence < 0.7) {
        lowConfidenceCount += 1;
      }
    }

    _recordMetric(
      metric: 'positionMapConfidence',
      value: <String, Object?>{
        'averageConfidence': confidenceTotal / entries.length,
        'minimumConfidence': minimumConfidence,
        'entryCount': entries.length,
        'lowConfidenceEntryCount': lowConfidenceCount,
        'documentType': _document.type.name,
      },
    );
  }

  void _recordMetric({required String metric, Object? value, String? chunkId}) {
    final voiceId = _selectedVoiceId;
    if (voiceId == null) {
      return;
    }

    _instrumentation.recordMetric(
      metric: metric,
      documentId: _document.displayDocument.documentId,
      sessionId: _narrationState.sessionId,
      voiceId: voiceId,
      engineId: _engineId(),
      chunkId: chunkId,
      value: value,
    );
  }

  void _recordProgress(TtsProgressUpdate update) {
    final chunkId = update.chunkId;
    final documentId = update.documentId;
    final wordStartIndex = update.wordStartIndex;
    final wordEndIndex = update.wordEndIndex;
    final chunkAudioDuration = update.chunkAudioDuration;
    final voiceId = update.voiceId;
    final rate = update.rate;
    if (chunkId == null ||
        documentId == null ||
        wordStartIndex == null ||
        wordEndIndex == null ||
        voiceId == null ||
        rate == null) {
      return;
    }

    if (_activeSpokenChunkId != null && _activeSpokenChunkId != chunkId) {
      _finalizeSpokenChunk(_activeSpokenChunkId!);
    }

    final existing = _spokenChunkRecords[chunkId];
    _spokenChunkRecords[chunkId] = SpokenChunkRecord(
      sceneTurns: update.sceneTurns,
      chunkId: chunkId,
      documentId: documentId,
      segmentIds:
          existing?.segmentIds ??
          <String>[if (update.segmentId != null) update.segmentId!],
      startWordIndex: existing?.startWordIndex ?? wordStartIndex,
      endWordIndex: math.max(
        existing?.endWordIndex ?? wordEndIndex,
        wordEndIndex,
      ),
      wordCount:
          (math.max(existing?.endWordIndex ?? wordEndIndex, wordEndIndex) -
                  (existing?.startWordIndex ?? wordStartIndex))
              .clamp(1, _document.wordCount),
      // Early packets establish source ownership before a scene duration is
      // known. Zero on an incomplete record is unknown, not measured silence;
      // replace it with the real total once final publication supplies it.
      audioDuration:
          chunkAudioDuration ?? existing?.audioDuration ?? Duration.zero,
      playbackOffset: update.elapsedInChunk ?? Duration.zero,
      voiceId: voiceId,
      rate: rate,
      completed: false,
      routeId: update.routeId,
      castId: update.castId,
      dialogueSpanId: update.dialogueSpanId,
    );
    _activeSpokenChunkId = chunkId;
    _wordsPerSecond = _estimateWordsPerSecond(voiceId: voiceId, rate: rate);
  }

  void _queueFollowerProgressUpdate(TtsProgressUpdate update) {
    _pendingFollowerProgressUpdate = update;
    final policy = _currentFollowerSyncPolicy();

    if (_shouldFlushFollowerProgressImmediately(update, policy)) {
      _flushPendingFollowerProgress();
      return;
    }

    final lastAppliedAt = _lastFollowerProgressAppliedAt;
    if (lastAppliedAt == null) {
      _flushPendingFollowerProgress();
      return;
    }

    final elapsedSinceLastApply = DateTime.now().difference(lastAppliedAt);
    final remainingDelay = policy.flushInterval - elapsedSinceLastApply;
    if (!remainingDelay.isNegative && remainingDelay > Duration.zero) {
      _followerProgressDebounce?.cancel();
      _followerProgressDebounce = Timer(
        remainingDelay,
        _flushPendingFollowerProgress,
      );
      return;
    }

    _flushPendingFollowerProgress();
  }

  bool _shouldFlushFollowerProgressImmediately(
    TtsProgressUpdate update,
    _FollowerSyncPolicy policy,
  ) {
    if (!_spokenSelection.hasSelection) {
      return true;
    }

    final pendingWordEndIndex = _resolvedProgressWordEndIndex(update);
    final visibleWordEndIndex = _spokenSelection.speechEndWordIndex ?? 0;
    final wordDrift = pendingWordEndIndex - visibleWordEndIndex;

    if (wordDrift >= _followerHardResyncWordDelta) {
      return true;
    }

    if (update.segmentId != null &&
        update.segmentId != _spokenSelection.segmentId) {
      return true;
    }

    if (update.routeId != _spokenSelection.routeId ||
        update.castId != _spokenSelection.castId ||
        update.dialogueSpanId != _spokenSelection.dialogueSpanId) {
      return true;
    }

    final lastAppliedAt = _lastFollowerProgressAppliedAt;
    if (lastAppliedAt == null) {
      return true;
    }

    final elapsedSinceLastApply = DateTime.now().difference(lastAppliedAt);
    return wordDrift >= policy.softWordDelta &&
        elapsedSinceLastApply >= policy.flushInterval;
  }

  void _flushPendingFollowerProgress() {
    _followerProgressDebounce?.cancel();
    _followerProgressDebounce = null;

    final update = _pendingFollowerProgressUpdate;
    if (update == null) {
      return;
    }
    _pendingFollowerProgressUpdate = null;
    _applyFollowerProgressUpdate(update);
  }

  void _applyFollowerProgressUpdate(TtsProgressUpdate update) {
    final nextSelection = _spokenSelectionMapperService.map(
      SpokenSelectionMapperInput(
        displayDocument: _document.displayDocument,
        speechDocument: _document.speechDocument,
        positionMap: _document.positionMap,
        progress: update,
      ),
    );
    final nextReadingFocusState = _readingFocusState.copyWith(
      playbackActive: true,
      activeDisplayBlockId: nextSelection.displayBlockId,
      clearActiveDisplayBlockId: nextSelection.displayBlockId == null,
    );

    final selectionChanged = !_sameSpokenSelection(
      _spokenSelection,
      nextSelection,
    );
    final readingFocusChanged = !_sameReadingFocusState(
      _readingFocusState,
      nextReadingFocusState,
    );

    _spokenSelection = nextSelection;
    _readingFocusState = nextReadingFocusState;
    _lastFollowerProgressAppliedAt = DateTime.now();

    if (selectionChanged || readingFocusChanged) {
      notifyListeners();
    }
  }

  void _resetFollowerProgressSynchronization() {
    _pendingFollowerProgressUpdate = null;
    _lastFollowerProgressAppliedAt = null;
    _followerProgressDebounce?.cancel();
    _followerProgressDebounce = null;
  }

  _FollowerSyncPolicy _currentFollowerSyncPolicy() {
    switch (_playbackActivity.bufferPressure) {
      case TtsBufferPressure.critical:
        return const _FollowerSyncPolicy(
          flushInterval: _criticalFollowerUpdateInterval,
          softWordDelta: _criticalFollowerSoftWordDelta,
        );
      case TtsBufferPressure.lowWater:
        return const _FollowerSyncPolicy(
          flushInterval: _lowWaterFollowerUpdateInterval,
          softWordDelta: _lowWaterFollowerSoftWordDelta,
        );
      case TtsBufferPressure.none:
      case TtsBufferPressure.healthy:
        return const _FollowerSyncPolicy(
          flushInterval: _healthyFollowerUpdateInterval,
          softWordDelta: _healthyFollowerSoftWordDelta,
        );
    }
  }

  int _resolvedProgressWordEndIndex(TtsProgressUpdate update) {
    return update.wordEndIndex ??
        _document.wordIndexForOffset(_utteranceStartOffset + update.endOffset);
  }

  bool _sameSpokenSelection(SpokenSelection left, SpokenSelection right) {
    return left.precision == right.precision &&
        left.confidence == right.confidence &&
        left.segmentId == right.segmentId &&
        left.displayBlockId == right.displayBlockId &&
        left.displayStart == right.displayStart &&
        left.displayEnd == right.displayEnd &&
        left.speechStartWordIndex == right.speechStartWordIndex &&
        left.speechEndWordIndex == right.speechEndWordIndex &&
        left.voiceId == right.voiceId &&
        left.routeId == right.routeId &&
        left.castId == right.castId &&
        left.dialogueSpanId == right.dialogueSpanId;
  }

  bool _sameReadingFocusState(ReadingFocusState left, ReadingFocusState right) {
    return left.playbackActive == right.playbackActive &&
        left.followMode == right.followMode &&
        left.activeDisplayBlockId == right.activeDisplayBlockId &&
        left.recenterRequestTick == right.recenterRequestTick;
  }

  void _finalizeActiveSpokenChunk() {
    final chunkId = _activeSpokenChunkId;
    if (chunkId == null) {
      return;
    }
    _finalizeSpokenChunk(chunkId);
    _activeSpokenChunkId = null;
  }

  void _finalizeSpokenChunk(String chunkId) {
    final existing = _spokenChunkRecords[chunkId];
    if (existing == null || existing.completed) {
      return;
    }
    _spokenChunkRecords[chunkId] = existing.copyWith(
      playbackOffset: existing.audioDuration,
      completed: true,
    );
    _wordsPerSecond = _estimateWordsPerSecond(
      voiceId: existing.voiceId,
      rate: existing.rate,
    );
  }

  double _estimateWordsPerSecond({
    required String voiceId,
    required double rate,
  }) {
    final matching = _spokenChunkRecords.values
        .where(
          (record) =>
              record.completed &&
              record.sceneTurns.map((t) => t.voiceId).toSet().length <= 1 &&
              record.voiceId == voiceId &&
              (record.rate - rate).abs() < 0.001 &&
              record.audioDuration.inMilliseconds > 0 &&
              record.wordCount > 0,
        )
        .toList(growable: false);
    if (matching.isEmpty) {
      return 2.8;
    }

    final recent = matching.length <= 5
        ? matching
        : matching.sublist(matching.length - 5);
    var weightedWordsPerSecond = 0.0;
    var weightTotal = 0.0;
    for (var index = 0; index < recent.length; index += 1) {
      final record = recent[index];
      final wordsPerSecond =
          record.wordCount / (record.audioDuration.inMilliseconds / 1000);
      final weight = (index + 1).toDouble();
      weightedWordsPerSecond += wordsPerSecond * weight;
      weightTotal += weight;
    }

    return weightedWordsPerSecond / weightTotal;
  }

  int _snapWordIndexToSegmentStart(int targetWordIndex) {
    final segment = _document.segmentForWordIndex(targetWordIndex);
    if (segment == null) {
      return targetWordIndex;
    }
    return _document.startWordIndexForSegment(segment);
  }
}

String _fallbackFileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (!normalized.contains('/')) {
    return normalized;
  }
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _defaultAudioExportFileName(String title, String? voiceId) {
  final trimmed = title.trim().isEmpty ? 'Read Aloud Export' : title.trim();
  final withoutExtension = trimmed.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final sanitized = withoutExtension.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
  final voiceSuffix = (voiceId == null || voiceId.trim().isEmpty)
      ? ''
      : ' - ${voiceId.trim()}';
  return '$sanitized$voiceSuffix.wav';
}

String _describeImportError({
  required String sourceLabel,
  required Object error,
}) {
  if (error is DocumentImportException) {
    return 'Failed to import $sourceLabel content: ${error.message}';
  }

  if (_looksLikePermissionIssue(error)) {
    return switch (sourceLabel) {
      'Opened' =>
        'Read Aloud could not access the opened file. Use Open and choose it again so the platform can grant access on demand.',
      'Dropped' =>
        'Read Aloud could not access the dropped file. Use Open and choose it again so the platform can grant access on demand.',
      'Shared' =>
        'Read Aloud could not access the shared file yet. Share it again and grant access when prompted.',
      _ =>
        'Read Aloud could not access that file yet. Try again and grant access when prompted.',
    };
  }

  return 'Failed to import $sourceLabel content: $error';
}

bool _looksLikePermissionIssue(Object error) {
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final message = '${error.message ?? ''} ${error.details ?? ''}'
        .toLowerCase();
    if (code.contains('permission') ||
        code.contains('denied') ||
        code.contains('access') ||
        message.contains('permission') ||
        message.contains('not permitted') ||
        message.contains('permission denied') ||
        message.contains('access denied') ||
        message.contains('sandbox') ||
        message.contains('security')) {
      return true;
    }
  }

  final text = error.toString().toLowerCase();
  return text.contains('permission denied') ||
      text.contains('operation not permitted') ||
      text.contains('access denied') ||
      text.contains('sandbox') ||
      text.contains('security-scoped');
}

class _FollowerSyncPolicy {
  const _FollowerSyncPolicy({
    required this.flushInterval,
    required this.softWordDelta,
  });

  final Duration flushInterval;
  final int softWordDelta;
}

class _SupersededPreparation implements Exception {
  const _SupersededPreparation();
}

// Keep the isolate closure outside the controller's async scope: it must never
// capture UI state, source leases, completers or the supervisor itself.
Future<String> _capturedSourceRevision(
  DocumentPreparationKind kind,
  String? fileName,
  String? text,
  Uint8List? bytes,
) => Isolate.run(() {
  final digest = sha256.convert(bytes ?? utf8.encode(text!));
  return 'captured-v1:${kind.name}:${jsonEncode(fileName)}:$digest';
});

Future<({ReaderDocument document, Map<String, String> userVoiceAssignments})>
_restoreDocumentOnWorker(String source) =>
    Isolate.run(() => decodeReaderDocumentWithPreferences(source));
