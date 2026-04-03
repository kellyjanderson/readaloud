import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/synthesis_boundary_policy.dart';

void main() {
  group('SynthesisBoundaryPolicy', () {
    test('caps initial chunk opening silence at 120ms', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-boundary-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final wavFile = File('${tempDir.path}/initial.wav');
      final sidecarFile = File('${tempDir.path}/initial.json');
      await wavFile.writeAsBytes(
        _buildWav(
          leadingSilenceMs: 240,
          speechMs: 300,
          trailingSilenceMs: 40,
        ),
      );
      await sidecarFile.writeAsString(jsonEncode(<String, dynamic>{}));

      final policy = const SynthesisBoundaryPolicy();
      final outcome = await policy.correctWavFile(
        chunkId: 'initial',
        wavFilePath: wavFile.path,
        boundaryClass: BreakClass.none,
        isInitialChunk: true,
        isResumedChunk: false,
      );

      expect(outcome.applied, isTrue);
      expect(outcome.leadingSilenceBefore, const Duration(milliseconds: 240));
      expect(outcome.leadingSilenceAfter, const Duration(milliseconds: 120));
    });

    test('retains a 20ms floor when combined join silence exceeds budget', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-boundary-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final wavFile = File('${tempDir.path}/joined.wav');
      final sidecarFile = File('${tempDir.path}/joined.json');
      await wavFile.writeAsBytes(
        _buildWav(
          leadingSilenceMs: 200,
          speechMs: 300,
          trailingSilenceMs: 60,
        ),
      );
      await sidecarFile.writeAsString(jsonEncode(<String, dynamic>{}));

      final policy = const SynthesisBoundaryPolicy();
      final outcome = await policy.correctWavFile(
        chunkId: 'joined',
        wavFilePath: wavFile.path,
        boundaryClass: BreakClass.weak,
        isInitialChunk: false,
        isResumedChunk: false,
        previousTrailingSilence: const Duration(milliseconds: 100),
      );

      expect(outcome.applied, isTrue);
      expect(outcome.leadingSilenceBefore, const Duration(milliseconds: 200));
      expect(outcome.leadingSilenceAfter, const Duration(milliseconds: 20));
      expect(outcome.joinSilenceAfter, const Duration(milliseconds: 120));
    });

    test('treats resumed chunks as fresh starts and records sidecar metadata', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-boundary-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final wavFile = File('${tempDir.path}/resumed.wav');
      final sidecarFile = File('${tempDir.path}/resumed.json');
      await wavFile.writeAsBytes(
        _buildWav(
          leadingSilenceMs: 250,
          speechMs: 280,
          trailingSilenceMs: 35,
        ),
      );
      await sidecarFile.writeAsString(jsonEncode(<String, dynamic>{}));

      final outcome = await const SynthesisBoundaryPolicy().correctWavFile(
        chunkId: 'resumed',
        wavFilePath: wavFile.path,
        boundaryClass: BreakClass.sentence,
        isInitialChunk: false,
        isResumedChunk: true,
        previousTrailingSilence: const Duration(milliseconds: 180),
      );

      expect(outcome.candidate.chunkId, 'resumed');
      expect(outcome.candidate.isResumedChunk, isTrue);
      expect(outcome.joinSilenceBefore, const Duration(milliseconds: 250));
      expect(outcome.leadingSilenceAfter, const Duration(milliseconds: 120));

      final sidecar = jsonDecode(await sidecarFile.readAsString()) as Map;
      expect(sidecar['chunkId'], 'resumed');
      expect(sidecar['boundaryClass'], BreakClass.sentence.name);
      expect(sidecar['isInitialChunk'], isFalse);
      expect(sidecar['isResumedChunk'], isTrue);
      expect(sidecar['leadingSilenceBeforeMs'], 250);
      expect(sidecar['leadingSilenceAfterMs'], 120);
      expect(sidecar['joinSilenceBeforeMs'], 250);
      expect(sidecar['joinSilenceAfterMs'], 120);
    });
  });
}

Uint8List _buildWav({
  required int leadingSilenceMs,
  required int speechMs,
  required int trailingSilenceMs,
}) {
  final leadingSamples = _msToSamples(leadingSilenceMs);
  final speechSamples = _msToSamples(speechMs);
  final trailingSamples = _msToSamples(trailingSilenceMs);
  final pcm = Int16List(leadingSamples + speechSamples + trailingSamples);

  for (var index = leadingSamples; index < leadingSamples + speechSamples; index += 1) {
    pcm[index] = 12000;
  }

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
    } else {
      buffer.setUint32(0, value, Endian.little);
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
  writeInt(sampleRate, 4);
  writeInt(sampleRate * Int16List.bytesPerElement, 4);
  writeInt(Int16List.bytesPerElement, 2);
  writeInt(16, 2);
  writeString('data');
  writeInt(dataLength, 4);
  bytes.add(pcm.buffer.asUint8List());
  return bytes.takeBytes();
}

int _msToSamples(int milliseconds) {
  return (milliseconds / 1000 * sampleRate).round();
}
