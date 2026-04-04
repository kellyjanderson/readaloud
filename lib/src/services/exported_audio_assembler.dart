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

class ExportedAudioAssembler {
  const ExportedAudioAssembler();

  Future<TtsExportResult> assemble(ExportedAudioAssemblyRequest request) async {
    if (request.chunks.isEmpty) {
      throw StateError('Audio export requires at least one prepared chunk.');
    }

    final frames = <Uint8List>[];
    int? sampleRate;
    int? channelCount;
    int? bitsPerSample;
    var totalPcmLength = 0;
    var totalDuration = Duration.zero;

    for (final chunk in request.chunks) {
      final decoded = await _readWavFile(chunk.audioPath);
      sampleRate ??= decoded.sampleRate;
      channelCount ??= decoded.channelCount;
      bitsPerSample ??= decoded.bitsPerSample;
      if (decoded.sampleRate != sampleRate ||
          decoded.channelCount != channelCount ||
          decoded.bitsPerSample != bitsPerSample) {
        throw StateError(
          'Audio export requires matching chunk audio formats across the whole document.',
        );
      }
      frames.add(decoded.pcmBytes);
      totalPcmLength += decoded.pcmBytes.length;
      totalDuration += chunk.duration;
    }

    final outputFile = File(request.outputPath);
    await outputFile.parent.create(recursive: true);
    final wavBytes = _buildWavFile(
      sampleRate: sampleRate!,
      channelCount: channelCount!,
      bitsPerSample: bitsPerSample!,
      pcmFrames: frames,
      totalPcmLength: totalPcmLength,
    );
    await outputFile.writeAsBytes(wavBytes, flush: true);

    final sidecarPath = outputFile.path.replaceFirst(
      RegExp(r'\.wav$'),
      '.json',
    );
    final sidecarFile = File(sidecarPath);
    final exportId = 'export_${DateTime.now().microsecondsSinceEpoch}';
    await sidecarFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'exportId': exportId,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'engineId': request.engineId,
        'engineVersion': request.engineVersion,
        'documentId': request.documentId,
        'documentTitle': request.documentTitle,
        'voiceId': request.voiceId,
        'rate': request.rate,
        'normalizationVersion': request.normalizationVersion,
        'chunkCount': request.chunks.length,
        'durationMillis': totalDuration.inMilliseconds,
        'outputPath': outputFile.path,
        'sourceDescription': request.sourceDescription,
        'pronunciationSummary': _buildPronunciationSummary(request.chunks),
        'chunks': request.chunks
            .map(
              (chunk) => <String, Object?>{
                'chunkId': chunk.chunkId,
                'cacheKey': chunk.cacheKey,
                'audioPath': chunk.audioPath,
                'durationMillis': chunk.duration.inMilliseconds,
                'segmentIds': chunk.segmentIds,
                'startWordIndex': chunk.startWordIndex,
                'endWordIndex': chunk.endWordIndex,
                'voiceId': chunk.voiceId,
                'routeId': chunk.routeId,
                'castId': chunk.castId,
                'dialogueSpanId': chunk.dialogueSpanId,
                'capabilityProfileId': chunk.capabilityProfileId,
                'missingFallbackWordCount': chunk.missingFallbackWordCount,
                'boundaryMetadata': _boundaryMetadataToMap(
                  chunk.boundaryMetadata,
                ),
                'pronunciationArtifacts': chunk.pronunciationArtifacts
                    .map(
                      (artifact) => <String, Object?>{
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
                    )
                    .toList(growable: false),
              },
            )
            .toList(growable: false),
      }),
      flush: true,
    );

    return TtsExportResult(
      outputPath: outputFile.path,
      sidecarPath: sidecarFile.path,
      duration: totalDuration,
      chunkCount: request.chunks.length,
      voiceId: request.voiceId,
      rate: request.rate,
      engineId: request.engineId,
      engineVersion: request.engineVersion,
    );
  }
}

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

class _DecodedWavFile {
  const _DecodedWavFile({
    required this.sampleRate,
    required this.channelCount,
    required this.bitsPerSample,
    required this.pcmBytes,
  });

  final int sampleRate;
  final int channelCount;
  final int bitsPerSample;
  final Uint8List pcmBytes;
}

Future<_DecodedWavFile> _readWavFile(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw StateError('Audio export could not find chunk audio at $path.');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length < 44) {
    throw StateError('Audio export found an invalid WAV file at $path.');
  }

  String readAscii(int offset, int length) =>
      ascii.decode(bytes.sublist(offset, offset + length));
  int readUint16(int offset) =>
      bytes.buffer.asByteData().getUint16(offset, Endian.little);
  int readUint32(int offset) =>
      bytes.buffer.asByteData().getUint32(offset, Endian.little);

  if (readAscii(0, 4) != 'RIFF' || readAscii(8, 4) != 'WAVE') {
    throw StateError('Audio export expected RIFF/WAVE audio at $path.');
  }

  final channelCount = readUint16(22);
  final sampleRate = readUint32(24);
  final bitsPerSample = readUint16(34);
  final pcmBytes = Uint8List.sublistView(bytes, 44);

  return _DecodedWavFile(
    sampleRate: sampleRate,
    channelCount: channelCount,
    bitsPerSample: bitsPerSample,
    pcmBytes: pcmBytes,
  );
}

Map<String, Object?> _buildPronunciationSummary(
  List<ExportedAudioChunk> chunks,
) {
  final artifacts = chunks
      .expand((chunk) => chunk.pronunciationArtifacts)
      .toList(growable: false);

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

Uint8List _buildWavFile({
  required int sampleRate,
  required int channelCount,
  required int bitsPerSample,
  required List<Uint8List> pcmFrames,
  required int totalPcmLength,
}) {
  final bytesPerSample = bitsPerSample ~/ 8;
  final byteRate = sampleRate * channelCount * bytesPerSample;
  final blockAlign = channelCount * bytesPerSample;
  final output = BytesBuilder(copy: false);

  void writeAscii(String text) => output.add(ascii.encode(text));
  void writeUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    output.add(data.buffer.asUint8List());
  }

  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    output.add(data.buffer.asUint8List());
  }

  writeAscii('RIFF');
  writeUint32(36 + totalPcmLength);
  writeAscii('WAVE');
  writeAscii('fmt ');
  writeUint32(16);
  writeUint16(1);
  writeUint16(channelCount);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bitsPerSample);
  writeAscii('data');
  writeUint32(totalPcmLength);

  for (final frame in pcmFrames) {
    output.add(frame);
  }

  return output.takeBytes();
}
