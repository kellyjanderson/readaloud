import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/prepared_voice_binding.dart';
import '../models/voice_profile.dart';
import 'audio_artifact_store.dart';
import 'speech_worker_pipeline.dart';
import 'tts_engine.dart';
import 'mlx_voice_library.dart';

const String mlxTtsModelVersion = 'mlx-audio-0.6.3-mlx-0.32.4-voices-v2';
String mlxTtsVersionFor(int bits) => '$mlxTtsModelVersion-q$bits';
const MethodChannel _mlxLifecycleChannel = MethodChannel(
  'read_aloud/mlx_tts_lifecycle',
);

/// Owns one persistent Python process. Inference runs outside the Flutter
/// isolate; the existing Dart pipeline retains cache, admission and playback.
class MlxSpeechWorkerChunkProcessor
    implements
        SpeechWorkerResourceOwner,
        CancellableSpeechWorkerChunkProcessor {
  MlxSpeechWorkerChunkProcessor({
    required this.engineId,
    required this.modelPath,
    required this.pythonPath,
    this.quantizationBits = 0,
    this.onStatus,
    this.onResourceProgress,
    AudioArtifactStore? artifactStore,
  }) : _store = artifactStore {
    _activeInstance = this;
    _mlxLifecycleChannel.setMethodCallHandler((call) async {
      if (call.method == 'shutdown') await _shutdownForApplicationTermination();
    });
  }

  static MlxSpeechWorkerChunkProcessor? _activeInstance;

  final String engineId;
  final String modelPath;
  final String pythonPath;
  final int quantizationBits;
  final void Function(String? message)? onStatus;
  final void Function(TtsResourceProgress? progress)? onResourceProgress;
  AudioArtifactStore? _store;
  MlxTtsPythonProcess? _process;
  String? _modelRoot;
  String? _helperPath;
  String? _resolvedPythonPath;
  bool _closed = false;
  final Set<String> _cancelledGenerations = <String>{};
  final Map<String, PreparedVoiceBinding> _bindings =
      <String, PreparedVoiceBinding>{};
  final Map<String, String> _referencePaths = <String, String>{};

  @override
  Future<List<PreparedVoiceBinding>> prepareResources({
    required String documentId,
    required int revision,
    required Iterable<String> voiceIds,
    String pronunciationProfileId = 'mlx-default',
  }) async {
    if (_closed) throw StateError('MLX inference owner is closed.');
    if (usesReferenceVoiceLibrary(engineId)) await MlxVoiceLibrary.load();
    if (!<String>{
      'qwen3_tts_1_7b',
      'qwen3_tts_base_1_7b',
      'voxtral_4b',
      'moss_tts_8b',
    }.contains(engineId)) {
      throw StateError('Unknown MLX TTS engine: $engineId');
    }
    final supportDirectory = await getApplicationSupportDirectory();
    final mlxRoot = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}read_aloud${Platform.pathSeparator}mlx-tts',
    );
    await mlxRoot.create(recursive: true);
    final modelDirectory = await _findInstalledModelDirectory(mlxRoot);
    final installedHelper = File(
      '${mlxRoot.path}${Platform.pathSeparator}mlx_tts_worker.py',
    );
    final helperBytes = await rootBundle.load('assets/mlx_tts_worker.py');
    await installedHelper.writeAsBytes(
      helperBytes.buffer.asUint8List(
        helperBytes.offsetInBytes,
        helperBytes.lengthInBytes,
      ),
      flush: true,
    );
    _helperPath = installedHelper.path;
    _modelRoot = mlxRoot.path;
    _resolvedPythonPath = await _findPythonRuntime(mlxRoot);

    final support = await getApplicationSupportDirectory();
    _store ??= AudioArtifactStore(
      Directory(
        '${support.path}${Platform.pathSeparator}generated-audio${Platform.pathSeparator}mlx-raw-v1',
      ),
    );
    final worker = _process ??= MlxTtsPythonProcess(
      pythonPath: _resolvedPythonPath!,
      helperPath: _helperPath!,
      privateCacheDirectory: Directory(
        '${mlxRoot.path}${Platform.pathSeparator}runtime-cache',
      ),
    );
    final engineName = _engineDisplayName(engineId);
    onStatus?.call('Preparing $engineName model…');
    onResourceProgress?.call(
      TtsResourceProgress(
        stage: 'modelCache',
        message:
            'Checking local files and the shared Hugging Face cache for $engineName…',
      ),
    );
    try {
      await worker.loadModel(
        modelId: engineId,
        modelPath: modelDirectory?.path ?? '',
        quantizationBits: quantizationBits,
        privateCachePath:
            '${mlxRoot.path}${Platform.pathSeparator}runtime-cache${Platform.pathSeparator}hub',
        onProgress: _handleModelLoadProgress,
      );
    } finally {
      onResourceProgress?.call(null);
      onStatus?.call(null);
    }

    final result = <PreparedVoiceBinding>[];
    for (final voiceId in voiceIds.toSet()) {
      final voices = mlxVoicesFor(engineId);
      if (!voices.any((v) => v.id == voiceId)) {
        throw StateError('Unknown voice for $engineName: $voiceId');
      }
      if (usesReferenceVoiceLibrary(engineId)) {
        final reference = await MlxVoiceLibrary.prepare(voiceId, mlxRoot);
        if (_closed) throw StateError('MLX inference owner is closed.');
        _referencePaths[voiceId] = reference.path;
      }
      final binding = PreparedVoiceBinding(
        voiceId: voiceId,
        voiceDigest: artifactIdentity(<String, Object?>{
          'engineId': engineId,
          'voiceId': voiceId,
          if (usesReferenceVoiceLibrary(engineId))
            'reference': MlxVoiceLibrary.voice(voiceId).rawValue,
        }),
        modelDigest: artifactIdentity(<String, Object?>{
          'engineId': engineId,
          'engineVersion': mlxTtsVersionFor(quantizationBits),
        }),
        engineVersion: mlxTtsVersionFor(quantizationBits),
        pronunciationProfileId: pronunciationProfileId,
        bindingRevision: revision,
        documentId: documentId,
      );
      _bindings[voiceId] = binding;
      result.add(binding);
    }
    return List<PreparedVoiceBinding>.unmodifiable(result);
  }

  Future<Directory?> _findInstalledModelDirectory(Directory mlxRoot) async {
    if (modelPath.isNotEmpty) {
      final explicit = Directory(modelPath);
      if (!await File(
        '${explicit.path}${Platform.pathSeparator}config.json',
      ).exists()) {
        throw StateError(
          'The configured MLX model folder is invalid: ${explicit.path}',
        );
      }
      return explicit;
    }

    final candidates = <Directory>[
      Directory('${mlxRoot.path}${Platform.pathSeparator}$engineId'),
      // path_provider appends the bundle ID; the runtime installer predates
      // that suffix and uses the containing Application Support directory.
      Directory(
        '${mlxRoot.parent.parent.parent.path}/read_aloud/mlx-tts/$engineId',
      ),
    ];
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      candidates.add(
        Directory(
          '$home${Platform.pathSeparator}Library${Platform.pathSeparator}Containers${Platform.pathSeparator}com.kellyjanderson.readAloud${Platform.pathSeparator}Data${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}read_aloud${Platform.pathSeparator}mlx-tts${Platform.pathSeparator}$engineId',
        ),
      );
    }
    for (final candidate in candidates) {
      if (await File(
        '${candidate.path}${Platform.pathSeparator}config.json',
      ).exists()) {
        return candidate;
      }
    }
    return null;
  }

  Future<String> _findPythonRuntime(Directory mlxRoot) async {
    if (pythonPath.isNotEmpty) return pythonPath;
    final candidates = <String>[
      '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/mlx-python/bin/python3.12',
      '${mlxRoot.path}${Platform.pathSeparator}runtime${Platform.pathSeparator}venv${Platform.pathSeparator}bin${Platform.pathSeparator}python',
      '${mlxRoot.parent.parent.parent.path}/read_aloud/mlx-tts/runtime/venv/bin/python',
    ];
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      candidates.add(
        '$home${Platform.pathSeparator}Library${Platform.pathSeparator}Containers${Platform.pathSeparator}com.kellyjanderson.readAloud${Platform.pathSeparator}Data${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}read_aloud${Platform.pathSeparator}mlx-tts${Platform.pathSeparator}runtime${Platform.pathSeparator}venv${Platform.pathSeparator}bin${Platform.pathSeparator}python',
      );
    }
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    return candidates.first;
  }

  void _handleModelLoadProgress(Map<String, Object?> event) {
    final stage = event['stage'] as String? ?? 'modelLoad';
    final message = event['message'] as String? ?? 'Preparing speech model…';
    final completed = (event['completed'] as num?)?.toInt();
    final total = (event['total'] as num?)?.toInt();
    final unit = event['unit'] as String? ?? 'bytes';
    onStatus?.call(message);
    onResourceProgress?.call(
      TtsResourceProgress(
        stage: stage,
        message: message,
        completed: completed,
        total: total,
        unit: unit,
      ),
    );
  }

  @override
  Future<void> releaseResources() async {
    _bindings.clear();
    _referencePaths.clear();
  }

  @override
  void cancelGeneration(String generationId) {
    _cancelledGenerations.add(generationId);
    _process?.cancelActiveRequest();
  }

  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent event) emit,
  ) async {
    bool isCancelled() =>
        _closed || _cancelledGenerations.contains(request.generationId);
    void event(
      SpeechWorkerEventType type, {
      required String stage,
      String? audioPath,
      Duration? duration,
      String? message,
      int? elapsedMillis,
    }) {
      emit(
        SpeechWorkerEvent(
          type: type,
          sessionId: request.sessionId,
          generationId: request.generationId,
          chunkId: request.chunkId,
          emittedAt: DateTime.now().toUtc(),
          stage: stage,
          audioPath: audioPath,
          duration: duration,
          message: message,
          elapsedMillis: elapsedMillis,
        ),
      );
    }

    if (isCancelled()) {
      event(SpeechWorkerEventType.cancelled, stage: 'cancelled');
      return;
    }
    final binding = _bindings[request.voiceId];
    if (binding == null ||
        binding.fingerprint != request.expectedBindingFingerprint ||
        binding.bindingRevision != request.expectedBindingRevision ||
        binding.documentId != request.documentId) {
      event(
        SpeechWorkerEventType.failed,
        stage: 'bindingValidation',
        message: 'The MLX voice binding changed before inference.',
      );
      return;
    }
    final identity = artifactIdentity(<String, Object?>{
      'schema': 'mlx-python-raw-v1',
      'engineId': engineId,
      'engineVersion': mlxTtsVersionFor(quantizationBits),
      'cacheKey': request.cacheKey,
      'voiceId': request.voiceId,
      'voiceDigest': binding.voiceDigest,
      'rate': request.rate.toString(),
      'language': request.languageTag,
      'speakText': request.speakText,
      'pronunciationArtifacts': request.pronunciationArtifacts,
      'synthesisIdentity': request.synthesisIdentity,
    });
    final store = _store;
    if (store == null) {
      event(
        SpeechWorkerEventType.failed,
        stage: 'cacheInitialization',
        message: 'MLX audio cache is unavailable.',
      );
      return;
    }
    final cached = store.lookup(identity);
    if (cached != null) {
      event(
        SpeechWorkerEventType.cacheHit,
        stage: 'cacheLookup',
        audioPath: cached.audioPath,
        duration: cached.duration,
      );
      event(
        SpeechWorkerEventType.completed,
        stage: 'completed',
        audioPath: cached.audioPath,
        duration: cached.duration,
      );
      return;
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final temporaryAudio = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}mlx-$identity.wav',
    );
    final worker = _process ??= MlxTtsPythonProcess(
      pythonPath: _resolvedPythonPath ?? pythonPath,
      helperPath: _helperPath ?? '',
      privateCacheDirectory: Directory(
        '${_modelRoot ?? ''}${Platform.pathSeparator}runtime-cache',
      ),
    );
    final stopwatch = Stopwatch()..start();
    try {
      event(SpeechWorkerEventType.inferencing, stage: 'inferencing');
      final response = await worker.synthesize(
        requestId: request.synthesisIdentity,
        modelId: engineId,
        sessionId: request.sessionId,
        generationId: request.generationId,
        chunkId: request.chunkId,
        bindingFingerprint: request.expectedBindingFingerprint ?? '',
        bindingRevision: request.expectedBindingRevision ?? -1,
        text: request.speakText,
        voice: _nativeVoice(engineId, request.voiceId),
        referenceAudioPath: _referencePaths[request.voiceId],
        referenceText: usesReferenceVoiceLibrary(engineId)
            ? MlxVoiceLibrary.voice(request.voiceId).rawValue['referenceText']
                  as String
            : null,
        language: _nativeLanguage(request.languageTag),
        outputPath: temporaryAudio.path,
      );
      if (isCancelled()) {
        event(SpeechWorkerEventType.cancelled, stage: 'cancelled');
        return;
      }
      if (response['audioPath'] != temporaryAudio.path ||
          response['sampleRate'] != 24000 ||
          response['synthesisIdentity'] != request.synthesisIdentity ||
          response['sessionId'] != request.sessionId ||
          response['generationId'] != request.generationId ||
          response['chunkId'] != request.chunkId ||
          response['bindingFingerprint'] != binding.fingerprint ||
          response['bindingRevision'] != binding.bindingRevision ||
          !await temporaryAudio.exists()) {
        throw StateError(
          'MLX response identity or 24 kHz WAV validation failed.',
        );
      }
      event(SpeechWorkerEventType.serializing, stage: 'serializing');
      final artifact = store.publish(
        identity: identity,
        wav: await temporaryAudio.readAsBytes(),
        metadata: <String, dynamic>{
          'chunkId': request.chunkId,
          'cacheKey': request.cacheKey,
          'engineId': engineId,
          'engineVersion': mlxTtsVersionFor(quantizationBits),
          'voiceId': request.voiceId,
          'rate': request.rate,
          'languageTag': request.languageTag,
          'documentId': request.documentId,
          'segmentIds': request.segmentIds,
          'speakText': request.speakText,
          'pronunciationArtifacts': request.pronunciationArtifacts,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      stopwatch.stop();
      event(
        SpeechWorkerEventType.completed,
        stage: 'completed',
        audioPath: artifact.audioPath,
        duration: artifact.duration,
        elapsedMillis: stopwatch.elapsedMilliseconds,
      );
    } on MlxTtsRequestCancelled {
      await worker.reapCancelledProcess();
      event(SpeechWorkerEventType.cancelled, stage: 'cancelled');
    } catch (error) {
      if (isCancelled()) {
        event(SpeechWorkerEventType.cancelled, stage: 'cancelled');
      } else {
        event(SpeechWorkerEventType.failed, stage: 'failed', message: '$error');
      }
    } finally {
      _cancelledGenerations.remove(request.generationId);
      if (await temporaryAudio.exists()) await temporaryAudio.delete();
    }
  }

  @override
  Future<void> dispose() => _shutdownForApplicationTermination();

  Future<void> _shutdownForApplicationTermination() async {
    if (_closed) return;
    _closed = true;
    _bindings.clear();
    await _process?.shutdown();
    _process = null;
    if (identical(_activeInstance, this)) _activeInstance = null;
  }
}

class MlxTtsRequestCancelled implements Exception {
  const MlxTtsRequestCancelled();
}

/// A bounded line-oriented protocol. One process handles one request at a time;
/// malformed output, timeout or cancellation retires that process before retry.
class MlxTtsPythonProcess {
  MlxTtsPythonProcess({
    required this.pythonPath,
    required this.helperPath,
    required this.privateCacheDirectory,
  });

  final String pythonPath;
  final String helperPath;
  final Directory privateCacheDirectory;
  Process? _child;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Completer<Map<String, Object?>>? _pendingResponse;
  String? _pendingId;
  void Function(Map<String, Object?> event)? _pendingProgress;
  String _stderrTail = '';
  int _sequence = 0;
  bool _disposed = false;
  Future<void>? _shutdown;

  Future<void> loadModel({
    required String modelId,
    required String modelPath,
    required int quantizationBits,
    required String privateCachePath,
    required void Function(Map<String, Object?> event) onProgress,
  }) async {
    await _request(
      <String, Object?>{
        'command': 'load',
        'modelId': modelId,
        'modelPath': modelPath,
        'quantizationBits': quantizationBits,
        'privateCachePath': privateCachePath,
      },
      timeout: const Duration(hours: 2),
      progress: onProgress,
    );
  }

  Future<Map<String, Object?>> synthesize({
    required String requestId,
    required String modelId,
    required String sessionId,
    required String generationId,
    required String chunkId,
    required String bindingFingerprint,
    required int bindingRevision,
    required String text,
    required String? voice,
    String? referenceAudioPath,
    String? referenceText,
    required String language,
    required String outputPath,
  }) => _request(<String, Object?>{
    'command': 'synthesize',
    'synthesisIdentity': requestId,
    'modelId': modelId,
    'sessionId': sessionId,
    'generationId': generationId,
    'chunkId': chunkId,
    'bindingFingerprint': bindingFingerprint,
    'bindingRevision': bindingRevision,
    'text': text,
    'voice': voice,
    'referenceAudioPath': referenceAudioPath,
    'referenceText': referenceText,
    'language': language,
    'outputPath': outputPath,
  }, timeout: const Duration(minutes: 5));

  Future<Map<String, Object?>> _request(
    Map<String, Object?> body, {
    required Duration timeout,
    void Function(Map<String, Object?> event)? progress,
  }) async {
    if (_disposed) throw StateError('MLX Python worker is closed.');
    await _startIfNeeded();
    if (_pendingResponse != null) {
      throw StateError('MLX Python worker already has an active request.');
    }
    final requestId = 'mlx-${++_sequence}';
    final completion = Completer<Map<String, Object?>>();
    _pendingId = requestId;
    _pendingProgress = progress;
    _pendingResponse = completion;
    final child = _child!;
    try {
      child.stdin.writeln(
        jsonEncode(<String, Object?>{...body, 'id': requestId}),
      );
      await child.stdin.flush();
      final response = await completion.future.timeout(timeout);
      if (response['ok'] != true) {
        throw StateError(
          'MLX helper failed: ${response['error'] ?? 'unknown error'}',
        );
      }
      return response;
    } on TimeoutException {
      await _terminateChild(child);
      throw TimeoutException(
        'MLX helper exceeded ${timeout.inSeconds}s. ${_stderrTail.trim()}',
      );
    } on MlxTtsRequestCancelled {
      rethrow;
    } catch (error) {
      if (error is StateError || error is ProcessException) rethrow;
      throw StateError(
        'MLX helper request failed: $error. ${_stderrTail.trim()}',
      );
    } finally {
      if (identical(_pendingResponse, completion)) {
        _pendingResponse = null;
        _pendingId = null;
        _pendingProgress = null;
      }
    }
  }

  Future<void> _startIfNeeded() async {
    if (_child != null) return;
    final executable = File(pythonPath);
    final helper = File(helperPath);
    if (!await executable.exists()) {
      throw StateError(
        'Python MLX runtime not found. Set READALOUD_MLX_PYTHON to an arm64 Python with mlx-audio installed.',
      );
    }
    if (!await helper.exists()) {
      throw StateError('Bundled MLX helper is missing.');
    }
    await privateCacheDirectory.create(recursive: true);
    final environment = Map<String, String>.from(Platform.environment)
      ..['READALOUD_MLX_PRIVATE_CACHE'] =
          '${privateCacheDirectory.path}${Platform.pathSeparator}hub'
      ..['PYTHONUNBUFFERED'] = '1'
      ..['PYTHONDONTWRITEBYTECODE'] = '1';
    final child = await Process.start(
      pythonPath,
      <String>['-u', helperPath],
      mode: ProcessStartMode.normal,
      environment: environment,
      workingDirectory: privateCacheDirectory.path,
    );
    _child = child;
    _stderrTail = '';
    _stdoutSubscription = child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleResponse,
          onError: _handleStreamError,
          onDone: () {
            _failPending('MLX helper closed its response stream.');
          },
        );
    _stderrSubscription = child.stderr.transform(utf8.decoder).listen((chunk) {
      _stderrTail = (_stderrTail + chunk);
      if (_stderrTail.length > 8192) {
        _stderrTail = _stderrTail.substring(_stderrTail.length - 8192);
      }
    }, onError: _handleStreamError);
    unawaited(
      child.exitCode.then((code) {
        if (identical(_child, child)) _child = null;
        _failPending(
          'MLX helper exited with code $code. ${_stderrTail.trim()}',
        );
      }),
    );
  }

  void _handleResponse(String line) {
    final pending = _pendingResponse;
    if (pending == null) return;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('Response must be an object.');
      }
      final response = Map<String, Object?>.from(decoded);
      if (response['id'] != _pendingId) {
        throw const FormatException(
          'Response identity did not match the active request.',
        );
      }
      if (response['type'] == 'progress') {
        _pendingProgress?.call(response);
        return;
      }
      if (!pending.isCompleted) pending.complete(response);
    } catch (error) {
      if (!pending.isCompleted) {
        pending.completeError(
          StateError('Invalid MLX helper response: $error'),
        );
      }
    }
  }

  void _handleStreamError(Object error, StackTrace stack) {
    _failPending('MLX helper stream failed: $error');
  }

  void _failPending(String message) {
    final pending = _pendingResponse;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError(message));
    }
  }

  void cancelActiveRequest() {
    final child = _child;
    if (child == null || _pendingResponse == null) return;
    final pending = _pendingResponse;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const MlxTtsRequestCancelled());
    }
    child.kill(ProcessSignal.sigterm);
  }

  Future<void> reapCancelledProcess() async {
    final child = _child;
    if (child == null) {
      await _closeStreams();
      return;
    }
    await _waitOrKill(child);
    if (identical(_child, child)) _child = null;
    await _closeStreams();
  }

  Future<void> shutdown() => _shutdown ??= _shutdownInternal();

  Future<void> _shutdownInternal() async {
    _disposed = true;
    final child = _child;
    if (child == null) {
      await _closeStreams();
      return;
    }
    if (_pendingResponse != null) {
      child.kill(ProcessSignal.sigterm);
    } else {
      try {
        final completion = Completer<Map<String, Object?>>();
        final requestId = 'mlx-${++_sequence}';
        _pendingId = requestId;
        _pendingResponse = completion;
        child.stdin.writeln(
          jsonEncode(<String, Object?>{'id': requestId, 'command': 'shutdown'}),
        );
        await child.stdin.flush();
        await completion.future.timeout(const Duration(seconds: 8));
      } catch (_) {
        child.kill(ProcessSignal.sigterm);
      }
    }
    await _waitOrKill(child);
    if (identical(_child, child)) _child = null;
    await _closeStreams();
  }

  Future<void> _terminateChild(Process child) async {
    child.kill(ProcessSignal.sigterm);
    await _waitOrKill(child);
    if (identical(_child, child)) _child = null;
    await _closeStreams();
  }

  Future<void> _waitOrKill(Process child) async {
    try {
      await child.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      child.kill(ProcessSignal.sigkill);
      try {
        await child.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        _failPending('MLX helper did not exit after SIGKILL.');
      }
    }
  }

  Future<void> _closeStreams() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _pendingResponse = null;
    _pendingId = null;
  }
}

String? _nativeVoice(String engineId, String voiceId) {
  return voiceId;
}

bool usesReferenceVoiceLibrary(String engineId) =>
    engineId == 'moss_tts_8b' || engineId == 'qwen3_tts_base_1_7b';

String _engineDisplayName(String engineId) => switch (engineId) {
  'qwen3_tts_1_7b' => 'Qwen3-TTS 1.7B',
  'qwen3_tts_base_1_7b' => 'Qwen3-TTS 1.7B Base',
  'voxtral_4b' => 'Voxtral TTS 4B',
  'moss_tts_8b' => 'MOSS-TTS 8B',
  _ => engineId,
};

String defaultVoiceIdFor(String engineId) => switch (engineId) {
  'qwen3_tts_1_7b' => 'Ryan',
  'qwen3_tts_base_1_7b' => 'library_ava',
  'voxtral_4b' => 'casual_male',
  'moss_tts_8b' => 'library_ava',
  _ => 'af_bella',
};

List<VoiceProfile> mlxVoicesFor(String engineId) {
  if (usesReferenceVoiceLibrary(engineId)) return MlxVoiceLibrary.profiles;
  final definitions = switch (engineId) {
    'qwen3_tts_1_7b' => const <(String, VoiceGender)>[
      ('Ryan', VoiceGender.male),
      ('Aiden', VoiceGender.male),
      ('Vivian', VoiceGender.female),
      ('Serena', VoiceGender.female),
      ('Dylan', VoiceGender.male),
      ('Eric', VoiceGender.male),
      ('Uncle_Fu', VoiceGender.male),
      ('Ono_Anna', VoiceGender.female),
      ('Sohee', VoiceGender.female),
    ],
    'voxtral_4b' => const <(String, VoiceGender)>[
      ('casual_male', VoiceGender.male),
      ('casual_female', VoiceGender.female),
      ('neutral_male', VoiceGender.male),
      ('neutral_female', VoiceGender.female),
      ('cheerful_female', VoiceGender.female),
      ('pt_male', VoiceGender.male),
      ('pt_female', VoiceGender.female),
      ('nl_male', VoiceGender.male),
      ('nl_female', VoiceGender.female),
      ('it_male', VoiceGender.male),
      ('it_female', VoiceGender.female),
      ('fr_male', VoiceGender.male),
      ('fr_female', VoiceGender.female),
      ('es_male', VoiceGender.male),
      ('es_female', VoiceGender.female),
      ('de_male', VoiceGender.male),
      ('de_female', VoiceGender.female),
      ('ar_male', VoiceGender.male),
      ('hi_male', VoiceGender.male),
      ('hi_female', VoiceGender.female),
    ],
    _ => const <(String, VoiceGender)>[],
  };
  return List<VoiceProfile>.unmodifiable(
    definitions.map(
      (definition) => VoiceProfile(
        id: definition.$1,
        label: definition.$1,
        locale: _presetLocale(engineId, definition.$1),
        rawValue: <String, Object?>{'engineId': engineId},
        gender: definition.$2,
        description: 'Provided by the $engineId model.',
        metadataSource: VoiceMetadataSource.engineCatalog,
      ),
    ),
  );
}

String _presetLocale(String engineId, String voiceId) {
  if (engineId == 'qwen3_tts_1_7b') {
    return switch (voiceId) {
      'Ryan' || 'Aiden' => 'en',
      'Ono_Anna' => 'ja',
      'Sohee' => 'ko',
      _ => 'zh',
    };
  }
  final prefix = voiceId.split('_').first;
  return const {'pt', 'nl', 'it', 'fr', 'es', 'de', 'ar', 'hi'}.contains(prefix)
      ? prefix
      : 'en';
}

String _nativeLanguage(String languageTag) {
  final language = languageTag.toLowerCase().split(RegExp('[-_]')).first;
  return switch (language) {
    'en' => 'English',
    'zh' => 'Chinese',
    'ja' => 'Japanese',
    'ko' => 'Korean',
    'fr' => 'French',
    'es' => 'Spanish',
    'de' => 'German',
    'it' => 'Italian',
    'pt' => 'Portuguese',
    'nl' => 'Dutch',
    'ar' => 'Arabic',
    'hi' => 'Hindi',
    _ => languageTag,
  };
}
