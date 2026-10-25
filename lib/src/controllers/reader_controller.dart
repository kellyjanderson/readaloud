import '../services/speech_planning_supervisor.dart';
import '../services/voice_assignment_coordinator.dart';
import '../models/voice_assignment_state.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_open/file_open.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/document_import_exception.dart';
import '../models/document_preparation.dart';
import '../models/prepared_voice_binding.dart';
import '../models/cast_voice_assignment.dart';
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
import '../services/cast_voice_assignment_service.dart';
import '../services/default_tts_engine.dart';
import '../services/document_access_service.dart';
import '../services/document_import_service.dart';
import '../services/document_preparation_supervisor.dart';
import '../services/english_pronunciation_profile_selector.dart';
import '../services/playback_instrumentation_service.dart';
import '../services/pronunciation_resource_layering_service.dart';
import '../services/reader_preferences_service.dart';
import '../services/share_intake_service.dart';
import '../services/spoken_selection_mapper_service.dart';
import '../services/tts_engine.dart';

class ReaderController extends ChangeNotifier {
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
    DocumentImportService? importer,
    DocumentPreparationSupervisor? preparationSupervisor,
    DocumentAccessService? documentAccessService,
    ReaderPreferencesService? preferencesService,
    TtsEngine? ttsEngine,
    bool enablePlatformIntakeChannels = true,
  }) : _preparation =
           preparationSupervisor ??
           DocumentPreparationSupervisor(testImporter: importer),
       _documentAccessService =
           documentAccessService ?? createDocumentAccessService(),
       _preferencesService = preferencesService ?? ReaderPreferencesService(),
       _ttsEngine = ttsEngine ?? createDefaultTtsEngine(),
       _enablePlatformIntakeChannels = enablePlatformIntakeChannels,
       _document = ReaderDocument.sample();

  final DocumentPreparationSupervisor _preparation;
  final String _preparationOwner =
      'reader-${DateTime.now().microsecondsSinceEpoch}';
  int _documentRevision = 0;
  int _preparedDocumentRevision = 0;
  int get preparedDocumentRevision => _preparedDocumentRevision;
  String get preparationOwnerId => _preparationOwner;
  int _watchSession = 0;
  bool _disposed = false;
  bool _documentPrepared = true;
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

  Future<void> applyPendingVoiceAssignments() async {
    if (!voiceAssignmentState.hasPending || _applyingVoiceAssignments) return;
    final revision = voiceAssignmentState.requestedRevision;
    final engine = _ttsEngine;
    final anchor = engine is VoiceAssignmentPlaybackCapable
        ? (engine as VoiceAssignmentPlaybackCapable).currentPlaybackResumeAnchor
        : null;
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
    final initial = _isInitialVoiceBuffering;
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
  bool get isDocumentPrepared => _documentPrepared && !_isImporting;
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
    ++_playbackIntent;
    _playbackStartPending = false;
    _invalidateResourceBindings();
    _preparation.cancel();
    return ++_documentRevision;
  }

  Future<ReaderDocument> _prepare(
    int revision,
    DocumentPreparationKind kind, {
    String? text,
    String? fileName,
    Uint8List? bytes,
    Future<Uint8List> Function()? acquireBytes,
  }) async {
    _requireRevision(revision);
    final result = await _preparation.prepare(
      DocumentPreparationRequest(
        ownerId: _preparationOwner,
        revision: revision,
        kind: kind,
        text: text,
        fileName: fileName,
        bytes: bytes,
        watchSession: _liveReadFilePath == null ? null : _watchSession,
      ),
      acquireBytes: acquireBytes,
    );
    _requireRevision(revision);
    if (result.outcome == DocumentPreparationOutcome.cancelled) {
      throw const _SupersededPreparation();
    }
    if (result.outcome != DocumentPreparationOutcome.ready ||
        result.document == null) {
      if (result.importFailure != null) throw result.importFailure!;
      throw StateError(
        result.error ?? 'Document preparation ${result.outcome.name}.',
      );
    }
    return result.document!;
  }

  final DocumentAccessService _documentAccessService;
  final ReaderPreferencesService _preferencesService;
  ReaderPreferences? _pendingPreferences;
  Future<void>? _preferenceSavePump;
  int _preferenceSnapshotRevision = 0;
  final TtsEngine _ttsEngine;
  final bool _enablePlatformIntakeChannels;
  final CastVoiceAssignmentService _castVoiceAssignmentService =
      const CastVoiceAssignmentService();
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
  final Map<String, Map<String, String>> _storedDocumentCastVoiceAssignments =
      <String, Map<String, String>>{};
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
  NarrationState _narrationState = NarrationState.initial();
  VoiceSessionRealization? _currentRealization;
  ChunkPlan? _currentChunkPlan;
  final Map<String, SpokenChunkRecord> _spokenChunkRecords =
      <String, SpokenChunkRecord>{};
  final Map<String, String> _castVoiceOverrides = <String, String>{};
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
    _ttsEngine.onStart = () {
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
      if (_activePreviewVoiceId != null) {
        return;
      }
      _statusMessage = message;
      notifyListeners();
    };
    _ttsEngine.onComplete = () {
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
      if (_activePreviewVoiceId != null) {
        _resetPreviewState();
        unawaited(_restoreSelectedVoiceEngineState());
        _statusMessage = 'Voice preview failed.';
        notifyListeners();
        return;
      }
      if (_activePlaybackDocumentId == null) {
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
      _activePlaybackDocumentId = null;
      _isPlaying = false;
      _isFadingOut = false;
      _playbackRequestedAt = null;
      _playbackState = _playbackActivity.isPlaying
          ? ReaderPlaybackPrimaryState.playing
          : ReaderPlaybackPrimaryState.failed;
      _readingFocusState = _readingFocusState.copyWith(playbackActive: false);
      notifyListeners();
    };
    _ttsEngine.onProgress = _handleProgress;
    _ttsEngine.onActivity = (activity) {
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
      _ttsDebugTraceLogPath = trace.logPath;
      _ttsDebugTraceStartedAt = trace.startedAt;
      _ttsDebugTraceVoiceId = trace.voiceId;
      _ttsDebugTraceLines = trace.recentLines;
      notifyListeners();
    };

    if (_ttsEngine is VoiceLibraryCapable) {
      _voiceLibraryCapable = _ttsEngine as VoiceLibraryCapable
        ..onVoiceLibraryChanged = _handleVoiceLibraryChanged;
      _voiceLibrary = _voiceLibraryCapable!.voiceLibrary;
    }

    final preferences = await _preferencesService.load();
    _selectedVoiceId = preferences.selectedVoiceId;
    _voiceSpeeds
      ..clear()
      ..addAll(preferences.voiceSpeeds);
    _fontFamily = preferences.fontFamily;
    _fontScale = preferences.fontScale;
    _appearanceMode = preferences.appearanceMode;
    _isMultiVoiceEnabled = preferences.multiVoiceEnabled;
    _storedDocumentCastVoiceAssignments
      ..clear()
      ..addAll(preferences.storedDocumentCastVoiceAssignments);
    _resumeState = preferences.resumeState;
    _lastOpenedDocumentPath = preferences.lastOpenedDocumentPath;
    _lastOpenedDocumentAccessToken = preferences.lastOpenedDocumentAccessToken;
    _lastOpenedDirectoryPath = preferences.lastOpenedDirectoryPath;
    _lastOpenedDirectoryAccessToken =
        preferences.lastOpenedDirectoryAccessToken;

    if (_enablePlatformIntakeChannels) {
      await _initializeIntakeChannels();
    }
    await _ttsEngine.initialize();

    try {
      _voices = await _ttsEngine.loadVoices();
      _voiceLibrary = _voiceLibraryCapable?.voiceLibrary ?? _voiceLibrary;
      if (_voices.isNotEmpty) {
        final initialVoice = _findVoiceById(_selectedVoiceId) ?? _voices.first;
        _selectedVoiceId = initialVoice.id;
        _voiceSpeeds.putIfAbsent(_selectedVoiceId!, () => 1.0);
        await _ttsEngine.selectVoice(initialVoice);
        await _ttsEngine.setSpeechRate(currentSpeed);
        await _persistPreferences();
      } else {
        _statusMessage ??=
            'No text-to-speech voices are available on this platform yet.';
      }
    } on MissingPluginException {
      _statusMessage = 'Text to speech is unavailable on this platform.';
    } finally {
      _isInitializing = false;
      notifyListeners();
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
    if (_playbackActivity.isBuffering) {
      return;
    }
    if (_isPlaying) {
      await pausePlayback();
      return;
    }
    await startPlayback();
  }

  Future<void> startPlayback() async {
    if (_disposed || !isDocumentPrepared) return;
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
    if (_preparedAssignmentRevision != assignmentRevision) {
      _invalidateResourceBindings();
    }
    if (!isResourcesReady) {
      try {
        await _prepareResourceBindings(_documentRevision);
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
    _playbackRequestedAt = DateTime.now();
    _recordPositionMapConfidenceIfNeeded();
    _activePlaybackDocumentId = _document.displayDocument.documentId;
    _activeAssignmentRevision = assignmentRevision;
    _activePlaybackIntent = playbackIntent;
    _acknowledgedPlaybackIntent = null;

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

  Future<void> pausePlayback() async {
    final engine = _ttsEngine;
    if (engine is VoiceAssignmentPlaybackCapable) {
      final anchor = (engine as VoiceAssignmentPlaybackCapable)
          .currentPlaybackResumeAnchor;
      if (anchor != null &&
          anchor.documentId == _document.displayDocument.documentId) {
        _pausedVoiceReplayAnchor = anchor;
      }
    }
    ++_playbackIntent;
    _playbackStartPending = false;
    _resumeAfterPreparation = false;
    _flushPendingFollowerProgress();
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
    if (_isPlaying || _playbackActivity.isBuffering) {
      await pausePlayback();
    }

    final voice = _voices
        .where((candidate) => candidate.id == voiceId)
        .firstOrNull;
    if (voice == null) {
      return;
    }

    if (_activePreviewVoiceId != null) {
      await stopVoicePreview(notify: false);
    }

    _activePreviewVoiceId = voiceId;
    _invalidateResourceBindings();
    _isVoicePreviewLoading = true;
    _isVoicePreviewPlaying = false;
    notifyListeners();

    try {
      await _ttsEngine.selectVoice(voice);
      await _ttsEngine.setSpeechRate(_voiceSpeeds[voiceId] ?? 1.0);
      await _ttsEngine.setVolume(1.0);
      await _ttsEngine.speak(
        const TtsSpeakRequest(
          text: 'Hello. This is Read Aloud previewing this voice.',
          documentId: 'voice-preview',
        ),
      );
    } catch (_) {
      _resetPreviewState();
      await _restoreSelectedVoiceEngineState();
      _statusMessage = 'Voice preview failed.';
      notifyListeners();
    }
  }

  Future<void> stopVoicePreview({bool notify = true}) async {
    if (_activePreviewVoiceId == null) {
      return;
    }
    await _ttsEngine.stop();
    _resetPreviewState();
    await _restoreSelectedVoiceEngineState();
    if (notify) {
      notifyListeners();
    }
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
    final automaticAssignments = _castVoiceAssignmentService.resolve(
      CastVoiceAssignmentInput(
        characterCastRegistry: _document.characterCastRegistry,
        availableVoices: _voices,
        fallbackVoiceId: _selectedVoiceId!,
        preferredNarratorVoiceId: _selectedVoiceId,
      ),
    );
    final automaticAssignment = automaticAssignments.forCastId(castId);
    if (automaticAssignment?.effectiveVoiceId == voiceId) {
      _castVoiceOverrides.remove(castId);
      _clearStoredCastVoiceAssignment(castId);
    } else {
      _castVoiceOverrides[castId] = voiceId;
      _storeCastVoiceAssignment(castId, voiceId);
    }
    await _voiceChoicesEdited();
  }

  Future<void> clearCastVoiceOverride(String castId) async {
    final storedAssignments = _currentStoredCastVoiceAssignments();
    if (!_castVoiceOverrides.containsKey(castId) &&
        !storedAssignments.containsKey(castId)) {
      return;
    }
    _castVoiceOverrides.remove(castId);
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
    await _ttsEngine.selectVoice(selected);
    await _ttsEngine.setSpeechRate(currentSpeed);
  }

  Future<TtsExportResult?> exportAudioToPath(String outputPath) async {
    if (voiceAssignmentState.hasPending) {
      _statusMessage = 'Apply pending voice choices before saving audio.';
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

    final exportRevision = _documentRevision;
    final exportAssignmentRevision = voiceAssignmentState.requestedRevision;
    _isExporting = true;
    _statusMessage = 'Saving audio with ${voice.displayName}...';
    notifyListeners();

    try {
      if (!isResourcesReady) await _prepareResourceBindings(_documentRevision);

      _requireRevision(exportRevision);
      if (exportAssignmentRevision != voiceAssignmentState.requestedRevision) {
        throw StateError(
          'Voice choices changed before export preparation completed.',
        );
      }
      final exportRequest = await _buildExportRequest(normalizedPath);
      _requireRevision(exportRevision);
      final result = await exporter.exportAudio(exportRequest);
      _requireRevision(exportRevision);
      if (exportRevision == _documentRevision) {
        _statusMessage = 'Saved audio to ${result.outputPath}.';
      }
      return result;
    } catch (error) {
      if (exportRevision == _documentRevision) {
        _statusMessage = 'Could not save audio right now. Try again.';
      }
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
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
    final imported = await _prepare(
      revision,
      DocumentPreparationKind.bytes,
      fileName: fileName,
      bytes: bytes,
      acquireBytes: acquireBytes,
    );
    await _replaceDocument(
      imported,
      sourcePath: sourcePath,
      revision: revision,
    );
    _requireRevision(revision);
    await _rememberOpenedDocumentPath(sourcePath, revision: revision);
  }

  Future<void> _prepareResourceBindings(int revision) async {
    while (true) {
      try {
        await _prepareResourceBindingsOnce(revision);
        return;
      } on _SupersededPreparation {
        // A newer cast/voice intent on the same analyzed document must retry;
        // a replacement document still terminates this owner immediately.
        _requireRevision(revision);
      }
    }
  }

  Future<void> _prepareResourceBindingsOnce(int revision) async {
    final intent = _resourceBindingIntent;
    final assignmentRevision = voiceAssignmentState.requestedRevision;
    final resourceEngine = _ttsEngine;
    if (resourceEngine is ResourcePreparationCapable &&
        _selectedVoiceId != null) {
      final assignments = _resolveCastVoiceAssignments(
        preferredNarratorVoiceId: _selectedVoiceId!,
      );
      final bindings = await (resourceEngine as ResourcePreparationCapable)
          .prepareDocumentResources(
            documentId: _document.displayDocument.documentId,
            revision: assignmentRevision,
            voiceIds: {
              _selectedVoiceId!,
              ...?assignments?.assignments.map((v) => v.effectiveVoiceId),
            },
            pronunciationProfileId: _selectedPronunciationProfile().profileId,
          )
          .catchError((Object error) {
            _requireRevision(revision);
            if (intent != _resourceBindingIntent ||
                !_voiceAssignments.isCurrent(assignmentRevision)) {
              throw const _SupersededPreparation();
            }
            throw error;
          });
      _requireRevision(revision);
      if (intent != _resourceBindingIntent ||
          !_voiceAssignments.isCurrent(assignmentRevision)) {
        throw const _SupersededPreparation();
      }
      if (bindings.any(
        (binding) =>
            binding.documentId != _document.displayDocument.documentId ||
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
    }
  }

  Future<void> _replaceDocument(
    ReaderDocument document, {
    required int revision,
    String? statusMessage,
    String? sourcePath,
  }) async {
    _requireRevision(revision);
    _activePlaybackDocumentId = null;
    await _ttsEngine.stop();
    _requireRevision(revision);
    _finalizeActiveSpokenChunk();
    _document = document;
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
    _castVoiceOverrides.clear();
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
    await _primePlaybackPreparation();
    await _prepareResourceBindings(revision);
    _requireRevision(revision);
    _documentPrepared = true;
    _clearDocumentLoadStage();
    _statusMessage = statusMessage;
    if (_statusMessage == null && document.wordCount == 0) {
      _statusMessage =
          'Loaded ${document.title}, but no readable text was extracted yet.';
    }
    notifyListeners();
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
    _voiceLibrary = _voiceLibraryCapable?.voiceLibrary ?? const [];
    _voices = await _ttsEngine.loadVoices();

    if (_voices.isEmpty) {
      _selectedVoiceId = null;
      notifyListeners();
      return;
    }

    final resolvedVoice = _findVoiceById(_selectedVoiceId) ?? _voices.first;
    final needsSelectionUpdate = _selectedVoiceId != resolvedVoice.id;
    _selectedVoiceId = resolvedVoice.id;
    _voiceSpeeds.putIfAbsent(resolvedVoice.id, () => 1.0);

    if (needsSelectionUpdate) {
      await _ttsEngine.selectVoice(resolvedVoice);
      await _ttsEngine.setSpeechRate(currentSpeed);
      await _persistPreferences();
    }

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
    _scheduleResumePersistence();
    _queueFollowerProgressUpdate(update);
  }

  @override
  void dispose() {
    unawaited(_planning.shutdown());
    unawaited(_exportPlanner?.shutdown());
    _disposed = true;
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
    _ttsEngine.onProgress = null;
    _ttsEngine.onComplete = null;
    _ttsEngine.onError = null;
    _ttsEngine.onActivity = null;
    _ttsEngine.onDebugTrace = null;
    _ttsEngine.dispose();
    super.dispose();
  }

  VoiceProfile? _findVoiceById(String? voiceId) {
    if (voiceId == null) {
      return null;
    }

    for (final voice in _voices) {
      if (voice.id == voiceId) {
        return voice;
      }
    }

    return null;
  }

  Future<void> _persistPreferences() async {
    _pendingPreferences = ReaderPreferences(
      selectedVoiceId: _selectedVoiceId,
      voiceSpeeds: Map.unmodifiable(_voiceSpeeds),
      fontFamily: _fontFamily,
      fontScale: _fontScale,
      appearanceMode: _appearanceMode,
      multiVoiceEnabled: _isMultiVoiceEnabled,
      storedDocumentCastVoiceAssignments: Map.unmodifiable({
        for (final entry in _storedDocumentCastVoiceAssignments.entries)
          entry.key: Map<String, String>.unmodifiable(entry.value),
      }),
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
          selectedVoiceId: value.selectedVoiceId,
          voiceSpeeds: value.voiceSpeeds,
          fontFamily: value.fontFamily,
          fontScale: value.fontScale,
          appearanceMode: value.appearanceMode,
          multiVoiceEnabled: value.multiVoiceEnabled,
          storedDocumentCastVoiceAssignments:
              value.storedDocumentCastVoiceAssignments,
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
      final restoreToken = await _documentAccessService
          .createPersistentRestoreToken(normalizedPath);
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
        _clearDocumentLoadStage();
        notifyListeners();
      }
    }
  }

  /// Call before disposal when a caller needs proof that preparation drained.
  Future<void> shutdownPreparation() async {
    _beginDocumentRequest();
    _isImporting = false;
    _clearDocumentLoadStage();
    if (!_disposed) notifyListeners();
    ++_watchSession;
    await _cancelLiveReadWatch();
    await _preparation.shutdown();
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

  SpeechPlanningContext? _planningContext({bool fromStart = false}) {
    final voiceId = _selectedVoiceId;
    final start = fromStart
        ? _document.speechDocument.segments.firstOrNull
        : _document.segmentForWordIndex(_currentWordIndex);
    if (voiceId == null || start == null) return null;
    final profile = _selectedPronunciationProfile(voiceId: voiceId);
    final assignments = _resolveCastVoiceAssignments(
      preferredNarratorVoiceId: voiceId,
    );
    return SpeechPlanningContext(
      realization: VoiceSessionRealizationInput(
        speechDocument: _document.speechDocument,
        baseAnnotations: _document.baseSpeechAnnotations,
        basePronunciationArtifacts: _document.basePronunciationArtifacts,
        startSegmentId: start.segmentId,
        voiceId: voiceId,
        engineId: _engineId(),
        rate: currentSpeed,
        narrationState: _narrationState,
        selectedProfile: profile,
        mergedPronunciationResources: _mergedPronunciationResources(profile),
      ),
      engineVersion: _engineVersion(),
      routes: assignments == null
          ? null
          : CastAwareSpeechRouteInput(
              documentVoiceAttribution: _document.documentVoiceAttribution,
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
    try {
      final window = await _planning.plan(
        context,
        maxChunks: _engineId() == 'kokoro' ? 3 : 1000000,
      );
      if (_disposed ||
          revision != _documentRevision ||
          intent != _resourceBindingIntent) {
        return;
      }
      _currentPlanningContext = context;
      _currentRealization = window.realization;
      _currentChunkPlan = window.plan;
    } on PlanningCancelled {
      return;
    }
  }

  String _engineId() {
    final runtime = _ttsEngine.runtimeType.toString().toLowerCase();
    return runtime.contains('kokoro') ? 'kokoro' : 'generic';
  }

  String _engineVersion() => _engineId() == 'kokoro' ? '2' : '1';

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

  Future<TtsExportRequest> _buildExportRequest(String outputPath) async {
    final document = _document;
    final revision = _documentRevision;
    final intent = _resourceBindingIntent;
    final bindings = resourceBindings;
    final context = _planningContext(fromStart: true);
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
        preparedResources: bindings,
      );
    } finally {
      if (identical(_exportPlanner, planner)) _exportPlanner = null;
      await planner.shutdown();
    }
  }

  CastVoiceAssignmentSet? _resolveCastVoiceAssignments({
    required String preferredNarratorVoiceId,
  }) {
    if (!_isMultiVoiceEnabled || _voices.isEmpty) {
      return null;
    }

    return _castVoiceAssignmentService.resolve(
      CastVoiceAssignmentInput(
        characterCastRegistry: _document.characterCastRegistry,
        availableVoices: _voices,
        fallbackVoiceId: preferredNarratorVoiceId,
        preferredNarratorVoiceId: preferredNarratorVoiceId,
        storedAssignments: _currentStoredCastVoiceAssignments(),
        userOverrides: _castVoiceOverrides,
      ),
    );
  }

  Map<String, String> _currentStoredCastVoiceAssignments() {
    return Map<String, String>.unmodifiable(
      _storedDocumentCastVoiceAssignments[_document
              .displayDocument
              .documentId] ??
          const <String, String>{},
    );
  }

  void _storeCastVoiceAssignment(String castId, String voiceId) {
    final documentId = _document.displayDocument.documentId;
    final assignments =
        _storedDocumentCastVoiceAssignments[documentId] ?? <String, String>{};
    assignments[castId] = voiceId;
    _storedDocumentCastVoiceAssignments[documentId] = assignments;
  }

  void _clearStoredCastVoiceAssignment(String castId) {
    final documentId = _document.displayDocument.documentId;
    final assignments = _storedDocumentCastVoiceAssignments[documentId];
    if (assignments == null) {
      return;
    }
    assignments.remove(castId);
    if (assignments.isEmpty) {
      _storedDocumentCastVoiceAssignments.remove(documentId);
    }
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
        chunkAudioDuration == null ||
        voiceId == null ||
        rate == null) {
      return;
    }

    if (_activeSpokenChunkId != null && _activeSpokenChunkId != chunkId) {
      _finalizeSpokenChunk(_activeSpokenChunkId!);
    }

    final existing = _spokenChunkRecords[chunkId];
    _spokenChunkRecords[chunkId] = SpokenChunkRecord(
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
      audioDuration: chunkAudioDuration,
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
