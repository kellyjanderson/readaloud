import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

class WavAnalysis {
  const WavAnalysis({
    required this.sampleRate,
    required this.channelCount,
    required this.bitsPerSample,
    required this.frameCount,
    required this.duration,
    required this.wavSha256,
    required this.pcmSha256,
    required this.peakAbsoluteAmplitude,
    required this.rmsAmplitude,
    required this.envelopeBins,
  });

  final int sampleRate;
  final int channelCount;
  final int bitsPerSample;
  final int frameCount;
  final Duration duration;
  final String wavSha256;
  final String pcmSha256;
  final double peakAbsoluteAmplitude;
  final double rmsAmplitude;
  final List<double> envelopeBins;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sampleRate': sampleRate,
      'channelCount': channelCount,
      'bitsPerSample': bitsPerSample,
      'frameCount': frameCount,
      'durationMillis': duration.inMilliseconds,
      'wavSha256': wavSha256,
      'pcmSha256': pcmSha256,
      'peakAbsoluteAmplitude': peakAbsoluteAmplitude,
      'rmsAmplitude': rmsAmplitude,
      'envelopeBins': envelopeBins,
    };
  }

  factory WavAnalysis.fromMap(Map<String, Object?> map) {
    return WavAnalysis(
      sampleRate: (map['sampleRate']! as num).toInt(),
      channelCount: (map['channelCount']! as num).toInt(),
      bitsPerSample: (map['bitsPerSample']! as num).toInt(),
      frameCount: (map['frameCount']! as num).toInt(),
      duration: Duration(milliseconds: (map['durationMillis']! as num).toInt()),
      wavSha256: map['wavSha256']! as String,
      pcmSha256: map['pcmSha256']! as String,
      peakAbsoluteAmplitude:
          (map['peakAbsoluteAmplitude']! as num).toDouble(),
      rmsAmplitude: (map['rmsAmplitude']! as num).toDouble(),
      envelopeBins: (map['envelopeBins']! as List<Object?>)
          .map((value) => (value! as num).toDouble())
          .toList(growable: false),
    );
  }
}

class WavComparison {
  const WavComparison({
    required this.identicalPcm,
    required this.identicalWav,
    required this.meanEnvelopeDelta,
  });

  final bool identicalPcm;
  final bool identicalWav;
  final double meanEnvelopeDelta;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'identicalPcm': identicalPcm,
      'identicalWav': identicalWav,
      'meanEnvelopeDelta': meanEnvelopeDelta,
    };
  }
}

class WavAnalysisService {
  const WavAnalysisService();

  WavAnalysis analyzeBytes(Uint8List wavBytes, {int envelopeBinCount = 64}) {
    if (wavBytes.length < 44) {
      throw StateError('WAV analysis requires a valid RIFF/WAVE file.');
    }

    final riffHeader = ascii.decode(wavBytes.sublist(0, 4));
    final waveHeader = ascii.decode(wavBytes.sublist(8, 12));
    if (riffHeader != 'RIFF' || waveHeader != 'WAVE') {
      throw StateError('WAV analysis requires a RIFF/WAVE file.');
    }

    final byteData = ByteData.sublistView(wavBytes);
    final channelCount = byteData.getUint16(22, Endian.little);
    final sampleRate = byteData.getUint32(24, Endian.little);
    final bitsPerSample = byteData.getUint16(34, Endian.little);
    if (bitsPerSample != 16) {
      throw StateError('WAV analysis currently supports only 16-bit PCM.');
    }

    final dataRange = _findDataChunk(byteData, wavBytes.length);
    final pcmBytes = Uint8List.sublistView(
      wavBytes,
      dataRange.start,
      dataRange.end,
    );
    final sampleCount = pcmBytes.length ~/ Int16List.bytesPerElement;
    final frameCount = channelCount == 0 ? 0 : sampleCount ~/ channelCount;
    final samples = Int16List.view(
      pcmBytes.buffer,
      pcmBytes.offsetInBytes,
      sampleCount,
    );

    var peak = 0.0;
    var sumSquares = 0.0;
    for (final sample in samples) {
      final normalized = sample.abs() / 32767.0;
      if (normalized > peak) {
        peak = normalized;
      }
      sumSquares += normalized * normalized;
    }
    final rms = samples.isEmpty ? 0.0 : math.sqrt(sumSquares / samples.length);

    return WavAnalysis(
      sampleRate: sampleRate,
      channelCount: channelCount,
      bitsPerSample: bitsPerSample,
      frameCount: frameCount,
      duration: Duration(
        microseconds: sampleRate == 0
            ? 0
            : ((frameCount * Duration.microsecondsPerSecond) / sampleRate)
                  .round(),
      ),
      wavSha256: crypto.sha256.convert(wavBytes).toString(),
      pcmSha256: crypto.sha256.convert(pcmBytes).toString(),
      peakAbsoluteAmplitude: peak,
      rmsAmplitude: rms,
      envelopeBins: _buildEnvelope(samples, envelopeBinCount),
    );
  }

  WavComparison compare(WavAnalysis baseline, WavAnalysis current) {
    final maxBins = math.max(
      baseline.envelopeBins.length,
      current.envelopeBins.length,
    );
    if (maxBins == 0) {
      return WavComparison(
        identicalPcm: baseline.pcmSha256 == current.pcmSha256,
        identicalWav: baseline.wavSha256 == current.wavSha256,
        meanEnvelopeDelta: 0.0,
      );
    }

    var totalDelta = 0.0;
    for (var i = 0; i < maxBins; i += 1) {
      final left = i < baseline.envelopeBins.length
          ? baseline.envelopeBins[i]
          : 0.0;
      final right = i < current.envelopeBins.length
          ? current.envelopeBins[i]
          : 0.0;
      totalDelta += (left - right).abs();
    }

    return WavComparison(
      identicalPcm: baseline.pcmSha256 == current.pcmSha256,
      identicalWav: baseline.wavSha256 == current.wavSha256,
      meanEnvelopeDelta: totalDelta / maxBins,
    );
  }
}

List<double> _buildEnvelope(Int16List samples, int envelopeBinCount) {
  if (samples.isEmpty || envelopeBinCount <= 0) {
    return const <double>[];
  }

  final bins = List<double>.filled(envelopeBinCount, 0.0, growable: false);
  final counts = List<int>.filled(envelopeBinCount, 0, growable: false);
  for (var i = 0; i < samples.length; i += 1) {
    final binIndex = (i * envelopeBinCount) ~/ samples.length;
    final clampedIndex = binIndex >= envelopeBinCount
        ? envelopeBinCount - 1
        : binIndex;
    bins[clampedIndex] += samples[i].abs() / 32767.0;
    counts[clampedIndex] += 1;
  }

  for (var i = 0; i < bins.length; i += 1) {
    if (counts[i] > 0) {
      bins[i] /= counts[i];
    }
  }
  return bins;
}

({int start, int end}) _findDataChunk(ByteData data, int totalLength) {
  var offset = 12;
  while (offset + 8 <= totalLength) {
    final chunkId = ascii.decode(data.buffer.asUint8List(offset, 4));
    final chunkLength = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    final chunkEnd = chunkStart + chunkLength;
    if (chunkEnd > totalLength) {
      break;
    }
    if (chunkId == 'data') {
      return (start: chunkStart, end: chunkEnd);
    }
    offset = chunkEnd + (chunkLength.isOdd ? 1 : 0);
  }
  throw StateError('WAV analysis could not find a data chunk.');
}
