import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_open/file_open.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/document_import_exception.dart';
import '../models/cast_voice_assignment.dart';
import '../models/narration_state.dart';
import '../models/reading_focus_state.dart';
import '../models/reader_document.dart';
import '../models/display_document.dart';
import '../models/chunk_plan.dart';
import '../models/english_pronunciation_profile.dart';
import '../models/spoken_chunk_record.dart';
import '../models/spoken_selection.dart';
import '../models/speech_document.dart';
import '../models/tts_artifact.dart';
import '../models/voice_session_realization.dart';
import '../models/voice_profile.dart';
import '../services/cast_aware_speech_route_service.dart';
import '../services/cast_voice_assignment_service.dart';
import '../services/chunk_planner_service.dart';
import '../services/default_tts_engine.dart';
import '../services/document_import_service.dart';
import '../services/english_pronunciation_profile_selector.dart';
import '../services/playback_instrumentation_service.dart';
import '../services/pronunciation_resource_layering_service.dart';
import '../services/reader_preferences_service.dart';
import '../services/share_intake_service.dart';
import '../services/spoken_selection_mapper_service.dart';
import '../services/tts_engine.dart';
import '../services/voice_session_realization_service.dart';

class ReaderController extends ChangeNotifier {
  ReaderController({
    DocumentImportService? importer,
    ReaderPreferencesService? preferencesService,
    TtsEngine? ttsEngine,
    bool enablePlatformIntakeChannels = true,
  }) : _importer = importer ?? DocumentImportService(),
       _preferencesService = preferencesService ?? ReaderPreferencesService(),
       _ttsEngine = ttsEngine ?? createDefaultTtsEngine(),
       _enablePlatformIntakeChannels = enablePlatformIntakeChannels,
       _document = ReaderDocument.sample(),
       _realizationService = const VoiceSessionRealizationService(),
       _chunkPlannerService = const ChunkPlannerService();

  final DocumentImportService _importer;
  final ReaderPreferencesService _preferencesService;
  final TtsEngine _ttsEngine;
  final bool _enablePlatformIntakeChannels;
  final VoiceSessionRealizationService _realizationService;
  final ChunkPlannerService _chunkPlannerService;
  final CastVoiceAssignmentService _castVoiceAssignmentService =
      const CastVoiceAssignmentService();
  final CastAwareSpeechRouteService _castAwareSpeechRouteService =
      const CastAwareSpeechRouteService();
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
  String? _lastOpenedDocumentPath;
  String? _lastOpenedDirectoryPath;
  String? _liveReadFilePath;
  StreamSubscription<FileSystemEvent>? _liveReadSubscription;
  Timer? _liveReadReloadDebounce;

  bool _isInitializing = true;
  bool _isImporting = false;
  bool _isExporting = false;
  bool _isPlaying = false;
  bool _isFadingOut = false;
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
    final voiceId = _selectedVoiceId;
    if (voiceId == null) {
      return null;
    }
    return _resolveCastVoiceAssignments(preferredNarratorVoiceId: voiceId);
  }
  Duration? get sleepTimerDuration => _sleepTimerDuration;
  String get fontFamily => _fontFamily;
  double get fontScale => _fontScale;
  bool get isLiveReadEnabled => _liveReadFilePath != null;
  String? get liveReadFilePath => _liveReadFilePath;
  bool get canExportAudio => _ttsEngine is AudioExportCapable;
  String get suggestedAudioExportFileName =>
      _defaultAudioExportFileName(_document.title, _selectedVoiceId);

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
    return _voiceSpeeds[voiceId] ?? 1.0;
  }

  Future<void> initialize() async {
    _ttsEngine.onStart = () {
      _isPlaying = true;
      _playbackState = ReaderPlaybackPrimaryState.playing;
      _readingFocusState = _readingFocusState.copyWith(playbackActive: true);
      _recordFirstAudioLatency();
      notifyListeners();
    };
    _ttsEngine.onStatus = (message) {
      _statusMessage = message;
      notifyListeners();
    };
    _ttsEngine.onComplete = () {
      _finalizeActiveSpokenChunk();
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
      _statusMessage = message;
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
    _lastOpenedDocumentPath = preferences.lastOpenedDocumentPath;
    _lastOpenedDirectoryPath = preferences.lastOpenedDirectoryPath;

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
    await stopLiveRead(clearStatus: true);
    _isImporting = true;
    _statusMessage = null;
    notifyListeners();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        withData: true,
        initialDirectory: _lastOpenedDirectoryPath,
        allowedExtensions: DocumentImportService.supportedExtensions,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        _statusMessage = 'The selected file could not be loaded into memory.';
        return;
      }

      await _loadImportedBytes(
        fileName: file.name,
        bytes: bytes,
        sourcePath: file.path,
        successMessage: 'Loaded ${file.name}.',
      );
    } catch (error) {
      _statusMessage = _describeImportError(
        sourceLabel: 'picked file',
        error: error,
      );
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> importDroppedFiles(List<XFile> files) async {
    await _importXFiles(files, sourceLabel: 'Dropped');
  }

  Future<void> importFilePaths(
    List<String> paths, {
    String sourceLabel = 'Opened',
  }) async {
    await stopLiveRead(clearStatus: false);
    final files = paths.map(XFile.new).toList(growable: false);
    await _importXFiles(files, sourceLabel: sourceLabel);
  }

  Future<void> importPastedText(String text) async {
    await stopLiveRead(clearStatus: false);
    final normalized = text.trim();
    if (normalized.isEmpty) {
      _statusMessage = 'Paste some text before importing it.';
      notifyListeners();
      return;
    }

    await _replaceDocument(_importer.importPastedText(normalized));
  }

  Future<void> loadSampleDocument() async {
    await stopLiveRead(clearStatus: false);
    await _replaceDocument(ReaderDocument.sample());
  }

  Future<void> loadDocument(ReaderDocument document) async {
    await stopLiveRead(clearStatus: false);
    await _replaceDocument(document);
  }

  Future<void> pickAndStartLiveRead() async {
    _statusMessage = null;
    notifyListeners();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        withData: false,
        allowMultiple: false,
        initialDirectory: _lastOpenedDirectoryPath,
        allowedExtensions: DocumentImportService.supportedExtensions,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final path = result.files.single.path;
      if (path == null || path.trim().isEmpty) {
        _statusMessage = 'The selected live read file could not be accessed.';
        notifyListeners();
        return;
      }

      await startLiveReadFromPath(path);
    } catch (error) {
      _statusMessage = 'Could not start live read mode: $error';
      notifyListeners();
    }
  }

  Future<void> startLiveReadFromPath(String sourcePath) async {
    final normalizedPath = p.normalize(sourcePath.trim());
    if (normalizedPath.isEmpty) {
      _statusMessage = 'Choose a readable file to start live read mode.';
      notifyListeners();
      return;
    }

    final file = File(normalizedPath);
    if (!await file.exists()) {
      _statusMessage = 'Live read file was not found: $normalizedPath';
      notifyListeners();
      return;
    }

    await _cancelLiveReadWatch();
    _liveReadFilePath = normalizedPath;
    await _rememberOpenedDocumentPath(normalizedPath);
    await _reloadLiveReadFile(initialLoad: true);
    await _startLiveReadWatch(normalizedPath);
    notifyListeners();
  }

  Future<void> stopLiveRead({bool clearStatus = false}) async {
    if (_liveReadFilePath == null &&
        _liveReadSubscription == null &&
        _liveReadReloadDebounce == null) {
      if (clearStatus) {
        _statusMessage = null;
        notifyListeners();
      }
      return;
    }

    await _cancelLiveReadWatch();
    _liveReadFilePath = null;
    if (clearStatus) {
      _statusMessage = null;
    } else {
      _statusMessage = 'Live read mode stopped.';
    }
    notifyListeners();
  }

  Future<bool> restoreLastOpenedDocument() async {
    final lastPath = _lastOpenedDocumentPath;
    if (lastPath == null || lastPath.trim().isEmpty) {
      return false;
    }

    await importFilePaths(<String>[lastPath], sourceLabel: 'Restored');
    return _document.type != ReaderDocumentType.sample;
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
    _narrationState = _narrationState.copyWith(
      currentSectionMode: _sectionModeForCurrentPosition(),
      discourseMode: _discourseModeForCurrentPosition(),
      recentRate: currentSpeed,
      localPronunciationChoices: const <String, String>{},
    );
    _refreshRealizationWindow();
    _refreshChunkPlan();
    await _ttsEngine.selectVoice(voice);
    await _ttsEngine.setSpeechRate(currentSpeed);
    await _ttsEngine.setVolume(1.0);

    _utteranceStartWordIndex = _currentWordIndex;
    _utteranceStartOffset = _document.charOffsetForWord(_currentWordIndex);
    _utteranceStartedAt = DateTime.now();
    _playbackState = ReaderPlaybackPrimaryState.bufferingFirstChunk;
    _playbackRequestedAt = DateTime.now();
    _recordPositionMapConfidenceIfNeeded();

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
        isResumedPlayback: _currentWordIndex > 0,
        speechDocument: _document.speechDocument,
        ttsArtifactSet: _currentRealization?.ttsArtifactSet,
      ),
    );
    notifyListeners();
  }

  Future<void> pausePlayback() async {
    await _ttsEngine.pause();
    _finalizeActiveSpokenChunk();
    _isPlaying = false;
    _playbackState = ReaderPlaybackPrimaryState.paused;
    _readingFocusState = _readingFocusState.copyWith(playbackActive: false);
    notifyListeners();
  }

  Future<void> jumpBySeconds(int seconds) async {
    if (_document.wordCount == 0 || _playbackActivity.isBuffering) return;
    final deltaWords = (seconds * _wordsPerSecond).round();
    final targetWord = (_currentWordIndex + deltaWords).clamp(
      0,
      math.max(_document.wordCount - 1, 0),
    );
    final snappedTarget = _snapWordIndexToSegmentStart(targetWord.toInt());
    _currentWordIndex = snappedTarget;
    _playbackEndedAtDocumentEnd = false;
    _activeSpokenChunkId = null;
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
        _spokenSelection.displayBlockId ?? _readingFocusState.activeDisplayBlockId;
    if (activeDisplayBlockId == null &&
        _readingFocusState.followMode == ReadingFocusFollowMode.following) {
      return;
    }
    _readingFocusState = _readingFocusState.copyWith(
      followMode: ReadingFocusFollowMode.following,
      activeDisplayBlockId: activeDisplayBlockId,
    );
    notifyListeners();
  }

  Future<void> selectVoiceById(String? voiceId) async {
    if (voiceId == null) return;
    _selectedVoiceId = voiceId;
    _voiceSpeeds.putIfAbsent(voiceId, () => 1.0);
    final voice = selectedVoice;
    if (voice != null) {
      await _ttsEngine.selectVoice(voice);
      await _ttsEngine.setSpeechRate(currentSpeed);
    }
    _narrationState = _narrationState.reset(recentRate: currentSpeed);
    _currentRealization = null;
    _currentChunkPlan = null;
    _primePlaybackPreparation();
    _wordsPerSecond = _estimateWordsPerSecond(
      voiceId: voiceId,
      rate: currentSpeed,
    );
    await _persistPreferences();

    if (_isPlaying) {
      await _ttsEngine.stop();
      _isPlaying = false;
      await startPlayback();
      return;
    }

    notifyListeners();
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
      _statusMessage = 'Failed to install the selected voice: $error';
      notifyListeners();
    }
  }

  Future<void> setVoiceSpeed(double speed) async {
    final voiceId = _selectedVoiceId;
    if (voiceId == null) return;
    _voiceSpeeds[voiceId] = speed;
    await _ttsEngine.setSpeechRate(speed);
    _wordsPerSecond = _estimateWordsPerSecond(voiceId: voiceId, rate: speed);
    await _persistPreferences();

    if (_isPlaying) {
      await _ttsEngine.stop();
      _isPlaying = false;
      await startPlayback();
      return;
    }

    notifyListeners();
  }

  Future<void> assignVoiceToCast(String castId, String voiceId) async {
    if (_selectedVoiceId == null || _voices.every((voice) => voice.id != voiceId)) {
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
    } else {
      _castVoiceOverrides[castId] = voiceId;
    }

    _refreshChunkPlan();

    if (_isPlaying) {
      await _ttsEngine.stop();
      _isPlaying = false;
      await startPlayback();
      return;
    }

    notifyListeners();
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

  Future<TtsExportResult?> exportAudioToPath(String outputPath) async {
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

    _isExporting = true;
    _statusMessage = 'Saving audio with ${voice.displayName}...';
    notifyListeners();

    try {
      if (_isPlaying || _playbackActivity.isBuffering) {
        await _ttsEngine.stop();
        _finalizeActiveSpokenChunk();
        _isPlaying = false;
        _playbackState = ReaderPlaybackPrimaryState.paused;
        _playbackActivity = const TtsPlaybackActivity.idle();
      }

      await _ttsEngine.selectVoice(voice);
      await _ttsEngine.setSpeechRate(currentSpeed);
      await _ttsEngine.setVolume(1.0);

      final exportRequest = _buildExportRequest(normalizedPath);
      final result = await exporter.exportAudio(exportRequest);
      _statusMessage = 'Saved audio to ${result.outputPath}.';
      return result;
    } catch (error) {
      _statusMessage = 'Audio export failed: $error';
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
      await stopLiveRead(clearStatus: false);
      final files = sharedData.filePaths.map(XFile.new).toList(growable: false);
      await _importXFiles(files, sourceLabel: sourceLabel);
    } else if (sharedData.text?.trim().isNotEmpty ?? false) {
      await stopLiveRead(clearStatus: false);
      await _replaceDocument(_importer.importSharedText(sharedData.text!));
      _statusMessage = 'Loaded shared text.';
      notifyListeners();
    }

    if (clearAfterHandling) {
      await _shareIntake.clearSharedData();
    }
  }

  Future<void> _importXFiles(
    List<XFile> files, {
    required String sourceLabel,
  }) async {
    if (files.isEmpty) {
      return;
    }

    await stopLiveRead(clearStatus: false);
    _isImporting = true;
    _statusMessage = null;
    notifyListeners();

    try {
      final firstFile = files.first;
      final bytes = await firstFile.readAsBytes();
      final fileName = firstFile.name.isNotEmpty
          ? firstFile.name
          : _fallbackFileName(firstFile.path);

      final message = files.length == 1
          ? '$sourceLabel $fileName.'
          : '$sourceLabel ${files.length} files; loaded $fileName.';

      await _loadImportedBytes(
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        successMessage: message,
      );
    } catch (error) {
      _statusMessage = _describeImportError(
        sourceLabel: sourceLabel,
        error: error,
      );
      notifyListeners();
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> _loadImportedBytes({
    required String fileName,
    required Uint8List bytes,
    String? sourcePath,
    String? successMessage,
  }) async {
    final imported = await _importer.importBytes(
      fileName: fileName,
      bytes: bytes,
    );
    await _replaceDocument(imported);
    await _rememberOpenedDocumentPath(sourcePath);
    if (successMessage != null) {
      _statusMessage = imported.wordCount == 0
          ? '$successMessage No readable text was extracted yet.'
          : successMessage;
      notifyListeners();
    }
  }

  Future<void> _replaceDocument(
    ReaderDocument document, {
    String? statusMessage,
  }) async {
    await _ttsEngine.stop();
    _document = document;
    _currentWordIndex = 0;
    _wordsPerSecond = 2.8;
    _isPlaying = false;
    _isFadingOut = false;
    _playbackEndedAtDocumentEnd = false;
    _playbackState = ReaderPlaybackPrimaryState.idle;
    _playbackActivity = const TtsPlaybackActivity.idle();
    _spokenChunkRecords.clear();
    _activeSpokenChunkId = null;
    _spokenSelection = const SpokenSelection.none();
    _castVoiceOverrides.clear();
    _readingFocusState = const ReadingFocusState();
    _playbackRequestedAt = null;
    _latencyRecordedSessions.clear();
    _positionConfidenceRecordedSessions.clear();
    _narrationState = NarrationState.initial(recentRate: currentSpeed);
    _currentRealization = null;
    _currentChunkPlan = null;
    _primePlaybackPreparation();
    _statusMessage =
        statusMessage ??
        (document.wordCount == 0
            ? 'Loaded ${document.title}, but no readable text was extracted yet.'
            : 'Loaded ${document.title}.');
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
    _spokenSelection = _spokenSelectionMapperService.map(
      SpokenSelectionMapperInput(
        displayDocument: _document.displayDocument,
        speechDocument: _document.speechDocument,
        positionMap: _document.positionMap,
        progress: update,
      ),
    );
    _readingFocusState = _readingFocusState.copyWith(
      playbackActive: true,
      activeDisplayBlockId: _spokenSelection.displayBlockId,
      clearActiveDisplayBlockId: _spokenSelection.displayBlockId == null,
    );
    _playbackEndedAtDocumentEnd = false;
    _narrationState = _narrationState.copyWith(
      currentSectionMode: _sectionModeForCurrentPosition(),
      discourseMode: _discourseModeForCurrentPosition(),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTicker?.cancel();
    _fileOpenSubscription?.cancel();
    _shareSubscription?.cancel();
    _liveReadReloadDebounce?.cancel();
    _liveReadSubscription?.cancel();
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
    await _preferencesService.save(
      selectedVoiceId: _selectedVoiceId,
      voiceSpeeds: _voiceSpeeds,
      fontFamily: _fontFamily,
      fontScale: _fontScale,
      lastOpenedDocumentPath: _lastOpenedDocumentPath,
      lastOpenedDirectoryPath: _lastOpenedDirectoryPath,
    );
  }

  Future<void> _rememberOpenedDocumentPath(String? sourcePath) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return;
    }

    final normalizedPath = p.normalize(sourcePath.trim());
    _lastOpenedDocumentPath = normalizedPath;
    final parent = p.dirname(normalizedPath);
    if (parent.isNotEmpty && parent != '.') {
      _lastOpenedDirectoryPath = parent;
    }
    await _persistPreferences();
  }

  Future<void> _startLiveReadWatch(String normalizedPath) async {
    final parentPath = p.dirname(normalizedPath);
    if (parentPath.isEmpty || parentPath == '.') {
      return;
    }

    final directory = Directory(parentPath);
    final targetBaseName = p.basename(normalizedPath);
    _liveReadSubscription = directory.watch().listen((event) {
      final eventPath = p.normalize(event.path);
      final eventBaseName = p.basename(eventPath);
      if (eventPath != normalizedPath && eventBaseName != targetBaseName) {
        return;
      }
      _liveReadReloadDebounce?.cancel();
      _liveReadReloadDebounce = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(_reloadLiveReadFile(initialLoad: false)),
      );
    });
  }

  Future<void> _cancelLiveReadWatch() async {
    _liveReadReloadDebounce?.cancel();
    _liveReadReloadDebounce = null;
    await _liveReadSubscription?.cancel();
    _liveReadSubscription = null;
  }

  Future<void> _reloadLiveReadFile({required bool initialLoad}) async {
    final sourcePath = _liveReadFilePath;
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return;
    }

    final file = File(sourcePath);
    if (!await file.exists()) {
      _statusMessage =
          'Live read is waiting for ${p.basename(sourcePath)} to appear.';
      notifyListeners();
      return;
    }

    try {
      final imported = await _importer.importBytes(
        fileName: p.basename(sourcePath),
        bytes: await file.readAsBytes(),
      );
      await _replaceDocument(
        imported,
        statusMessage: initialLoad
            ? 'Live read connected to ${p.basename(sourcePath)}.'
            : 'Live read updated ${p.basename(sourcePath)}.',
      );
    } catch (error) {
      _statusMessage = _describeImportError(
        sourceLabel: 'live read file',
        error: error,
      );
      notifyListeners();
    }
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

  void _refreshRealizationWindow() {
    final voiceId = _selectedVoiceId;
    final startSegment = _document.segmentForWordIndex(_currentWordIndex);
    if (voiceId == null || startSegment == null) {
      _currentRealization = null;
      return;
    }
    final selectedProfile = _selectedPronunciationProfile(voiceId: voiceId);
    final mergedResources = _mergedPronunciationResources(selectedProfile);

    _currentRealization = _realizationService.realize(
      VoiceSessionRealizationInput(
        speechDocument: _document.speechDocument,
        baseAnnotations: _document.baseSpeechAnnotations,
        basePronunciationArtifacts: _document.basePronunciationArtifacts,
        startSegmentId: startSegment.segmentId,
        voiceId: voiceId,
        engineId: _engineId(),
        rate: currentSpeed,
        narrationState: _narrationState,
        selectedProfile: selectedProfile,
        mergedPronunciationResources: mergedResources,
      ),
    );
  }

  void _refreshChunkPlan() {
    final voiceId = _selectedVoiceId;
    final startSegment = _document.segmentForWordIndex(_currentWordIndex);
    if (voiceId == null || startSegment == null) {
      _currentChunkPlan = null;
      return;
    }

    final castVoiceAssignments = _resolveCastVoiceAssignments(
      preferredNarratorVoiceId: voiceId,
    );
    final castAwareSpeechRoutes = castVoiceAssignments == null
        ? null
        : _castAwareSpeechRouteService.build(
            CastAwareSpeechRouteInput(
              speechDocument: _document.speechDocument,
              baseAnnotations: _document.baseSpeechAnnotations,
              dialogueAttributions: _document.dialogueAttributions,
              characterCastRegistry: _document.characterCastRegistry,
              castVoiceAssignments: castVoiceAssignments,
            ),
          );

    _currentChunkPlan = _chunkPlannerService.plan(
      ChunkPlannerInput(
        speechDocument: _document.speechDocument,
        baseAnnotations: _document.baseSpeechAnnotations,
        ttsArtifactSet:
            _currentRealization?.ttsArtifactSet ??
            TtsArtifactSet(
              documentId: _document.speechDocument.documentId,
              sessionId: _narrationState.sessionId,
              engineId: _engineId(),
              voiceId: voiceId,
              rate: currentSpeed,
              selectedProfileId: _selectedPronunciationProfile(
                voiceId: voiceId,
              ).profileId,
              startSegmentId: startSegment.segmentId,
              endSegmentId: startSegment.segmentId,
              segments: const <TtsArtifactSegment>[],
            ),
        startSegmentId: startSegment.segmentId,
        voiceId: voiceId,
        rate: currentSpeed,
        engineId: _engineId(),
        engineVersion: _engineVersion(),
        castAwareSpeechRoutes: castAwareSpeechRoutes,
      ),
    );
  }

  void _primePlaybackPreparation() {
    if (_document.wordCount == 0) {
      _currentRealization = null;
      _currentChunkPlan = null;
      return;
    }
    _refreshRealizationWindow();
    _refreshChunkPlan();
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

  TtsExportRequest _buildExportRequest(String outputPath) {
    final voiceId = _selectedVoiceId;
    final firstSegment = _document.speechDocument.segments.firstOrNull;
    final exportProfile = voiceId == null
        ? _selectedPronunciationProfile()
        : _selectedPronunciationProfile(voiceId: voiceId);
    final exportResources = _mergedPronunciationResources(exportProfile);
    final exportRealization = firstSegment == null || voiceId == null
        ? null
        : _realizationService.realize(
            VoiceSessionRealizationInput(
              speechDocument: _document.speechDocument,
              baseAnnotations: _document.baseSpeechAnnotations,
              basePronunciationArtifacts: _document.basePronunciationArtifacts,
              startSegmentId: firstSegment.segmentId,
              voiceId: voiceId,
              engineId: _engineId(),
              rate: currentSpeed,
              narrationState: NarrationState.initial(recentRate: currentSpeed),
              selectedProfile: exportProfile,
              mergedPronunciationResources: exportResources,
            ),
          );
    final castVoiceAssignments = voiceId == null
        ? null
        : _resolveCastVoiceAssignments(preferredNarratorVoiceId: voiceId);
    final castAwareSpeechRoutes = castVoiceAssignments == null
        ? null
        : _castAwareSpeechRouteService.build(
            CastAwareSpeechRouteInput(
              speechDocument: _document.speechDocument,
              baseAnnotations: _document.baseSpeechAnnotations,
              dialogueAttributions: _document.dialogueAttributions,
              characterCastRegistry: _document.characterCastRegistry,
              castVoiceAssignments: castVoiceAssignments,
            ),
          );
    final chunkPlan = firstSegment == null || voiceId == null
        ? null
        : _chunkPlannerService.plan(
            ChunkPlannerInput(
              speechDocument: _document.speechDocument,
              baseAnnotations: _document.baseSpeechAnnotations,
              ttsArtifactSet: exportRealization!.ttsArtifactSet,
              startSegmentId: firstSegment.segmentId,
              voiceId: voiceId,
              rate: currentSpeed,
              engineId: _engineId(),
              engineVersion: _engineVersion(),
              castAwareSpeechRoutes: castAwareSpeechRoutes,
            ),
          );

    return TtsExportRequest(
      text: _document.speakableText,
      outputPath: outputPath,
      documentId: _document.displayDocument.documentId,
      documentTitle: _document.title,
      sourceDescription: _document.sourceDescription,
      sessionId: 'export_${DateTime.now().microsecondsSinceEpoch}',
      normalizationVersion: _document.speechDocument.normalizationVersion,
      chunkPlan: chunkPlan,
      speechDocument: _document.speechDocument,
      ttsArtifactSet: exportRealization?.ttsArtifactSet,
    );
  }

  CastVoiceAssignmentSet? _resolveCastVoiceAssignments({
    required String preferredNarratorVoiceId,
  }) {
    if (_voices.isEmpty) {
      return null;
    }

    return _castVoiceAssignmentService.resolve(
      CastVoiceAssignmentInput(
        characterCastRegistry: _document.characterCastRegistry,
        availableVoices: _voices,
        fallbackVoiceId: preferredNarratorVoiceId,
        preferredNarratorVoiceId: preferredNarratorVoiceId,
        userOverrides: _castVoiceOverrides,
      ),
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
