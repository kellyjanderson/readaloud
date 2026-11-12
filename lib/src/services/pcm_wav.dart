import 'dart:typed_data';

/// Integer, interleaved little-endian PCM supported by these WAV consumers.
/// Consumer-specific restrictions (for example PCM16 analysis) stay at the caller.
class PcmFormat {
  PcmFormat({
    required this.sampleRate,
    required this.channelCount,
    required this.bitsPerSample,
  }) {
    if (sampleRate <= 0 ||
        sampleRate > 0xffffffff ||
        channelCount <= 0 ||
        channelCount > 0xffff ||
        !const [8, 16, 24, 32].contains(bitsPerSample) ||
        blockAlign > 0xffff ||
        byteRate > 0xffffffff) {
      throw const FormatException('Unsupported or inconsistent PCM format.');
    }
  }

  final int sampleRate;
  final int channelCount;
  final int bitsPerSample;
  int get blockAlign => channelCount * (bitsPerSample ~/ 8);
  int get byteRate => sampleRate * blockAlign;

  bool matches(PcmFormat other) =>
      sampleRate == other.sampleRate &&
      channelCount == other.channelCount &&
      bitsPerSample == other.bitsPerSample;
}

/// One validated fmt/data pair. No audio bytes or chunk list are retained.
class PcmWavLayout {
  const PcmWavLayout({
    required this.format,
    required this.dataOffset,
    required this.dataLength,
  });

  final PcmFormat format;
  final int dataOffset;
  final int dataLength;
  int get frameCount => dataLength ~/ format.blockAlign;
}

/// Shared structural state machine for synchronous and asynchronous adapters.
/// Each request is only a RIFF header, chunk header or the required fmt prefix.
/// Callers supply exactly that range, skipping payloads and extended fmt bytes.
class PcmWavScan {
  PcmWavScan(this.fileLength) {
    if (fileLength < 12) {
      throw const FormatException('Truncated WAV header.');
    }
  }

  final int fileLength;
  ({int offset, int length})? _nextRead = (offset: 0, length: 12);
  ({int offset, int length})? get nextRead => _nextRead;
  var _stage = _ScanStage.riff;
  var _nextChunk = 12;
  PcmFormat? _format;
  int? _dataOffset;
  int? _dataLength;

  void accept(Uint8List bytes) {
    final request = _nextRead;
    if (request == null) throw StateError('WAV scan is already complete.');
    if (bytes.length != request.length) {
      throw const FormatException('Truncated WAV header.');
    }
    final data = ByteData.sublistView(bytes);
    switch (_stage) {
      case _ScanStage.riff:
        if (!_tag(bytes, 'RIFF') ||
            !_tag(Uint8List.sublistView(bytes, 8), 'WAVE') ||
            data.getUint32(4, Endian.little) + 8 != fileLength) {
          throw const FormatException('Invalid RIFF/WAVE length or signature.');
        }
        _advance();
      case _ScanStage.chunk:
        final length = data.getUint32(4, Endian.little);
        final payloadOffset = request.offset + 8;
        _nextChunk = payloadOffset + length + length % 2;
        if (_nextChunk > fileLength) {
          throw const FormatException('Truncated WAV section or padding.');
        }
        if (_tag(bytes, 'fmt ')) {
          if (_format != null || length < 16) {
            throw const FormatException('Invalid WAV format section.');
          }
          _stage = _ScanStage.format;
          _nextRead = (offset: payloadOffset, length: 16);
        } else {
          if (_tag(bytes, 'data')) {
            if (_dataOffset != null) {
              throw const FormatException('Multiple WAV data sections.');
            }
            _dataOffset = payloadOffset;
            _dataLength = length;
          }
          _advance();
        }
      case _ScanStage.format:
        if (data.getUint16(0, Endian.little) != 1) {
          throw const FormatException('Only integer PCM WAV is supported.');
        }
        final format = PcmFormat(
          sampleRate: data.getUint32(4, Endian.little),
          channelCount: data.getUint16(2, Endian.little),
          bitsPerSample: data.getUint16(14, Endian.little),
        );
        if (data.getUint16(12, Endian.little) != format.blockAlign ||
            data.getUint32(8, Endian.little) != format.byteRate) {
          throw const FormatException(
            'Inconsistent PCM alignment or byte rate.',
          );
        }
        _format = format;
        _advance();
    }
  }

  void _advance() {
    if (_nextChunk == fileLength) {
      _nextRead = null;
    } else {
      if (_nextChunk + 8 > fileLength) {
        throw const FormatException('Truncated WAV section header.');
      }
      _stage = _ScanStage.chunk;
      _nextRead = (offset: _nextChunk, length: 8);
    }
  }

  PcmWavLayout finish() {
    if (_nextRead != null) throw StateError('WAV scan is incomplete.');
    final format = _format;
    final offset = _dataOffset;
    final length = _dataLength;
    if (format == null || offset == null || length == null) {
      throw const FormatException('Missing PCM format or data.');
    }
    if (length % format.blockAlign != 0) {
      throw const FormatException('Unaligned PCM data.');
    }
    return PcmWavLayout(format: format, dataOffset: offset, dataLength: length);
  }
}

enum _ScanStage { riff, chunk, format }

bool _tag(Uint8List bytes, String tag) =>
    bytes[0] == tag.codeUnitAt(0) &&
    bytes[1] == tag.codeUnitAt(1) &&
    bytes[2] == tag.codeUnitAt(2) &&
    bytes[3] == tag.codeUnitAt(3);

PcmWavLayout decodePcmWav(Uint8List bytes) {
  final scan = PcmWavScan(bytes.length);
  while (scan.nextRead != null) {
    final request = scan.nextRead!;
    scan.accept(
      Uint8List.sublistView(
        bytes,
        request.offset,
        request.offset + request.length,
      ),
    );
  }
  return scan.finish();
}

/// Canonical 44-byte header. The caller writes [dataLength] payload bytes and,
/// when odd, one final pad byte. Padding is included only in the RIFF size.
Uint8List encodePcmWavHeader(PcmFormat format, int dataLength) {
  // Bound before addition: native Dart int64 arithmetic can otherwise wrap.
  if (dataLength < 0 ||
      dataLength > 0xffffffff - 36 ||
      dataLength % format.blockAlign != 0 ||
      36 + dataLength + dataLength % 2 > 0xffffffff) {
    throw const FormatException('Unaligned PCM data or RIFF size limit.');
  }
  final bytes = Uint8List(44);
  final data = ByteData.sublistView(bytes);
  void tag(int offset, String value) =>
      bytes.setRange(offset, offset + 4, value.codeUnits);
  tag(0, 'RIFF');
  data.setUint32(4, 36 + dataLength + dataLength % 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, format.channelCount, Endian.little);
  data.setUint32(24, format.sampleRate, Endian.little);
  data.setUint32(28, format.byteRate, Endian.little);
  data.setUint16(32, format.blockAlign, Endian.little);
  data.setUint16(34, format.bitsPerSample, Endian.little);
  tag(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  return bytes;
}
