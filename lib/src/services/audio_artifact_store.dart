import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Stable canonical serialization: object order is not an identity input.
String artifactIdentity(Object? value) {
  Object? canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(v[key])};
    }
    if (v is Iterable) return v.map(canonical).toList();
    return v;
  }

  return sha256.convert(utf8.encode(jsonEncode(canonical(value)))).toString();
}

class AudioArtifact {
  const AudioArtifact(
    this.audioPath,
    this.identity,
    this.metadata,
    this.frames,
    this.sampleRate,
  );
  final String audioPath;
  final String identity;
  final Map<String, dynamic> metadata;
  final int frames;
  final int sampleRate;
  Duration get duration =>
      Duration(milliseconds: (frames * 1000 / sampleRate).round());
}

/// Immutable complete generations. Only the writer's private staging directory
/// is cleaned. Published generations are never overwritten or automatically
/// evicted, including when another writer wins the same identity concurrently.
/// This synchronous API runs in the synthesis/correction worker, never the UI.
class AudioArtifactStore {
  AudioArtifactStore(this.directory);
  final Directory directory;
  static const schema = 1;

  AudioArtifact? lookup(String identity) {
    _validateIdentity(identity);
    final bucket = Directory('${directory.path}/$identity');
    if (!bucket.existsSync()) return null;
    for (final entry in bucket.listSync(followLinks: false)) {
      if (entry is! Directory) continue;
      final artifact = _read(entry, identity);
      if (artifact != null) return artifact;
    }
    return null;
  }

  AudioArtifact publish({
    required String identity,
    required Uint8List wav,
    required Map<String, dynamic> metadata,
  }) {
    _validateIdentity(identity);
    final existing = lookup(identity);
    if (existing != null) return existing;
    final format = validateWav(wav);
    directory.createSync(recursive: true);
    final stage = directory.createTempSync('.stage-');
    try {
      final audio = File('${stage.path}/audio.wav');
      audio.writeAsBytesSync(wav, flush: true);
      final completeMetadata = <String, dynamic>{
        ...metadata,
        'artifactIdentity': identity,
        'durationMillis': format.duration.inMilliseconds,
        'frameCount': format.frames,
        'sampleRate': format.sampleRate,
      };
      final metadataBytes = utf8.encode(jsonEncode(completeMetadata));
      File(
        '${stage.path}/audio.json',
      ).writeAsBytesSync(metadataBytes, flush: true);
      File('${stage.path}/manifest.json').writeAsStringSync(
        jsonEncode({
          'schema': schema,
          'complete': true,
          'identity': identity,
          'wavBytes': wav.length,
          'wavSha256': sha256.convert(wav).toString(),
          'pcmSha256': sha256.convert(wav.sublist(44)).toString(),
          'metadataSha256': sha256.convert(metadataBytes).toString(),
          'frames': format.frames,
          'sampleRate': format.sampleRate,
        }),
        flush: true,
      );
      final bucket = Directory('${directory.path}/$identity')
        ..createSync(recursive: true);
      // Unique generation name: a corrupt/incomplete historical artifact is not
      // overwritten, and concurrent publishers cannot replace queued files.
      final name = stage.path.split(Platform.pathSeparator).last;
      final published = stage.renameSync('${bucket.path}/$name');
      return _read(published, identity) ??
          (throw StateError('Published audio failed validation.'));
    } finally {
      if (stage.existsSync()) stage.deleteSync(recursive: true);
    }
  }

  AudioArtifact? _read(Directory generation, String identity) {
    try {
      final m = jsonDecode(
        File('${generation.path}/manifest.json').readAsStringSync(),
      );
      if (m is! Map ||
          m['schema'] != schema ||
          m['complete'] != true ||
          m['identity'] != identity) {
        return null;
      }
      final wav = File('${generation.path}/audio.wav').readAsBytesSync();
      final metadataBytes = File(
        '${generation.path}/audio.json',
      ).readAsBytesSync();
      if (wav.length != m['wavBytes'] ||
          sha256.convert(wav).toString() != m['wavSha256'] ||
          sha256.convert(wav.sublist(44)).toString() != m['pcmSha256'] ||
          sha256.convert(metadataBytes).toString() != m['metadataSha256']) {
        return null;
      }
      final f = validateWav(wav);
      final metadata =
          jsonDecode(utf8.decode(metadataBytes)) as Map<String, dynamic>;
      if (m['frames'] != f.frames ||
          m['sampleRate'] != f.sampleRate ||
          metadata['artifactIdentity'] != identity ||
          metadata['frameCount'] != f.frames ||
          metadata['sampleRate'] != f.sampleRate ||
          metadata['durationMillis'] != f.duration.inMilliseconds) {
        return null;
      }
      return AudioArtifact(
        '${generation.path}/audio.wav',
        identity,
        Map.unmodifiable(metadata),
        f.frames,
        f.sampleRate,
      );
    } on Object {
      return null;
    }
  }

  static void _validateIdentity(String identity) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(identity)) {
      throw ArgumentError.value(identity, 'identity');
    }
  }

  /// Only our canonical mono PCM16 WAV format is accepted as reusable audio.
  static WavFormat validateWav(Uint8List bytes) {
    if (bytes.length <= 44 || (bytes.length - 44).isOdd) {
      throw const FormatException('Incomplete PCM WAV.');
    }
    final b = ByteData.sublistView(bytes);
    String tag(int start) => ascii.decode(bytes.sublist(start, start + 4));
    final rate = b.getUint32(24, Endian.little);
    if (tag(0) != 'RIFF' ||
        tag(8) != 'WAVE' ||
        tag(12) != 'fmt ' ||
        tag(36) != 'data' ||
        b.getUint32(4, Endian.little) != bytes.length - 8 ||
        b.getUint32(16, Endian.little) != 16 ||
        b.getUint16(20, Endian.little) != 1 ||
        b.getUint16(22, Endian.little) != 1 ||
        rate != 24000 ||
        b.getUint32(28, Endian.little) != rate * 2 ||
        b.getUint16(32, Endian.little) != 2 ||
        b.getUint16(34, Endian.little) != 16 ||
        b.getUint32(40, Endian.little) != bytes.length - 44) {
      throw const FormatException('Invalid canonical PCM WAV.');
    }
    return WavFormat((bytes.length - 44) ~/ 2, rate);
  }
}

class WavFormat {
  const WavFormat(this.frames, this.sampleRate);
  final int frames;
  final int sampleRate;
  Duration get duration =>
      Duration(milliseconds: (frames * 1000 / sampleRate).round());
}

/// Queue/export lifetime accounting. Pins never trigger deletion on release.
class AudioArtifactPins {
  static final shared = AudioArtifactPins();
  final Map<String, int> _counts = {};
  AudioArtifactPin pin(String path) {
    _counts.update(path, (n) => n + 1, ifAbsent: () => 1);
    return AudioArtifactPin._(() {
      final n = _counts[path]!;
      if (n == 1) {
        _counts.remove(path);
      } else {
        _counts[path] = n - 1;
      }
    });
  }

  int pinCount(String path) => _counts[path] ?? 0;
  bool isPinned(String path) => pinCount(path) > 0;
}

class AudioArtifactPin {
  AudioArtifactPin._(this._release);
  void Function()? _release;
  void release() {
    final release = _release;
    _release = null;
    release?.call();
  }
}
