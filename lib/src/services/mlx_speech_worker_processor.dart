import '../models/speech_engine_catalog.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/prepared_voice_binding.dart';
import '../models/voice_profile.dart';
import 'audio_artifact_store.dart';
import 'speech_worker_pipeline.dart';
import 'tts_engine.dart';
import 'mlx_voice_library.dart';

const String mlxTtsModelVersion = 'mlx-audio-0.6.3-mlx-0.32.4-complete-v3';
String mlxTtsVersionFor(int bits) => '$mlxTtsModelVersion-q$bits';
const MethodChannel _mlxLifecycleChannel = MethodChannel(
  'read_aloud/mlx_tts_lifecycle',
);

// Keep isolate closures outside the processor's method context. Dart closures
// can retain that entire context, including unsendable process completers.
Future<AudioArtifact?> _lookupArtifact(String root, String identity) =>
    Isolate.run(() => AudioArtifactStore(Directory(root)).lookup(identity));

Future<AudioArtifact> _publishArtifact(
  String root,
  String identity,
  Uint8List wav,
  Map<String, dynamic> metadata,
) => Isolate.run(
  () => AudioArtifactStore(
    Directory(root),
  ).publish(identity: identity, wav: wav, metadata: metadata),
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
    if (!_lifecycleInstalled) {
      _lifecycleInstalled = true;
      _mlxLifecycleChannel.setMethodCallHandler((call) async {
        if (call.method == 'shutdown') {
          await _activeInstance?._shutdownForApplicationTermination();
        }
      });
    }
  }

  static bool _lifecycleInstalled = false;
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
  String? _modelIdentity;
  String? _activeGeneration;
  Future<void>? _closing;
  final _closedSignal = Completer<void>();
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
    await prepareModel();
    final mlxRoot = Directory(_modelRoot!);
    final engineName = _engineDisplayName(engineId);
    final result = <PreparedVoiceBinding>[];
    for (final voiceId in voiceIds.toSet()) {
      final voices = mlxVoicesFor(engineId);
      if (!voices.any((v) => v.id == voiceId)) {
        throw StateError('Unknown voice for $engineName: $voiceId');
      }
      if (usesReferenceVoiceLibrary(engineId)) {
        final reference = await MlxVoiceLibrary.prepare(
          voiceId,
          mlxRoot,
          cancelled: _closedSignal.future,
        );
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
          'modelIdentity': _modelIdentity,
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

  Future<void> prepareModel() async {
    if (_closed) throw StateError('MLX inference owner is closed.');
    if (_modelIdentity != null) return;
    if (usesReferenceVoiceLibrary(engineId)) await MlxVoiceLibrary.load();
    if (!isMlxEngine(engineId)) {
      throw StateError('Unknown MLX TTS engine: $engineId');
    }
    final supportDirectory = await getApplicationSupportDirectory();
    final mlxRoot = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}read_aloud${Platform.pathSeparator}mlx-tts',
    );
    await mlxRoot.create(recursive: true);
    if (isDramaEngine(engineId)) {
      final voices = MlxVoiceLibrary.profiles
          .where((v) => v.rawValue['provider'] == 'Fish Official')
          .toList();
      for (var i = 0; i < voices.length; i++) {
        if (_closed) throw StateError('MLX inference owner is closed.');
        onResourceProgress?.call(
          TtsResourceProgress(
            stage: 'voiceDownload',
            message: 'Preparing Fish voice ${i + 1} of ${voices.length}…',
            completed: i,
            total: voices.length,
            unit: 'voices',
          ),
        );
        await MlxVoiceLibrary.prepare(
          voices[i].id,
          mlxRoot,
          cancelled: _closedSignal.future,
        );
      }
    }
    if (_closed) throw StateError('MLX inference owner is closed.');
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
    final modelCatalog = await rootBundle.loadString(
      'assets/fish_drama_models.json',
    );
    await File(
      '${mlxRoot.path}/fish_drama_models.json',
    ).writeAsString(modelCatalog, flush: true);
    _helperPath = installedHelper.path;
    _modelRoot = mlxRoot.path;
    _resolvedPythonPath = await _findPythonRuntime(mlxRoot);

    final support = await getApplicationSupportDirectory();
    _store ??= AudioArtifactStore(
      Directory(
        '${support.path}${Platform.pathSeparator}generated-audio${Platform.pathSeparator}mlx-raw-v1',
      ),
    );
    if (_closed) throw StateError('MLX inference owner is closed.');
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
      final loaded = await worker.loadModel(
        modelId: engineId,
        modelPath: modelDirectory?.path ?? '',
        quantizationBits: quantizationBits,
        privateCachePath:
            '${mlxRoot.path}${Platform.pathSeparator}runtime-cache${Platform.pathSeparator}hub',
        onProgress: _handleModelLoadProgress,
      );
      _modelIdentity = loaded['modelIdentity'] as String;
      if (_closed) throw StateError('MLX inference owner is closed.');
    } finally {
      onResourceProgress?.call(null);
      onStatus?.call(null);
    }
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

    if (isDramaEngine(engineId)) {
      final catalog =
          jsonDecode(
                await rootBundle.loadString('assets/fish_drama_models.json'),
              )
              as Map;
      final spec = catalog[engineId] as Map;
      final snapshot =
          'models--${(spec['repo'] as String).replaceAll('/', '--')}/snapshots/${spec['revision']}';
      for (final root in [
        mlxRoot.path,
        '${mlxRoot.parent.parent.parent.path}/read_aloud/mlx-tts',
      ]) {
        final cached = Directory('$root/models/$snapshot');
        var complete = true;
        for (final file in spec['requiredFiles'] as List) {
          if (!await File('${cached.path}/$file').exists()) {
            complete = false;
            break;
          }
        }
        if (complete) {
          return cached;
        }
      }
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
    if (_activeGeneration != generationId) return;
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

    _activeGeneration = request.generationId;
    try {
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
        'modelIdentity': _modelIdentity,
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
      final storePath = store.directory.path;
      final cached = await _lookupArtifact(storePath, identity);
      if (isCancelled()) return;
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
      final requestDirectory = await temporaryDirectory.createTemp('mlx-');
      final temporaryAudio = File('${requestDirectory.path}/speech.wav');
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
            response['sampleRate'] is! int ||
            (response['sampleRate'] as int) <= 0 ||
            response['synthesisIdentity'] != request.synthesisIdentity ||
            response['sessionId'] != request.sessionId ||
            response['generationId'] != request.generationId ||
            response['chunkId'] != request.chunkId ||
            response['bindingFingerprint'] != binding.fingerprint ||
            response['bindingRevision'] != binding.bindingRevision ||
            !await temporaryAudio.exists()) {
          throw StateError('MLX response identity or WAV validation failed.');
        }
        event(SpeechWorkerEventType.serializing, stage: 'serializing');
        final wav = await temporaryAudio.readAsBytes();
        if (AudioArtifactStore.validateWav(wav).sampleRate !=
            response['sampleRate']) {
          throw StateError(
            'Model response and emitted WAV sample rates differ.',
          );
        }
        final metadata = <String, dynamic>{
          'engineId': engineId,
          'modelIdentity': _modelIdentity,
          'voiceId': request.voiceId,
          'speakText': request.speakText,
        };
        final artifact = await _publishArtifact(
          storePath,
          identity,
          wav,
          metadata,
        );
        if (isCancelled()) return;
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
          event(
            SpeechWorkerEventType.failed,
            stage: 'failed',
            message: '$error',
          );
        }
      } finally {
        if (await requestDirectory.exists()) {
          await requestDirectory.delete(recursive: true);
        }
      }
    } finally {
      if (_activeGeneration == request.generationId) _activeGeneration = null;
      _cancelledGenerations.remove(request.generationId);
    }
  }

  @override
  Future<void> dispose() => _shutdownForApplicationTermination();

  Future<void> _shutdownForApplicationTermination() => _closing ??= _close();
  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    if (!_closedSignal.isCompleted) _closedSignal.complete();
    _bindings.clear();
    await _process?.shutdown();
    _process = null;
    if (identical(_activeInstance, this)) _activeInstance = null;
  }
}

class MlxTtsRequestCancelled implements Exception {
  const MlxTtsRequestCancelled();
}

/// One admitted request, one child, and one shared retirement future. Every
/// callback captures its child; an obsolete child can never settle a new job.
class MlxTtsPythonProcess {
  MlxTtsPythonProcess({
    required this.pythonPath,
    required this.helperPath,
    required this.privateCacheDirectory,
    this.memorySampler,
  });
  final String pythonPath;
  final String helperPath;
  final Directory privateCacheDirectory;
  final Future<int> Function(int childPid)? memorySampler;
  static int observedPeakRuntimeBytes = 0;
  Process? _child;
  Future<void>? _starting;
  Future<void>? _retiring;
  Future<void>? _shutdown;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Completer<Map<String, Object?>>? _pendingResponse;
  String? _pendingId;
  void Function(Map<String, Object?>)? _pendingProgress;
  Map<String, Object?>? _loadSpec;
  String? _modelIdentity;
  String _stderrTail = '';
  bool _busy = false;
  bool _disposed = false;
  int _sequence = 0;
  int _cancelEpoch = 0;
  Timer? _memoryTimer;
  bool _samplingMemory = false;
  int? _childFootprint;
  DateTime? _lastChildFootprint;
  DateTime? _childStartedAt;
  int peakRuntimeBytes = 0;

  Future<Map<String, Object?>> loadModel({
    required String modelId,
    required String modelPath,
    required int quantizationBits,
    required String privateCachePath,
    required void Function(Map<String, Object?>) onProgress,
  }) async {
    final spec = <String, Object?>{
      'command': 'load',
      'modelId': modelId,
      'modelPath': modelPath,
      'quantizationBits': quantizationBits,
      'privateCachePath': privateCachePath,
    };
    final response = await _request(
      spec,
      timeout:
          null, // Hub bounds network requests; selection owns cancellation.
      progress: onProgress,
    );
    _loadSpec = spec;
    _modelIdentity = response['modelIdentity'] as String;
    return response;
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
    required Duration? timeout,
    void Function(Map<String, Object?>)? progress,
  }) async {
    if (_disposed) throw StateError('MLX Python worker is closed.');
    if (_busy) {
      throw StateError('MLX Python worker already has an active request.');
    }
    _busy = true; // Reserve before the first await, including process start.
    final epoch = _cancelEpoch;
    try {
      await _retiring;
      final needsLoad = _child == null && body['command'] == 'synthesize';
      await (_starting ??= _start().whenComplete(() => _starting = null));
      if (_disposed || epoch != _cancelEpoch) {
        throw const MlxTtsRequestCancelled();
      }
      final child = _child!;
      if (needsLoad) {
        final spec = _loadSpec;
        if (spec == null) {
          throw StateError('Model must be prepared before synthesis.');
        }
        final loaded = await _exchange(child, spec, null, progress);
        if (loaded['modelIdentity'] != _modelIdentity) {
          throw StateError(
            'Model changed after cancellation; prepare resources again.',
          );
        }
      }
      if (_disposed || epoch != _cancelEpoch) {
        throw const MlxTtsRequestCancelled();
      }
      return await _exchange(child, body, timeout, progress);
    } catch (_) {
      await _retire(); // Errors, malformed replies and timeouts poison the child.
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, Object?>> _exchange(
    Process child,
    Map<String, Object?> body,
    Duration? timeout,
    void Function(Map<String, Object?>)? progress,
  ) async {
    final completion = Completer<Map<String, Object?>>();
    final id = 'mlx-${++_sequence}';
    _pendingId = id;
    _pendingResponse = completion;
    _pendingProgress = progress;
    // Attach the error handler before touching stdin (exit may race flush).
    final responseFuture = timeout == null
        ? completion.future
        : completion.future.timeout(timeout);
    unawaited(
      responseFuture.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    try {
      child.stdin.writeln(jsonEncode({...body, 'id': id}));
      await child.stdin.flush();
      final response = await responseFuture;
      if (response['ok'] != true) {
        throw StateError('${response['error']}. $_stderrTail');
      }
      return response;
    } finally {
      if (identical(_pendingResponse, completion)) {
        _pendingId = null;
        _pendingResponse = null;
        _pendingProgress = null;
      }
    }
  }

  Future<void> _start() async {
    if (_child != null) return;
    if (_disposed) throw const MlxTtsRequestCancelled();
    await privateCacheDirectory.create(recursive: true);
    final child = await Process.start(
      pythonPath,
      ['-u', '-B', helperPath],
      workingDirectory: privateCacheDirectory.path,
      environment: {
        ...Platform.environment,
        'PYTHONUNBUFFERED': '1',
        'PYTHONDONTWRITEBYTECODE': '1',
        'HF_HUB_CACHE': '${privateCacheDirectory.path}/hub',
      },
    );
    _child = child;
    _childFootprint = null;
    _lastChildFootprint = null;
    _childStartedAt = DateTime.now();
    _stderrTail = '';
    bool current() => identical(_child, child);
    _stdoutSubscription = child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (!current()) return;
            try {
              final response = Map<String, Object?>.from(
                jsonDecode(line) as Map,
              );
              if (response['type'] == 'memory') {
                final footprint = response['footprintBytes'];
                if (footprint is! int || footprint <= 0) {
                  throw FormatException('Invalid memory sample: $response');
                }
                _childFootprint = footprint;
                _lastChildFootprint = DateTime.now();
                unawaited(_sampleMemory(child));
                return;
              }
              final pending = _pendingResponse;
              if (pending == null || pending.isCompleted) return;
              if (response['id'] != _pendingId) {
                throw const FormatException('Wrong request identity');
              }
              if (response['type'] == 'progress') {
                _pendingProgress?.call(response);
                return;
              }
              pending.complete(response);
            } catch (error) {
              _fail(StateError('Invalid MLX helper response: $error'));
              unawaited(_retire());
            }
          },
          onError: (Object error) {
            if (current()) _fail(error);
          },
          onDone: () {
            if (current()) {
              _fail(
                StateError('MLX helper response stream closed. $_stderrTail'),
              );
            }
          },
        );
    _stderrSubscription = child.stderr
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            if (!current()) return;
            _stderrTail += chunk;
            if (_stderrTail.length > 8192) {
              _stderrTail = _stderrTail.substring(_stderrTail.length - 8192);
            }
          },
          onError: (Object error) {
            if (current()) _fail(error);
          },
        );
    unawaited(
      child.exitCode.then((code) {
        if (current()) {
          _fail(StateError('MLX helper exited with code $code. $_stderrTail'));
          unawaited(_retire());
        }
      }),
    );
    _memoryTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _sampleMemory(child),
    );
    if (_disposed) await _retire();
  }

  Future<void> _sampleMemory(Process child) async {
    if (_samplingMemory || !identical(_child, child)) return;
    _samplingMemory = true;
    try {
      if (memorySampler == null) {
        final age = DateTime.now().difference(
          _lastChildFootprint ?? _childStartedAt!,
        );
        if (age > const Duration(seconds: 30)) {
          throw StateError('Inference memory telemetry stopped');
        }
        if (_childFootprint == null) return;
      }
      final childBytes = _childFootprint ?? 0;
      final bytes =
          await (memorySampler?.call(child.pid) ??
              _mlxLifecycleChannel
                  .invokeMethod<int>('runtimeFootprint')
                  .then(
                    (bytes) =>
                        (bytes ??
                            (throw StateError('Missing memory footprint'))) +
                        childBytes,
                  ));
      if (!identical(_child, child)) return;
      if (bytes > observedPeakRuntimeBytes) observedPeakRuntimeBytes = bytes;
      if (bytes > peakRuntimeBytes) peakRuntimeBytes = bytes;
      if (bytes >= 99000000000) {
        _fail(
          StateError(
            'Speech runtime reached the 100 GB memory ceiling. Select a smaller Drama variant.',
          ),
        );
        unawaited(_retire());
      }
    } catch (error) {
      if (identical(_child, child)) {
        _fail(StateError('Speech memory monitoring failed: $error'));
        unawaited(_retire());
      }
    } finally {
      _samplingMemory = false;
    }
  }

  void _fail(Object error) {
    final pending = _pendingResponse;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  void cancelActiveRequest() {
    if (!_busy) return;
    ++_cancelEpoch;
    _fail(const MlxTtsRequestCancelled());
    _child?.kill(ProcessSignal.sigterm);
  }

  Future<void> reapCancelledProcess() => _retire();
  Future<void> _retire() =>
      _retiring ??= _terminate().whenComplete(() => _retiring = null);
  Future<void> _terminate() async {
    final child = _child;
    if (child == null) return;
    _memoryTimer?.cancel();
    _memoryTimer = null;
    child.kill(ProcessSignal.sigterm);
    try {
      await child.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode.timeout(const Duration(seconds: 3));
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    if (identical(_child, child)) _child = null;
  }

  Future<void> shutdown() => _shutdown ??= _close();
  Future<void> _close() async {
    _disposed = true;
    ++_cancelEpoch;
    _fail(const MlxTtsRequestCancelled());
    _child?.kill(ProcessSignal.sigterm);
    await _starting;
    await _retire();
  }
}

String? _nativeVoice(String engineId, String voiceId) {
  return voiceId;
}

bool usesReferenceVoiceLibrary(String engineId) =>
    isDramaEngine(engineId) ||
    engineId == 'moss_tts_8b' ||
    engineId == 'qwen3_tts_base_1_7b';

String _engineDisplayName(String engineId) =>
    speechEngineLabels[engineId] ?? engineId;
String defaultVoiceIdFor(String engineId) => switch (engineId) {
  'qwen3_tts_1_7b' => 'Ryan',
  'qwen3_tts_base_1_7b' => 'library_ava',
  'voxtral_4b' => 'casual_male',
  'fish_drama3' ||
  'fish_drama3_8bit' ||
  'fish_drama3_4bit' => 'library_fishadrian',
  'moss_tts_8b' => 'library_ava',
  _ => 'af_bella',
};

List<VoiceProfile> mlxVoicesFor(String engineId) {
  if (isDramaEngine(engineId)) {
    final voices = MlxVoiceLibrary.profiles;
    return [
      ...voices.where((v) => v.id == 'library_fishadrian'),
      ...voices.where(
        (v) =>
            v.rawValue['provider'] == 'Fish Official' &&
            v.id != 'library_fishadrian',
      ),
      ...voices.where((v) => v.rawValue['provider'] != 'Fish Official'),
    ];
  }
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
