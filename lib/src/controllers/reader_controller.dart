import 'dart:async';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_open/file_open.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/reader_document.dart';
import '../models/voice_profile.dart';
import '../services/document_import_service.dart';
import '../services/flutter_tts_engine.dart';
import '../services/share_intake_service.dart';
import '../services/tts_engine.dart';

class ReaderController extends ChangeNotifier {
  ReaderController({DocumentImportService? importer, TtsEngine? ttsEngine})
    : _importer = importer ?? DocumentImportService(),
      _ttsEngine = ttsEngine ?? FlutterTtsEngine(),
      _document = ReaderDocument.sample();

  final DocumentImportService _importer;
  final TtsEngine _ttsEngine;
  final ShareIntakeService _shareIntake = createShareIntakeService();

  ReaderDocument _document;
  List<VoiceProfile> _voices = const <VoiceProfile>[];
  String? _selectedVoiceId;
  final Map<String, double> _voiceSpeeds = <String, double>{};

  bool _isInitializing = true;
  bool _isImporting = false;
  bool _isPlaying = false;
  bool _isFadingOut = false;

  String? _statusMessage;

  int _currentWordIndex = 0;
  double _wordsPerSecond = 2.6;

  int _utteranceStartOffset = 0;
  int _utteranceStartWordIndex = 0;
  DateTime? _utteranceStartedAt;

  Duration? _sleepTimerDuration;
  DateTime? _sleepTimerEndsAt;
  Timer? _sleepTicker;
  StreamSubscription<List<Uri>>? _fileOpenSubscription;
  StreamSubscription<SharedIntake>? _shareSubscription;

  ReaderDocument get document => _document;
  List<VoiceProfile> get voices => _voices;
  bool get isInitializing => _isInitializing;
  bool get isImporting => _isImporting;
  bool get isPlaying => _isPlaying;
  bool get isFadingOut => _isFadingOut;
  String? get statusMessage => _statusMessage;
  int get currentWordIndex => _currentWordIndex;
  double get wordsPerSecond => _wordsPerSecond;
  Duration? get sleepTimerDuration => _sleepTimerDuration;

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
      notifyListeners();
    };
    _ttsEngine.onComplete = () {
      _isPlaying = false;
      _isFadingOut = false;
      notifyListeners();
    };
    _ttsEngine.onError = (message) {
      _statusMessage = message;
      _isPlaying = false;
      _isFadingOut = false;
      notifyListeners();
    };
    _ttsEngine.onProgress = _handleProgress;

    await _initializeIntakeChannels();
    await _ttsEngine.initialize();

    try {
      _voices = await _ttsEngine.loadVoices();
      if (_voices.isNotEmpty) {
        _selectedVoiceId = _voices.first.id;
        _voiceSpeeds[_selectedVoiceId!] = 1.0;
        await _ttsEngine.selectVoice(_voices.first);
        await _ttsEngine.setSpeechRate(currentSpeed);
      } else {
        _statusMessage =
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
    _isImporting = true;
    _statusMessage = null;
    notifyListeners();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        withData: true,
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
        successMessage: 'Loaded ${file.name}.',
      );
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> importDroppedFiles(List<XFile> files) async {
    await _importXFiles(files, sourceLabel: 'Dropped');
  }

  Future<void> importPastedText(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      _statusMessage = 'Paste some text before importing it.';
      notifyListeners();
      return;
    }

    await _replaceDocument(_importer.importPastedText(normalized));
  }

  Future<void> loadSampleDocument() async {
    await _replaceDocument(ReaderDocument.sample());
  }

  Future<void> togglePlayback() async {
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

    _statusMessage = null;
    await _ttsEngine.selectVoice(voice);
    await _ttsEngine.setSpeechRate(currentSpeed);
    await _ttsEngine.setVolume(1.0);

    _utteranceStartWordIndex = _currentWordIndex;
    _utteranceStartOffset = _document.charOffsetForWord(_currentWordIndex);
    _utteranceStartedAt = DateTime.now();

    final speakableTail = _document.speakableText.substring(
      _utteranceStartOffset,
    );
    await _ttsEngine.speak(speakableTail);
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> pausePlayback() async {
    await _ttsEngine.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> jumpBySeconds(int seconds) async {
    if (_document.wordCount == 0) return;
    final deltaWords = (seconds * _wordsPerSecond).round();
    final targetWord = (_currentWordIndex + deltaWords).clamp(
      0,
      math.max(_document.wordCount - 1, 0),
    );
    _currentWordIndex = targetWord.toInt();
    _statusMessage =
        'Jumped ${seconds.abs()} seconds ${seconds < 0 ? 'back' : 'forward'}.';

    if (_isPlaying) {
      await _ttsEngine.stop();
      _isPlaying = false;
      await startPlayback();
      return;
    }

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
    notifyListeners();
  }

  Future<void> setVoiceSpeed(double speed) async {
    final voiceId = _selectedVoiceId;
    if (voiceId == null) return;
    _voiceSpeeds[voiceId] = speed;
    await _ttsEngine.setSpeechRate(speed);
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
      _statusMessage = 'Failed to import $sourceLabel content: $error';
      notifyListeners();
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> _loadImportedBytes({
    required String fileName,
    required Uint8List bytes,
    String? successMessage,
  }) async {
    final imported = await _importer.importBytes(
      fileName: fileName,
      bytes: bytes,
    );
    await _replaceDocument(imported);
    if (successMessage != null) {
      _statusMessage = imported.wordCount == 0
          ? '$successMessage No readable text was extracted yet.'
          : successMessage;
      notifyListeners();
    }
  }

  Future<void> _replaceDocument(ReaderDocument document) async {
    await _ttsEngine.stop();
    _document = document;
    _currentWordIndex = 0;
    _wordsPerSecond = 2.6;
    _isPlaying = false;
    _isFadingOut = false;
    _statusMessage = document.wordCount == 0
        ? 'Loaded ${document.title}, but no readable text was extracted yet.'
        : 'Loaded ${document.title}.';
    notifyListeners();
  }

  Future<void> _fadeOutSleepTimer() async {
    _isFadingOut = true;
    notifyListeners();

    if (_isPlaying) {
      const steps = 8;
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

  void _handleProgress(TtsProgressUpdate update) {
    final globalOffset = _utteranceStartOffset + update.endOffset;
    final nextWordIndex = _document.wordIndexForOffset(globalOffset);
    final elapsed = _utteranceStartedAt == null
        ? 0.0
        : DateTime.now().difference(_utteranceStartedAt!).inMilliseconds / 1000;
    final wordsRead = math.max(1, nextWordIndex - _utteranceStartWordIndex);

    if (elapsed > 0.5) {
      final observed = wordsRead / elapsed;
      _wordsPerSecond = (_wordsPerSecond * 0.8) + (observed * 0.2);
    }

    _currentWordIndex = nextWordIndex;
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTicker?.cancel();
    _fileOpenSubscription?.cancel();
    _shareSubscription?.cancel();
    _ttsEngine.dispose();
    super.dispose();
  }
}

String _fallbackFileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (!normalized.contains('/')) {
    return normalized;
  }
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
