import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';

import '../models/voice_profile.dart';
import 'kokoro_voice_catalog.dart';

class KokoroVoiceRepository {
  KokoroVoiceRepository({required this.voicesDirectory});

  final String voicesDirectory;
  final Map<String, Voice> _voiceCache = <String, Voice>{};

  Future<List<VoiceProfile>> loadInstalledVoiceProfiles() async {
    final directory = Directory(voicesDirectory);
    if (!await directory.exists()) {
      return const <VoiceProfile>[];
    }

    final installedIds = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.npy'))
        .map((entity) => entity.path.split(Platform.pathSeparator).last)
        .map((name) => name.replaceFirst('.npy', ''))
        .toList();

    return KokoroVoiceCatalog.profilesForIds(installedIds);
  }

  bool isInstalled(String voiceId) {
    return File(_voicePathForId(voiceId)).existsSync();
  }

  Future<void> storeVoiceBytes(String voiceId, Uint8List bytes) async {
    final file = File(_voicePathForId(voiceId));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    _voiceCache.remove(voiceId);
  }

  Future<Voice> loadVoice(String voiceId) async {
    final cached = _voiceCache[voiceId];
    if (cached != null) {
      return cached;
    }

    final file = File(_voicePathForId(voiceId));
    if (!await file.exists()) {
      throw StateError('Kokoro voice "$voiceId" is not installed.');
    }

    final bytes = await file.readAsBytes();
    final voiceProfile = KokoroVoiceCatalog.profileForId(voiceId);
    final voice = Voice(
      id: voiceId,
      name: voiceProfile.label,
      styleVectors: _parseStyleVectors(bytes),
      languageCode: KokoroVoiceCatalog.languageTagForVoice(voiceId),
      gender: KokoroVoiceCatalog.genderForVoice(voiceId),
    );
    _voiceCache[voiceId] = voice;
    return voice;
  }

  String _voicePathForId(String voiceId) {
    return '$voicesDirectory${Platform.pathSeparator}$voiceId.npy';
  }
}

List<Float32List> _parseStyleVectors(Uint8List bytes) {
  final header = _parseNpyHeader(bytes);
  if (header.descriptor != '<f4') {
    throw FormatException(
      'Unsupported Kokoro voice data type: ${header.descriptor}',
    );
  }

  if (header.shape.isEmpty) {
    throw const FormatException('Kokoro voice archive has an empty shape.');
  }

  final vectorCount = header.shape.first;
  final vectorLength = header.shape
      .skip(1)
      .fold<int>(1, (product, dimension) => product * dimension);
  final totalValues = vectorCount * vectorLength;
  final dataBytes = bytes.length - header.dataOffset;
  if (dataBytes != totalValues * Float32List.bytesPerElement) {
    throw FormatException(
      'Kokoro voice archive size does not match its header shape.',
    );
  }

  final byteData = ByteData.sublistView(bytes, header.dataOffset);
  final vectors = List<Float32List>.generate(vectorCount, (index) {
    final vector = Float32List(vectorLength);
    final baseIndex = index * vectorLength;
    for (var elementIndex = 0; elementIndex < vectorLength; elementIndex += 1) {
      final offset = (baseIndex + elementIndex) * Float32List.bytesPerElement;
      vector[elementIndex] = byteData.getFloat32(offset, Endian.little);
    }
    return vector;
  });

  return vectors;
}

_NpyHeader _parseNpyHeader(Uint8List bytes) {
  if (bytes.length < 12 ||
      bytes[0] != 0x93 ||
      ascii.decode(bytes.sublist(1, 6)) != 'NUMPY') {
    throw const FormatException('Kokoro voice archive is not a NumPy array.');
  }

  final major = bytes[6];
  final byteData = ByteData.sublistView(bytes);
  final headerLength = switch (major) {
    1 => byteData.getUint16(8, Endian.little),
    2 || 3 => byteData.getUint32(8, Endian.little),
    _ => throw FormatException('Unsupported NumPy version: $major'),
  };
  final headerOffset = major == 1 ? 10 : 12;
  final dataOffset = headerOffset + headerLength;

  final headerText = ascii
      .decode(bytes.sublist(headerOffset, dataOffset))
      .trimRight();
  final descriptorMatch = RegExp(
    r"'descr':\s*'([^']+)'",
  ).firstMatch(headerText);
  final shapeMatch = RegExp(r"'shape':\s*\(([^)]*)\)").firstMatch(headerText);
  if (descriptorMatch == null || shapeMatch == null) {
    throw const FormatException('Kokoro voice array header is malformed.');
  }

  final shape = shapeMatch
      .group(1)!
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .map(int.parse)
      .toList(growable: false);

  return _NpyHeader(
    descriptor: descriptorMatch.group(1)!,
    shape: shape,
    dataOffset: dataOffset,
  );
}

class _NpyHeader {
  const _NpyHeader({
    required this.descriptor,
    required this.shape,
    required this.dataOffset,
  });

  final String descriptor;
  final List<int> shape;
  final int dataOffset;
}
