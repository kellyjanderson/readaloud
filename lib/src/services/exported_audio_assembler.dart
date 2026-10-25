import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tts_engine.dart';

class ExportedPronunciationArtifact {
  const ExportedPronunciationArtifact({
    required this.artifactId,
    required this.segmentId,
    required this.startWord,
    required this.endWord,
    required this.resolutionClass,
    required this.translationIntent,
    required this.translationOutcome,
    this.representationType,
    this.representationValue,
    this.diagnosticCodes = const <String>[],
  });

  final String artifactId;
  final String segmentId;
  final int startWord;
  final int endWord;
  final String resolutionClass;
  final String translationIntent;
  final String translationOutcome;
  final String? representationType;
  final String? representationValue;
  final List<String> diagnosticCodes;
}

class ExportedBoundaryMetadata {
  const ExportedBoundaryMetadata({
    required this.boundaryClass,
    required this.correctionApplied,
    required this.leadingSilenceBefore,
    required this.leadingSilenceAfter,
    required this.trailingSilenceBefore,
    required this.trailingSilenceAfter,
    required this.joinSilenceBefore,
    required this.joinSilenceAfter,
    required this.isInitialChunk,
    required this.isResumedChunk,
  });

  final String boundaryClass;
  final bool correctionApplied;
  final Duration leadingSilenceBefore;
  final Duration leadingSilenceAfter;
  final Duration trailingSilenceBefore;
  final Duration trailingSilenceAfter;
  final Duration joinSilenceBefore;
  final Duration joinSilenceAfter;
  final bool isInitialChunk;
  final bool isResumedChunk;
}

class ExportedAudioChunk {
  const ExportedAudioChunk({
    required this.chunkId,
    required this.cacheKey,
    required this.audioPath,
    required this.duration,
    required this.segmentIds,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.voiceId,
    this.capabilityProfileId,
    this.missingFallbackWordCount = 0,
    this.pronunciationArtifacts = const <ExportedPronunciationArtifact>[],
    this.boundaryMetadata,
    this.routeId,
    this.castId,
    this.dialogueSpanId,
  });

  final String chunkId;
  final String cacheKey;
  final String audioPath;
  final Duration duration;
  final List<String> segmentIds;
  final int startWordIndex;
  final int endWordIndex;
  final String voiceId;
  final String? capabilityProfileId;
  final int missingFallbackWordCount;
  final List<ExportedPronunciationArtifact> pronunciationArtifacts;
  final ExportedBoundaryMetadata? boundaryMetadata;
  final String? routeId;
  final String? castId;
  final String? dialogueSpanId;
}

class ExportedAudioAssemblyRequest {
  const ExportedAudioAssemblyRequest({
    required this.outputPath,
    required this.engineId,
    required this.engineVersion,
    required this.documentId,
    required this.documentTitle,
    required this.sourceDescription,
    required this.voiceId,
    required this.rate,
    required this.normalizationVersion,
    required this.chunks,
  });

  final String outputPath;
  final String engineId;
  final String engineVersion;
  final String documentId;
  final String documentTitle;
  final String sourceDescription;
  final String voiceId;
  final double rate;
  final String normalizationVersion;
  final List<ExportedAudioChunk> chunks;
}

/// A small main-isolate notification; PCM and JSON work stay in the worker.
class ExportAssemblyProgress {
  const ExportAssemblyProgress(this.requestId, this.stage, this.workerName);
  final int requestId;
  final String stage;
  final String? workerName;
}

class ExportAssemblyCancelled implements Exception {
  const ExportAssemblyCancelled();
  @override
  String toString() => 'Audio export assembly was cancelled.';
}

/// One active request, no waiting queue. Shutdown rejects new intake and drains
/// file handles/temp-file cleanup. Cancellation is cooperative until commit.
class ExportedAudioAssembler {
  ExportedAudioAssembler({
    this.onProgress,
    this.timeout = const Duration(minutes: 5),
  });
  final void Function(ExportAssemblyProgress progress)? onProgress;
  final Duration timeout;
  _AssemblyJob? _active;
  bool _closed = false;
  int _sequence = 0;

  Future<TtsExportResult> assemble(ExportedAudioAssemblyRequest request) {
    if (_closed || _active != null) {
      return Future.error(
        StateError(
          _closed
              ? 'Audio assembler is shut down.'
              : 'Audio assembler already owns an active request.',
        ),
      );
    }
    final job = _AssemblyJob(++_sequence);
    _active = job;
    return _run(job, request);
  }

  void cancel() {
    final job = _active;
    if (job == null || job.committing) return;
    job.cancelled = true;
    job.commands?.send('cancel');
  }

  Future<void> shutdown() async {
    _closed = true;
    final job = _active;
    cancel();
    if (job != null) await job.drained.future;
  }

  Future<TtsExportResult> _run(
    _AssemblyJob job,
    ExportedAudioAssemblyRequest request,
  ) async {
    final port = ReceivePort();
    Object? error;
    TtsExportResult? result;
    var terminal = false;
    final subscription = port.listen((message) {
      if (message == null) {
        if (!terminal) {
          error ??= StateError(
            'Audio assembly worker exited without a result.',
          );
        }
        if (!job.exited.isCompleted) job.exited.complete();
        return;
      }
      if (message is List) {
        error ??= StateError('Audio assembly worker failed: $message');
        return;
      }
      if (message is! Map || message['id'] != job.id) return;
      final stage = message['stage'] as String;
      if (stage == 'ready') {
        job.commands = message['commands'] as SendPort;
        if (job.cancelled) job.commands!.send('cancel');
      }
      if (stage == 'result') {
        terminal = true;
        result = message['result'] as TtsExportResult;
      } else if (stage == 'error') {
        terminal = true;
        error ??= message['cancelled'] == true
            ? const ExportAssemblyCancelled()
            : StateError(message['message'] as String);
      } else {
        try {
          onProgress?.call(
            ExportAssemblyProgress(
              job.id,
              stage,
              message['workerName'] as String?,
            ),
          );
        } catch (callbackError) {
          error ??= callbackError;
          job.cancelled = true;
          job.commands?.send('cancel');
        }
        if (stage == 'staged') {
          // This handshake gives cancellation an explicit pre-publication barrier.
          if (job.cancelled) {
            job.commands!.send('cancel');
          } else {
            job.committing = true;
            job.commands!.send('commit');
          }
        }
      }
    });
    final deadline = Timer(timeout, () {
      if (!job.committing) {
        error ??= TimeoutException(
          'Audio assembly deadline exceeded.',
          timeout,
        );
        job.cancelled = true;
        job.commands?.send('cancel');
      }
    });
    try {
      await Isolate.spawn(
        _assemblyWorker,
        _AssemblyInput(job.id, request, port.sendPort),
        onError: port.sendPort,
        onExit: port.sendPort,
        debugName: 'audio-export-${job.id}',
      );
      await job.exited.future;
      if (error != null) throw error!;
      return result ?? (throw StateError('Audio assembly produced no result.'));
    } finally {
      deadline.cancel();
      await subscription.cancel();
      port.close();
      if (identical(_active, job)) _active = null;
      job.drained.complete();
    }
  }
}

class _AssemblyJob {
  _AssemblyJob(this.id);
  final int id;
  final exited = Completer<void>();
  final drained = Completer<void>();
  SendPort? commands;
  bool cancelled = false;
  bool committing = false;
}

class _AssemblyInput {
  const _AssemblyInput(this.id, this.request, this.reply);
  final int id;
  final ExportedAudioAssemblyRequest request;
  final SendPort reply;
}

Future<void> _assemblyWorker(_AssemblyInput input) async {
  final commands = ReceivePort();
  var cancelled = false;
  final commit = Completer<void>();
  final subscription = commands.listen((message) {
    if (message == 'cancel') {
      cancelled = true;
      if (!commit.isCompleted) commit.complete();
    } else if (message == 'commit' && !commit.isCompleted) {
      commit.complete();
    }
  });
  void checkCancelled() {
    if (cancelled) throw const ExportAssemblyCancelled();
  }

  void send(String stage, [Map<String, Object?> fields = const {}]) {
    input.reply.send({
      'id': input.id,
      'stage': stage,
      'workerName': Isolate.current.debugName,
      ...fields,
    });
  }

  Directory? staging;
  var preserveStaging = false;
  Object? failure;
  TtsExportResult? result;
  try {
    send('ready', {'commands': commands.sendPort});
    final request = input.request;
    if (request.chunks.isEmpty) {
      throw StateError('Audio export requires at least one prepared chunk.');
    }
    if (!request.outputPath.toLowerCase().endsWith('.wav')) {
      throw ArgumentError('Audio export output must end in .wav.');
    }
    final output = File(request.outputPath).absolute;
    final sidecar = File(
      '${output.path.substring(0, output.path.length - 4)}.json',
    );
    await output.parent.create(recursive: true);
    Future<String> canonicalPath(File file) async {
      if (await FileSystemEntity.type(file.path) !=
          FileSystemEntityType.notFound) {
        return file.resolveSymbolicLinks();
      }
      return '${await file.parent.resolveSymbolicLinks()}/${file.uri.pathSegments.last}';
    }

    final destinations = {
      await canonicalPath(output),
      await canonicalPath(sidecar),
    };
    for (final chunk in request.chunks) {
      checkCancelled();
      if (destinations.contains(
        await canonicalPath(File(chunk.audioPath).absolute),
      )) {
        throw ArgumentError('Audio export cannot replace an input chunk.');
      }
    }
    staging = await output.parent.createTemp('.readaloud-export-');
    final stagedAudio = File('${staging.path}/audio.wav');
    final stagedJson = File('${staging.path}/metadata.json');
    final writer = await stagedAudio.open(mode: FileMode.write);
    final formats = <_WavInfo>[];
    var totalBytes = 0;
    try {
      await writer.writeFrom(Uint8List(44));
      for (final chunk in request.chunks) {
        checkCancelled();
        final reader = await File(chunk.audioPath).open();
        try {
          final info = await _scanWav(reader);
          if (formats.isNotEmpty && !info.sameFormat(formats.first)) {
            throw StateError(
              'Audio export requires matching chunk audio formats across the whole document.',
            );
          }
          formats.add(info);
          totalBytes += info.length;
          if (totalBytes + 36 + totalBytes % 2 > 0xffffffff) {
            throw StateError('Audio export exceeds RIFF size limit.');
          }
          await reader.setPosition(info.offset);
          var remaining = info.length;
          while (remaining > 0) {
            checkCancelled();
            final bytes = await reader.read(
              remaining > 65536 ? 65536 : remaining,
            );
            if (bytes.isEmpty) {
              throw StateError('Chunk audio was truncated during export.');
            }
            await writer.writeFrom(bytes);
            remaining -= bytes.length;
          }
        } finally {
          await reader.close();
        }
      }
      if (totalBytes.isOdd) await writer.writeByte(0);
      await writer.setPosition(0);
      await writer.writeFrom(_wavHeader(formats.first, totalBytes));
      await writer.flush();
    } finally {
      await writer.close();
    }
    checkCancelled();
    final format = formats.first;
    final frames = totalBytes ~/ format.blockAlign;
    final duration = Duration(
      microseconds:
          (frames * Duration.microsecondsPerSecond / format.sampleRate).round(),
    );
    final metadata = await stagedJson.open(mode: FileMode.write);
    try {
      final header = jsonEncode(<String, Object?>{
        'exportId': staging.path.split(Platform.pathSeparator).last,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'engineId': request.engineId,
        'engineVersion': request.engineVersion,
        'documentId': request.documentId,
        'documentTitle': request.documentTitle,
        'voiceId': request.voiceId,
        'rate': request.rate,
        'normalizationVersion': request.normalizationVersion,
        'chunkCount': request.chunks.length,
        'durationMillis': (frames * 1000 / format.sampleRate).round(),
        'frameCount': frames,
        'sampleRate': format.sampleRate,
        'outputPath': output.path,
        'sourceDescription': request.sourceDescription,
        'pronunciationSummary': _buildPronunciationSummary(request.chunks),
      });
      await metadata.writeString(
        '${header.substring(0, header.length - 1)},"chunks":[',
      );
      for (var index = 0; index < request.chunks.length; index++) {
        checkCancelled();
        if (index > 0) await metadata.writeString(',');
        await metadata.writeString(
          jsonEncode(_chunkMetadata(request.chunks[index], formats[index])),
        );
      }
      await metadata.writeString(']}');
      await metadata.flush();
    } finally {
      await metadata.close();
    }
    checkCancelled();
    send('staged');
    await commit.future;
    checkCancelled();
    // Synchronous, short publication transaction: no cancellation between renames.
    // Each rename is atomic; two independent paths cannot be crash-atomic as a pair.
    final oldAudio = File('${staging.path}/previous.wav');
    final oldJson = File('${staging.path}/previous.json');
    var audioBackedUp = false;
    var jsonBackedUp = false;
    var audioPublished = false;
    var jsonPublished = false;
    try {
      if (output.existsSync()) {
        output.renameSync(oldAudio.path);
        audioBackedUp = true;
      }
      if (sidecar.existsSync()) {
        sidecar.renameSync(oldJson.path);
        jsonBackedUp = true;
      }
      stagedAudio.renameSync(output.path);
      audioPublished = true;
      stagedJson.renameSync(sidecar.path);
      jsonPublished = true;
    } catch (_) {
      try {
        if (jsonPublished) sidecar.deleteSync();
        if (audioPublished) output.deleteSync();
        if (audioBackedUp) oldAudio.renameSync(output.path);
        if (jsonBackedUp) oldJson.renameSync(sidecar.path);
      } catch (_) {
        preserveStaging = true;
        throw StateError(
          'Export rollback failed; recovery files retained at ${staging.path}.',
        );
      }
      rethrow;
    }
    result = TtsExportResult(
      outputPath: output.path,
      sidecarPath: sidecar.path,
      duration: duration,
      chunkCount: request.chunks.length,
      voiceId: request.voiceId,
      rate: request.rate,
      engineId: request.engineId,
      engineVersion: request.engineVersion,
    );
  } catch (error) {
    failure = error;
  } finally {
    if (staging != null && !preserveStaging) {
      try {
        await staging.delete(recursive: true);
      } catch (error) {
        failure ??= error;
      }
    }
    await subscription.cancel();
    commands.close();
  }
  if (failure != null) {
    send('error', {
      'cancelled': failure is ExportAssemblyCancelled,
      'message': '$failure',
    });
  } else {
    send('result', {'result': result});
  }
  Isolate.exit();
}

class _WavInfo {
  const _WavInfo(
    this.sampleRate,
    this.channels,
    this.bits,
    this.offset,
    this.length,
  );
  final int sampleRate, channels, bits, offset, length;
  int get blockAlign => channels * (bits ~/ 8);
  int get frames => length ~/ blockAlign;
  bool sameFormat(_WavInfo other) =>
      sampleRate == other.sampleRate &&
      channels == other.channels &&
      bits == other.bits;
}

Future<_WavInfo> _scanWav(RandomAccessFile file) async {
  Future<ByteData> read(int length) async {
    final bytes = await file.read(length);
    if (bytes.length != length) {
      throw const FormatException('Truncated WAV header.');
    }
    return ByteData.sublistView(bytes);
  }

  final size = await file.length();
  final header = await read(12);
  String tag(ByteData bytes, int offset) =>
      ascii.decode(bytes.buffer.asUint8List(bytes.offsetInBytes + offset, 4));
  if (tag(header, 0) != 'RIFF' ||
      tag(header, 8) != 'WAVE' ||
      header.getUint32(4, Endian.little) + 8 != size) {
    throw const FormatException('Invalid RIFF/WAVE length or signature.');
  }
  int? rate, channels, bits, pcmOffset, pcmLength;
  var offset = 12;
  while (offset + 8 <= size) {
    await file.setPosition(offset);
    final section = await read(8);
    final length = section.getUint32(4, Endian.little);
    final end = offset + 8 + length;
    if (end + length % 2 > size) {
      throw const FormatException('Truncated WAV section.');
    }
    if (tag(section, 0) == 'fmt ') {
      if (rate != null || length < 16) {
        throw const FormatException('Invalid WAV format section.');
      }
      final format = await read(16);
      channels = format.getUint16(2, Endian.little);
      rate = format.getUint32(4, Endian.little);
      bits = format.getUint16(14, Endian.little);
      if (format.getUint16(0, Endian.little) != 1 ||
          channels == 0 ||
          rate == 0 ||
          ![8, 16, 24, 32].contains(bits) ||
          format.getUint16(12, Endian.little) != channels * bits ~/ 8 ||
          format.getUint32(8, Endian.little) != rate * channels * bits ~/ 8) {
        throw const FormatException('Unsupported or inconsistent PCM format.');
      }
    } else if (tag(section, 0) == 'data') {
      if (pcmOffset != null) {
        throw const FormatException('Multiple WAV data sections.');
      }
      pcmOffset = offset + 8;
      pcmLength = length;
    }
    offset = end + length % 2;
  }
  if (offset != size ||
      rate == null ||
      channels == null ||
      bits == null ||
      pcmOffset == null ||
      pcmLength == null ||
      pcmLength % (channels * bits ~/ 8) != 0) {
    throw const FormatException('Missing or unaligned PCM data.');
  }
  return _WavInfo(rate, channels, bits, pcmOffset, pcmLength);
}

Uint8List _wavHeader(_WavInfo format, int length) {
  final bytes = Uint8List(44);
  final data = ByteData.sublistView(bytes);
  void text(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, ascii.encode(value));
  text(0, 'RIFF');
  data.setUint32(4, 36 + length + length % 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, format.channels, Endian.little);
  data.setUint32(24, format.sampleRate, Endian.little);
  data.setUint32(28, format.sampleRate * format.blockAlign, Endian.little);
  data.setUint16(32, format.blockAlign, Endian.little);
  data.setUint16(34, format.bits, Endian.little);
  text(36, 'data');
  data.setUint32(40, length, Endian.little);
  return bytes;
}

Map<String, Object?> _chunkMetadata(ExportedAudioChunk chunk, _WavInfo info) =>
    {
      'chunkId': chunk.chunkId,
      'cacheKey': chunk.cacheKey,
      'audioPath': chunk.audioPath,
      'durationMillis': (info.frames * 1000 / info.sampleRate).round(),
      'frameCount': info.frames,
      'segmentIds': chunk.segmentIds,
      'startWordIndex': chunk.startWordIndex,
      'endWordIndex': chunk.endWordIndex,
      'voiceId': chunk.voiceId,
      'routeId': chunk.routeId,
      'castId': chunk.castId,
      'dialogueSpanId': chunk.dialogueSpanId,
      'capabilityProfileId': chunk.capabilityProfileId,
      'missingFallbackWordCount': chunk.missingFallbackWordCount,
      'boundaryMetadata': _boundaryMetadataToMap(chunk.boundaryMetadata),
      'pronunciationArtifacts': [
        for (final artifact in chunk.pronunciationArtifacts)
          {
            'artifactId': artifact.artifactId,
            'segmentId': artifact.segmentId,
            'startWord': artifact.startWord,
            'endWord': artifact.endWord,
            'resolutionClass': artifact.resolutionClass,
            'translationIntent': artifact.translationIntent,
            'translationOutcome': artifact.translationOutcome,
            'representationType': artifact.representationType,
            'representationValue': artifact.representationValue,
            'diagnosticCodes': artifact.diagnosticCodes,
          },
      ],
    };
Map<String, Object?>? _boundaryMetadataToMap(
  ExportedBoundaryMetadata? metadata,
) {
  if (metadata == null) {
    return null;
  }

  return <String, Object?>{
    'boundaryClass': metadata.boundaryClass,
    'correctionApplied': metadata.correctionApplied,
    'leadingSilenceBeforeMs': metadata.leadingSilenceBefore.inMilliseconds,
    'leadingSilenceAfterMs': metadata.leadingSilenceAfter.inMilliseconds,
    'trailingSilenceBeforeMs': metadata.trailingSilenceBefore.inMilliseconds,
    'trailingSilenceAfterMs': metadata.trailingSilenceAfter.inMilliseconds,
    'joinSilenceBeforeMs': metadata.joinSilenceBefore.inMilliseconds,
    'joinSilenceAfterMs': metadata.joinSilenceAfter.inMilliseconds,
    'isInitialChunk': metadata.isInitialChunk,
    'isResumedChunk': metadata.isResumedChunk,
  };
}

Map<String, Object?> _buildPronunciationSummary(
  List<ExportedAudioChunk> chunks,
) {
  final artifacts = chunks.expand((chunk) => chunk.pronunciationArtifacts);

  var resolvedLexicalArtifacts = 0;
  var contextSensitiveArtifacts = 0;
  var unresolvedArtifacts = 0;
  var directEngineTranslations = 0;
  var approximatedEngineTranslations = 0;
  var deferredEngineTranslations = 0;
  var missingArtifactFallbackWords = 0;

  for (final chunk in chunks) {
    missingArtifactFallbackWords += chunk.missingFallbackWordCount;
  }

  for (final artifact in artifacts) {
    if (artifact.diagnosticCodes.contains('pronunciation.resolved.lexicon') ||
        artifact.resolutionClass == 'direct_resolved') {
      resolvedLexicalArtifacts += 1;
    }
    if (artifact.diagnosticCodes.contains(
          'pronunciation.context_sensitive.pending',
        ) ||
        artifact.diagnosticCodes.contains(
          'pronunciation.context_sensitive.resolved',
        ) ||
        artifact.resolutionClass == 'context_resolved' ||
        artifact.resolutionClass == 'deferred_to_engine') {
      contextSensitiveArtifacts += 1;
    }
    if (artifact.diagnosticCodes.contains(
          'pronunciation.unresolved.document_time',
        ) ||
        artifact.diagnosticCodes.contains(
          'pronunciation.unresolved.voice_session',
        ) ||
        artifact.resolutionClass == 'unresolved') {
      unresolvedArtifacts += 1;
    }
    switch (artifact.translationOutcome) {
      case 'direct':
        directEngineTranslations += 1;
      case 'approximated':
        approximatedEngineTranslations += 1;
      case 'deferred':
        deferredEngineTranslations += 1;
    }
  }

  return <String, Object?>{
    'totalPronunciationArtifacts': artifacts.length,
    'resolvedLexicalArtifacts': resolvedLexicalArtifacts,
    'contextSensitiveArtifacts': contextSensitiveArtifacts,
    'unresolvedArtifacts': unresolvedArtifacts,
    'directEngineTranslations': directEngineTranslations,
    'approximatedEngineTranslations': approximatedEngineTranslations,
    'deferredEngineTranslations': deferredEngineTranslations,
    'missingArtifactFallbackWords': missingArtifactFallbackWords,
  };
}
