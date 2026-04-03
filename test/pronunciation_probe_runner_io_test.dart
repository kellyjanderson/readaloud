import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/pronunciation_probe_runner_io.dart';
import 'package:read_aloud/src/services/wav_analysis_service.dart';

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
