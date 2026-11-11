import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../tools/radoc_first_load_smoke.dart';

void main() {
  test('queued WAV evidence crosses a real isolate and preserves bytes', () async {
    final root = await Directory.systemTemp.createTemp('queued-evidence-test-');
    try {
      final bytes = ByteData(48);
      void tag(int offset, String value) {
        for (var i = 0; i < value.length; i++) {
          bytes.setUint8(offset + i, value.codeUnitAt(i));
        }
      }
      tag(0, 'RIFF');
      bytes.setUint32(4, 40, Endian.little);
      tag(8, 'WAVE');
      tag(12, 'fmt ');
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little);
      bytes.setUint16(22, 1, Endian.little);
      bytes.setUint32(24, 44100, Endian.little);
      bytes.setUint32(28, 88200, Endian.little);
      bytes.setUint16(32, 2, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      tag(36, 'data');
      bytes.setUint32(40, 4, Endian.little);
      bytes.setInt16(44, -1200, Endian.little);
      bytes.setInt16(46, 800, Endian.little);
      final source = File('${root.path}/source.wav');
      await source.writeAsBytes(bytes.buffer.asUint8List());
      final target = '${root.path}/copy.wav';
      final receipt = await copyQueuedAudioEvidence(source.path, target);
      expect(receipt['peakPcm16'], 1200);
      expect(receipt['sampleRate'], 44100);
      expect(receipt['pcmBytes'], 4);
      expect(await File(target).readAsBytes(), await source.readAsBytes());
    } finally {
      await root.delete(recursive: true);
    }
  });
}
