import 'dart:typed_data';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/pronunciation_probe_runner_io.dart';
import 'package:read_aloud/src/services/wav_analysis_service.dart';

import 'pcm_wav_test.dart' show buildPcmWavFixture, malformedPcmWavFixtures;

void main() {
  group('parsePronunciationProbeCases', () {
    test('supports comments, implicit ids, and tab-separated ids', () {
      final cases = parsePronunciationProbeCases('''
# comment
John's hand.
possessive_z\tJenny's hand.

dogs_plural\tDogs bark.
''');

      expect(cases, hasLength(3));
      expect(cases[0].id, 'probe_1');
      expect(cases[0].text, "John's hand.");
      expect(cases[1].id, 'possessive_z');
      expect(cases[1].text, "Jenny's hand.");
      expect(cases[2].id, 'dogs_plural');
      expect(cases[2].text, 'Dogs bark.');
    });
  });

  group('WavAnalysisService', () {
    for (final rate in [24000, 44100, 48000]) {
      for (final dataFirst in [false, true]) {
        test(
          'PCM16 arithmetic/hash/envelope at $rate, data-first=$dataFirst',
          () {
            const samples = [-32768, 32767, 0, 16384, -8192, 1];
            final pcm = ByteData(samples.length * 2);
            for (var i = 0; i < samples.length; i++) {
              pcm.setInt16(i * 2, samples[i], Endian.little);
            }
            final bytes = buildPcmWavFixture(
              payload: pcm.buffer.asUint8List(),
              rate: rate,
              channels: 2,
              junk: true,
              extended: true,
              dataFirst: dataFirst,
            );
            final analysis = const WavAnalysisService().analyzeBytes(
              bytes,
              envelopeBinCount: 3,
            );
            expect(analysis.sampleRate, rate);
            expect(analysis.channelCount, 2);
            expect(analysis.bitsPerSample, 16);
            expect(analysis.frameCount, 3);
            expect(
              analysis.duration,
              Duration(microseconds: (3000000 / rate).round()),
            );
            expect(analysis.wavSha256, crypto.sha256.convert(bytes).toString());
            expect(
              analysis.pcmSha256,
              crypto.sha256.convert(pcm.buffer.asUint8List()).toString(),
            );
            expect(analysis.peakAbsoluteAmplitude, 32768 / 32767);
            final expectedRms = math.sqrt(
              samples.fold<double>(
                    0,
                    (total, s) => total + math.pow(s.abs() / 32767, 2),
                  ) /
                  samples.length,
            );
            expect(analysis.rmsAmplitude, closeTo(expectedRms, 1e-15));
            expect(analysis.envelopeBins, [
              (32768 / 32767 + 1) / 2,
              8192 / 32767,
              8193 / 65534,
            ]);
          },
        );
      }
    }
    for (final bits in [8, 24, 32]) {
      test('analysis retains explicit PCM16-only policy: PCM$bits', () {
        final bytes = buildPcmWavFixture(
          bits: bits,
          payload: List.filled(bits ~/ 8, 7),
        );
        expect(
          () => const WavAnalysisService().analyzeBytes(bytes),
          throwsStateError,
        );
      });
    }
    for (final entry in malformedPcmWavFixtures().entries) {
      test('analysis rejects under-validated input: ${entry.key}', () {
        expect(
          () => const WavAnalysisService().analyzeBytes(entry.value),
          throwsFormatException,
        );
      });
    }
    test('identifies identical PCM output as unchanged', () {
      final service = const WavAnalysisService();
      final baseline = service.analyzeBytes(_buildWav(<int>[100, 200, 300]));
      final current = service.analyzeBytes(_buildWav(<int>[100, 200, 300]));
      final comparison = service.compare(baseline, current);

      expect(comparison.identicalPcm, isTrue);
      expect(comparison.identicalWav, isTrue);
      expect(comparison.meanEnvelopeDelta, 0.0);
    });

    test('identifies changed PCM output as changed', () {
      final service = const WavAnalysisService();
      final baseline = service.analyzeBytes(_buildWav(<int>[100, 200, 300]));
      final current = service.analyzeBytes(_buildWav(<int>[100, 400, 700]));
      final comparison = service.compare(baseline, current);

      expect(comparison.identicalPcm, isFalse);
      expect(comparison.meanEnvelopeDelta, greaterThan(0.0));
    });
  });
}

Uint8List _buildWav(List<int> samples) {
  final pcm = Int16List.fromList(samples);
  final output = BytesBuilder(copy: false);

  void writeAscii(String text) => output.add(text.codeUnits);
  void writeUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    output.add(data.buffer.asUint8List());
  }

  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    output.add(data.buffer.asUint8List());
  }

  writeAscii('RIFF');
  writeUint32(36 + pcm.lengthInBytes);
  writeAscii('WAVE');
  writeAscii('fmt ');
  writeUint32(16);
  writeUint16(1);
  writeUint16(1);
  writeUint32(24000);
  writeUint32(24000 * 2);
  writeUint16(2);
  writeUint16(16);
  writeAscii('data');
  writeUint32(pcm.lengthInBytes);
  output.add(pcm.buffer.asUint8List());

  return output.takeBytes();
}
