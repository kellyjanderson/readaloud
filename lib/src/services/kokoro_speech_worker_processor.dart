import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';

import 'kokoro_model_runner.dart';
import 'kokoro_voice_repository.dart';
import 'speech_worker_pipeline.dart';

class KokoroSpeechWorkerChunkProcessor implements SpeechWorkerChunkProcessor {
  KokoroSpeechWorkerChunkProcessor({
    required RootIsolateToken rootIsolateToken,
    required String modelPath,
    required String voicesDirectory,
    required String generatedAudioDirectory,
    required String engineId,
    required String engineVersion,
  }) : _rootIsolateToken = rootIsolateToken,
       _modelPath = modelPath,
       _voicesDirectory = voicesDirectory,
       _generatedAudioDirectory = generatedAudioDirectory,
       _engineId = engineId,
       _engineVersion = engineVersion;

  final RootIsolateToken _rootIsolateToken;
  final String _modelPath;
  final String _voicesDirectory;
  final String _generatedAudioDirectory;
  final String _engineId;
  final String _engineVersion;

  @override
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent event) emit,
  ) async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn<Map<String, dynamic>>(
      _kokoroWorkerEntryPoint,
      <String, dynamic>{
        'sendPort': receivePort.sendPort,
        'rootIsolateToken': _rootIsolateToken,
        'request': request.toMap(),
        'modelPath': _modelPath,
        'voicesDirectory': _voicesDirectory,
        'generatedAudioDirectory': _generatedAudioDirectory,
        'engineId': _engineId,
        'engineVersion': _engineVersion,
      },
    );

    final completion = Completer<void>();
    late final StreamSubscription<dynamic> subscription;
    subscription = receivePort.listen((message) async {
      if (message is! Map<Object?, Object?>) {
        return;
      }
      final payload = message.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (payload['kind'] == 'event') {
        final event = SpeechWorkerEvent.fromMap(payload);
        emit(event);
        return;
      }
      if (payload['kind'] == 'done' && !completion.isCompleted) {
        completion.complete();
      }
    });

    try {
      await completion.future;
    } finally {
      isolate.kill(priority: Isolate.immediate);
      await subscription.cancel();
      receivePort.close();
    }
  }

  @override
  Future<void> dispose() async {}
}

Future<void> _kokoroWorkerEntryPoint(Map<String, dynamic> message) async {
  final sendPort = message['sendPort'] as SendPort;
  final rootIsolateToken = message['rootIsolateToken'] as RootIsolateToken;
  final request = SpeechWorkerChunkRequest.fromMap(
    Map<String, dynamic>.from(message['request'] as Map<dynamic, dynamic>),
  );
  final modelPath = message['modelPath'] as String;
  final voicesDirectory = message['voicesDirectory'] as String;
  final generatedAudioDirectory = message['generatedAudioDirectory'] as String;
  final engineId = message['engineId'] as String;
  final engineVersion = message['engineVersion'] as String;

  BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);

  final cacheFiles = _cacheFilesForChunk(
    request,
    generatedAudioDirectory: generatedAudioDirectory,
    engineId: engineId,
    engineVersion: engineVersion,
  );

  Future<void> emitEvent(
    SpeechWorkerEventType type, {
    required String stage,
    String? audioPath,
    Duration? duration,
    String? message,
    int? elapsedMillis,
  }) async {
    sendPort.send(
      <String, dynamic>{
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
      },
    );
  }

  KokoroModelRunner? modelRunner;
  try {
    final cachedDuration = await _cachedDurationForChunk(cacheFiles, request);
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
    await emitEvent(
      SpeechWorkerEventType.inferencing,
      stage: 'inferencing',
    );
    final voiceRepository = KokoroVoiceRepository(
      voicesDirectory: voicesDirectory,
    );
    final voice = await voiceRepository.loadVoice(request.voiceId);
    final styleVector = voice.getStyleVectorForTokens(tokens.length);

    modelRunner = KokoroModelRunner(modelPath: modelPath);
    await modelRunner.initialize();
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
    await emitEvent(
      SpeechWorkerEventType.failed,
      stage: 'failed',
      message: '$error',
    );
  } finally {
    await modelRunner?.dispose();
    sendPort.send(<String, dynamic>{'kind': 'done'});
  }
}

_ChunkCacheFiles _cacheFilesForChunk(
  SpeechWorkerChunkRequest request, {
  required String generatedAudioDirectory,
  required String engineId,
  required String engineVersion,
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
      .convert(utf8.encode(request.cacheKey))
      .toString();
  return _ChunkCacheFiles(
    wavFile: File('${cacheDirectory.path}${Platform.pathSeparator}$chunkHash.wav'),
    sidecarFile: File(
      '${cacheDirectory.path}${Platform.pathSeparator}$chunkHash.json',
    ),
  );
}

Future<Duration?> _cachedDurationForChunk(
  _ChunkCacheFiles cacheFiles,
  SpeechWorkerChunkRequest request,
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
    if (raw['cacheKey'] != request.cacheKey ||
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
  const _ChunkCacheFiles({
    required this.wavFile,
    required this.sidecarFile,
  });

  final File wavFile;
  final File sidecarFile;
}
