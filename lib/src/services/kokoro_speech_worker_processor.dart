import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';
import '../models/prepared_voice_binding.dart';
import 'kokoro_model_runner.dart';
import 'kokoro_voice_repository.dart';
import 'speech_worker_pipeline.dart';

/// One resident isolate; one command at a time. A timeout quarantines this
/// owner until native work drains: it never starts a replacement session.
class KokoroSpeechWorkerChunkProcessor implements SpeechWorkerChunkProcessor {
  KokoroSpeechWorkerChunkProcessor({
    required RootIsolateToken rootIsolateToken,
    required String modelPath,
    required String voicesDirectory,
    required String generatedAudioDirectory,
    required String engineId,
    required String engineVersion,
    this.timeout = const Duration(minutes: 2),
    this.workerEntryPoint = _residentWorker,
  }) : _configuration = {
         'rootIsolateToken': rootIsolateToken,
         'modelPath': modelPath,
         'voicesDirectory': voicesDirectory,
         'generatedAudioDirectory': generatedAudioDirectory,
         'engineId': engineId,
         'engineVersion': engineVersion,
       };
  final Map<String, dynamic> _configuration;
  final Duration timeout;
  final void Function(Map<String, dynamic>) workerEntryPoint;
  final ReceivePort _port = ReceivePort();
  final Completer<SendPort> _ready = Completer<SendPort>();
  final Completer<void> _exited = Completer<void>();
  Future<void>? _starting;
  Future<void>? _closing;
  StreamSubscription<dynamic>? _subscription;
  Completer<Map<String, dynamic>>? _active;
  void Function(SpeechWorkerEvent)? _emit;
  bool _unhealthy = false;
  bool _exiting = false;
  int _sequence = 0;
  int? _activeId;

  Future<void> _start() => _starting ??= _spawn();
  Future<void> _spawn() async {
    _subscription = _port.listen((raw) {
      if (raw == null || raw is List) {
        _exiting = true;
        _unhealthy = true;
        final error = StateError('Resident synthesis worker exited: $raw');
        if (!_ready.isCompleted) _ready.completeError(error);
        if (_active != null && !_active!.isCompleted) {
          _active!.completeError(error);
        }
        _active = null;
        _emit = null;
        if (raw == null && !_exited.isCompleted) _exited.complete();
        return;
      }
      final message = Map<String, dynamic>.from(raw as Map);
      if (message['kind'] == 'ready') {
        _ready.complete(message['port'] as SendPort);
        return;
      }
      if (message['id'] != _activeId) return;
      if (message['kind'] == 'event') {
        _emit?.call(SpeechWorkerEvent.fromMap(message));
      } else if (message['kind'] == 'done') {
        if (message['quarantined'] == true) _unhealthy = true;
        final active = _active;
        _active = null;
        _emit = null;
        if (message['error'] != null) {
          active?.completeError(StateError(message['error'] as String));
        } else {
          active?.complete(message);
        }
      }
    });
    try {
      await Isolate.spawn(
        workerEntryPoint,
        {..._configuration, 'reply': _port.sendPort},
        onError: _port.sendPort,
        onExit: _port.sendPort,
        debugName: 'kokoro-resident',
      );
      await _ready.future.timeout(timeout);
    } catch (_) {
      _unhealthy = true;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _command(
    Map<String, dynamic> command, {
    void Function(SpeechWorkerEvent)? emit,
    bool closing = false,
  }) async {
    if (!closing && (_closing != null || _unhealthy)) {
      throw StateError('Resident worker is closing or unavailable.');
    }
    await _start();
    if (_active != null) {
      throw StateError('Resident worker admission limit reached.');
    }
    final completion = Completer<Map<String, dynamic>>();
    _active = completion;
    _emit = emit;
    _activeId = ++_sequence;
    (await _ready.future).send({...command, 'id': _activeId});
    try {
      return await (closing
          ? completion.future
          : completion.future.timeout(timeout));
    } on TimeoutException {
      _unhealthy = true;
      _emit = null;
      rethrow;
    }
  }

  Future<List<PreparedVoiceBinding>> prepareResources({
    required String documentId,
    required int revision,
    required Iterable<String> voiceIds,
    String pronunciationProfileId = 'kokoro-default',
  }) async {
    final response = await _command({
      'kind': 'prepare',
      'documentId': documentId,
      'revision': revision,
      'voiceIds': voiceIds.toSet().toList(),
      'pronunciationProfileId': pronunciationProfileId,
    });
    return List.unmodifiable(
      (response['bindings'] as List).map(
        (v) => PreparedVoiceBinding.fromMap(v as Map),
      ),
    );
  }

  Future<void> releaseResources() async {
    await drain();
    if (_starting != null && !_exited.isCompleted) {
      await _command({'kind': 'release'}, closing: true);
    }
  }

  Future<void> drain() async {
    try {
      await _active?.future;
    } catch (_) {}
  }

  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent) emit,
  ) async {
    await _command({'kind': 'chunk', 'request': request.toMap()}, emit: emit);
  }

  @override
  Future<void> dispose() => _closing ??= _dispose();
  Future<void> _dispose() async {
    if (_starting == null) {
      _port.close();
      return;
    }
    await drain();
    if (_exiting) await _exited.future;
    if (!_exited.isCompleted) {
      await _command({'kind': 'shutdown'}, closing: true);
      await _exited.future;
    }
    await _subscription?.cancel();
    _port.close();
  }
}

Future<void> _residentWorker(Map<String, dynamic> configuration) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(
    configuration['rootIsolateToken'] as RootIsolateToken,
  );
  final reply = configuration['reply'] as SendPort;
  final commands = ReceivePort();
  KokoroModelRunner? runner;
  final repository = KokoroVoiceRepository(
    voicesDirectory: configuration['voicesDirectory'] as String,
  );
  final bindings = <String, PreparedVoiceBinding>{};
  String? documentId;
  String? modelDigest;
  Future<void> release() async {
    await runner?.dispose();
    runner = null;
    repository.clear();
    bindings.clear();
    documentId = null;
    modelDigest = null;
    // ignore: avoid_print
    print(
      'READALOUD_RESOURCE ${jsonEncode({'event': 'released', 'loadedVoiceCount': repository.loadedVoiceCount, 'loadCount': repository.loadCount})}',
    );
  }

  reply.send({'kind': 'ready', 'port': commands.sendPort});
  await for (final raw in commands) {
    final command = Map<String, dynamic>.from(raw as Map);
    final id = command['id'];
    try {
      switch (command['kind']) {
        case 'prepare':
          if (documentId != command['documentId']) await release();
          final modelPath = configuration['modelPath'] as String;
          final model = File(modelPath);
          if (!await model.exists() || await model.length() == 0) {
            throw StateError('Missing model asset.');
          }
          final digestNow = (await crypto.sha256.bind(model.openRead()).first)
              .toString();
          if (modelDigest != null && modelDigest != digestNow) await release();
          if (runner == null) {
            modelDigest = digestNow;
            runner = KokoroModelRunner(modelPath: modelPath);
            await runner!.initialize();
            documentId = command['documentId'] as String;
          }
          for (final voiceId in (command['voiceIds'] as List).cast<String>()) {
            await repository.loadVoice(voiceId, validateAsset: true);
            final digest = repository.digestFor(voiceId);
            bindings[voiceId] = PreparedVoiceBinding(
              voiceId: voiceId,
              voiceDigest: digest,
              modelDigest: modelDigest!,
              engineVersion: configuration['engineVersion'] as String,
              pronunciationProfileId:
                  command['pronunciationProfileId'] as String,
              bindingRevision: command['revision'] as int,
            );
          }
          // ignore: avoid_print
          print(
            'READALOUD_RESOURCE ${jsonEncode({'event': 'prepared', 'documentId': documentId, 'revision': command['revision'], 'loadedVoiceCount': repository.loadedVoiceCount, 'loadCount': repository.loadCount, 'modelDigest': modelDigest})}',
          );
          reply.send({
            'kind': 'done',
            'id': id,
            'bindings': bindings.values.map((v) => v.toMap()).toList(),
          });
        case 'chunk':
          final request = SpeechWorkerChunkRequest.fromMap(
            Map<String, dynamic>.from(command['request'] as Map),
          );
          final binding = bindings[request.voiceId];
          if (runner == null ||
              binding == null ||
              documentId != request.documentId) {
            throw StateError(
              'Chunk resources were not prepared for this document and voice.',
            );
          }
          await _processResidentChunk(
            request,
            configuration,
            runner!,
            repository,
            binding,
            (message) => reply.send({...message, 'id': id}),
          );
        case 'release':
          await release();
          reply.send({'kind': 'done', 'id': id});
        case 'shutdown':
          await release();
          commands.close();
          // BackgroundIsolateBinaryMessenger owns a live receive port. Returning
          // from this entry point does not exit the isolate. Native disposal has
          // completed before the final message and supervisor onExit signal.
          Isolate.exit(reply, {'kind': 'done', 'id': id});
        default:
          throw StateError('Unknown resident command.');
      }
    } catch (error) {
      var quarantined =
          command['kind'] == 'release' || command['kind'] == 'shutdown';
      if (command['kind'] == 'prepare') {
        try {
          await release();
        } catch (_) {
          quarantined = true;
        }
      }
      reply.send({
        'kind': 'done',
        'id': id,
        'error': '$error',
        'quarantined': quarantined,
      });
    }
  }
}

Future<void> _processResidentChunk(
  SpeechWorkerChunkRequest request,
  Map<String, dynamic> configuration,
  KokoroModelRunner modelRunner,
  KokoroVoiceRepository voiceRepository,
  PreparedVoiceBinding binding,
  void Function(Map<String, dynamic>) send,
) async {
  var quarantined = false;
  final generatedAudioDirectory =
      configuration['generatedAudioDirectory'] as String;
  final engineId = configuration['engineId'] as String;
  final engineVersion = configuration['engineVersion'] as String;
  final cacheFiles = _cacheFilesForChunk(
    request,
    generatedAudioDirectory: generatedAudioDirectory,
    engineId: engineId,
    engineVersion: engineVersion,
    bindingFingerprint: binding.fingerprint,
  );

  Future<void> emitEvent(
    SpeechWorkerEventType type, {
    required String stage,
    String? audioPath,
    Duration? duration,
    String? message,
    int? elapsedMillis,
  }) async {
    send(<String, dynamic>{
      'kind': 'event',
      'type': type.name,
      'sessionId': request.sessionId,
      'generationId': request.generationId,
      'chunkId': request.chunkId,
      'emittedAtMillis': DateTime.now().toUtc().millisecondsSinceEpoch,
      'stage': stage,
      'audioPath': audioPath,
      'durationMillis': duration?.inMilliseconds,
      'message': message,
      'elapsedMillis': elapsedMillis,
    });
  }

  try {
    final cachedDuration = await _cachedDurationForChunk(
      cacheFiles,
      request,
      binding,
    );
    if (cachedDuration != null) {
      await emitEvent(
        SpeechWorkerEventType.cacheHit,
        stage: 'cacheLookup',
        audioPath: cacheFiles.wavFile.path,
        duration: cachedDuration,
      );
      await emitEvent(
        SpeechWorkerEventType.completed,
        stage: 'completed',
        audioPath: cacheFiles.wavFile.path,
        duration: cachedDuration,
      );
      return;
    }

    final tokens = request.tokens;
    if (tokens.isEmpty) {
      throw StateError('Kokoro could not derive speech tokens for this chunk.');
    }

    final inferenceWatch = Stopwatch()..start();
    await emitEvent(SpeechWorkerEventType.inferencing, stage: 'inferencing');
    final voice = voiceRepository.residentVoice(request.voiceId);
    final styleVector = voice.getStyleVectorForTokens(tokens.length);

    final audio = await modelRunner.runInference(
      tokens: tokens,
      voice: styleVector,
      speed: request.rate,
    );
    inferenceWatch.stop();

    if (audio.isEmpty) {
      throw StateError('Kokoro returned empty audio for this passage.');
    }

    final serializationWatch = Stopwatch()..start();
    await emitEvent(
      SpeechWorkerEventType.serializing,
      stage: 'serializing',
      elapsedMillis: inferenceWatch.elapsedMilliseconds,
    );
    await cacheFiles.wavFile.parent.create(recursive: true);
    await cacheFiles.wavFile.writeAsBytes(
      _buildWavFile(_audioToPcm16(audio), sampleRate),
      flush: true,
    );
    final duration = Duration(
      milliseconds: (audio.length / sampleRate * 1000).round(),
    );
    await cacheFiles.sidecarFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'chunkId': request.chunkId,
        'cacheKey': request.cacheKey,
        'engineId': engineId,
        'engineVersion': engineVersion,
        'binding': binding.toMap(),
        'capabilityProfileId': request.capabilityProfileId,
        'voiceId': request.voiceId,
        'rate': request.rate,
        'boundaryClass': request.boundaryClass.name,
        'normalizationVersion': request.normalizationVersion,
        'documentId': request.documentId,
        'segmentIds': request.segmentIds,
        'speakText': request.speakText,
        'tokenCount': request.tokens.length,
        'tokens': request.tokens,
        'pronunciationArtifacts': request.pronunciationArtifacts,
        'missingFallbackWordCount': request.missingFallbackWordCount,
        'durationMillis': duration.inMilliseconds,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    serializationWatch.stop();

    await emitEvent(
      SpeechWorkerEventType.completed,
      stage: 'completed',
      audioPath: cacheFiles.wavFile.path,
      duration: duration,
      elapsedMillis: serializationWatch.elapsedMilliseconds,
    );
  } catch (error) {
    quarantined = error is KokoroResourceCleanupError;
    await emitEvent(
      SpeechWorkerEventType.failed,
      stage: 'failed',
      message: '$error',
    );
  } finally {
    send(<String, dynamic>{'kind': 'done', 'quarantined': quarantined});
  }
}

_ChunkCacheFiles _cacheFilesForChunk(
  SpeechWorkerChunkRequest request, {
  required String generatedAudioDirectory,
  required String engineId,
  required String engineVersion,
  required String bindingFingerprint,
}) {
  final rateKey =
      'rate_${(request.rate * 100).round().toString().padLeft(3, '0')}';
  final cacheDirectory = Directory(
    [
      generatedAudioDirectory,
      engineId,
      engineVersion,
      request.voiceId,
      rateKey,
    ].join(Platform.pathSeparator),
  );
  final chunkHash = crypto.sha256
      .convert(utf8.encode('${request.cacheKey}:$bindingFingerprint'))
      .toString();
  return _ChunkCacheFiles(
    wavFile: File(
      '${cacheDirectory.path}${Platform.pathSeparator}$chunkHash.wav',
    ),
    sidecarFile: File(
      '${cacheDirectory.path}${Platform.pathSeparator}$chunkHash.json',
    ),
  );
}

Future<Duration?> _cachedDurationForChunk(
  _ChunkCacheFiles cacheFiles,
  SpeechWorkerChunkRequest request,
  PreparedVoiceBinding binding,
) async {
  if (!await cacheFiles.wavFile.exists() ||
      !await cacheFiles.sidecarFile.exists() ||
      await cacheFiles.wavFile.length() <= 44) {
    return null;
  }

  try {
    final raw = jsonDecode(await cacheFiles.sidecarFile.readAsString());
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    if (raw['binding'] is! Map ||
        PreparedVoiceBinding.fromMap(raw['binding'] as Map).fingerprint !=
            binding.fingerprint ||
        raw['cacheKey'] != request.cacheKey ||
        raw['voiceId'] != request.voiceId ||
        raw['normalizationVersion'] != request.normalizationVersion) {
      return null;
    }
    final durationMillis = raw['durationMillis'];
    if (durationMillis is int && durationMillis > 0) {
      return Duration(milliseconds: durationMillis);
    }
  } catch (_) {
    return null;
  }

  final length = await cacheFiles.wavFile.length();
  final dataBytes = (length - 44).clamp(0, length);
  final sampleCount = dataBytes ~/ Int16List.bytesPerElement;
  return Duration(milliseconds: (sampleCount / sampleRate * 1000).round());
}

Int16List _audioToPcm16(List<num> audio) {
  final pcm = Int16List(audio.length);
  for (var index = 0; index < audio.length; index += 1) {
    final sample = audio[index].toDouble().clamp(-1.0, 1.0);
    pcm[index] = (sample * 32767).round().clamp(-32768, 32767);
  }
  return pcm;
}

Uint8List _buildWavFile(Int16List pcm, int wavSampleRate) {
  final dataLength = pcm.length * Int16List.bytesPerElement;
  final totalLength = 44 + dataLength;
  final bytes = BytesBuilder(copy: false);

  void writeString(String value) {
    bytes.add(value.codeUnits);
  }

  void writeInt(int value, int byteCount) {
    final buffer = ByteData(byteCount);
    if (byteCount == 2) {
      buffer.setUint16(0, value, Endian.little);
    } else if (byteCount == 4) {
      buffer.setUint32(0, value, Endian.little);
    } else {
      throw ArgumentError('Unsupported byte count: $byteCount');
    }
    bytes.add(buffer.buffer.asUint8List());
  }

  writeString('RIFF');
  writeInt(totalLength - 8, 4);
  writeString('WAVE');
  writeString('fmt ');
  writeInt(16, 4);
  writeInt(1, 2);
  writeInt(1, 2);
  writeInt(wavSampleRate, 4);
  writeInt(wavSampleRate * Int16List.bytesPerElement, 4);
  writeInt(Int16List.bytesPerElement, 2);
  writeInt(16, 2);
  writeString('data');
  writeInt(dataLength, 4);
  bytes.add(pcm.buffer.asUint8List());

  return bytes.takeBytes();
}

class _ChunkCacheFiles {
  const _ChunkCacheFiles({required this.wavFile, required this.sidecarFile});

  final File wavFile;
  final File sidecarFile;
}
