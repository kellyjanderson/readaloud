import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import '../models/voice_profile.dart';
import 'kokoro_voice_catalog.dart';
import 'kokoro_voice_repository.dart';
import 'tts_engine.dart';

const String _voiceArchiveUrl =
    'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin';

class KokoroVoiceManager {
  KokoroVoiceManager({
    required this.voiceRepository,
    required this.cacheDirectory,
  });

  final KokoroVoiceRepository voiceRepository;
  final String cacheDirectory;

  void Function()? _onChanged;
  final Map<String, double?> _downloadProgress = <String, double?>{};
  final Map<String, String?> _downloadMessages = <String, String?>{};

  set onChanged(void Function()? callback) => _onChanged = callback;

  List<VoiceLibraryEntry> get voiceLibrary {
    return KokoroVoiceCatalog.allProfiles
        .map((voice) {
          final voiceId = voice.id;
          final isBundled = KokoroVoiceCatalog.isBundled(voiceId);
          final isInstalled = voiceRepository.isInstalled(voiceId);
          final progress = _downloadProgress[voiceId];
          final isDownloading = progress != null;
          final statusMessage =
              _downloadMessages[voiceId] ??
              (isInstalled
                  ? (isBundled ? 'Included with the app' : 'Installed locally')
                  : (isBundled
                        ? 'Ready to install from the bundled starter set'
                        : 'Available as an on-demand download'));

          return VoiceLibraryEntry(
            voice: voice,
            isBundled: isBundled,
            isInstalled: isInstalled,
            isDownloading: isDownloading,
            progress: progress,
            statusMessage: statusMessage,
          );
        })
        .toList(growable: false);
  }

  Future<void> initialize() async {
    await Directory(voiceRepository.voicesDirectory).create(recursive: true);
    await Directory(cacheDirectory).create(recursive: true);
    await _seedBundledVoices();
    await _seedLegacyArchiveCache();
    _notifyChanged();
  }

  Future<List<VoiceProfile>> loadInstalledVoices() {
    return voiceRepository.loadInstalledVoiceProfiles();
  }

  Future<void> installVoice(String voiceId) async {
    if (voiceRepository.isInstalled(voiceId)) {
      return;
    }

    try {
      _setDownloadState(
        voiceId,
        progress: 0,
        message: KokoroVoiceCatalog.isBundled(voiceId)
            ? 'Installing bundled voice...'
            : 'Preparing voice download...',
      );

      if (KokoroVoiceCatalog.isBundled(voiceId)) {
        await _installBundledVoice(voiceId);
      } else {
        await _installVoiceFromArchive(voiceId);
      }

      _clearDownloadState(voiceId);
      _notifyChanged();
    } catch (error) {
      _downloadProgress.remove(voiceId);
      _downloadMessages[voiceId] = 'Voice install failed: $error';
      _notifyChanged();
      rethrow;
    }
  }

  Future<void> _seedBundledVoices() async {
    for (final voiceId in KokoroVoiceCatalog.bundledVoiceIds) {
      if (voiceRepository.isInstalled(voiceId)) {
        continue;
      }

      final assetData = await rootBundle.load(
        KokoroVoiceCatalog.bundledAssetPath(voiceId),
      );
      await voiceRepository.storeVoiceBytes(
        voiceId,
        assetData.buffer.asUint8List(
          assetData.offsetInBytes,
          assetData.lengthInBytes,
        ),
      );
    }
  }

  Future<void> _installBundledVoice(String voiceId) async {
    final assetData = await rootBundle.load(
      KokoroVoiceCatalog.bundledAssetPath(voiceId),
    );
    await voiceRepository.storeVoiceBytes(
      voiceId,
      assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      ),
    );
  }

  Future<void> _installVoiceFromArchive(String voiceId) async {
    final archiveFile = await _resolveVoiceArchiveCache(voiceId);
    _setDownloadState(
      voiceId,
      progress: 0.98,
      message: 'Installing voice locally...',
    );

    final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
    final file = archive.find('$voiceId.npy');
    if (file == null || !file.isFile) {
      throw StateError('Voice "$voiceId" is missing from the Kokoro archive.');
    }

    final bytes = file.readBytes();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Voice "$voiceId" could not be extracted.');
    }

    await voiceRepository.storeVoiceBytes(voiceId, Uint8List.fromList(bytes));
  }

  Future<File> _resolveVoiceArchiveCache(String voiceId) async {
    final cacheFile = File(
      '$cacheDirectory${Platform.pathSeparator}voices-v1.0.bin',
    );
    if (await cacheFile.exists() && await cacheFile.length() > 0) {
      return cacheFile;
    }

    final legacyArchive = _legacyArchiveFile();
    if (legacyArchive != null && await legacyArchive.exists()) {
      await legacyArchive.copy(cacheFile.path);
      return cacheFile;
    }

    await _downloadVoiceArchive(cacheFile, voiceId);
    return cacheFile;
  }

  Future<void> _downloadVoiceArchive(File destination, String voiceId) async {
    final client = HttpClient();
    final temporaryFile = File('${destination.path}.download');

    try {
      final request = await client.getUrl(Uri.parse(_voiceArchiveUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'HTTP ${response.statusCode} while downloading the voice library',
          uri: Uri.parse(_voiceArchiveUrl),
        );
      }

      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      await temporaryFile.parent.create(recursive: true);

      final sink = temporaryFile.openWrite();
      try {
        final totalBytes = response.contentLength;
        var receivedBytes = 0;
        await for (final chunk in response) {
          sink.add(chunk);
          receivedBytes += chunk.length;

          final progress = totalBytes > 0
              ? (receivedBytes / totalBytes).clamp(0.0, 0.96)
              : null;
          _setDownloadState(
            voiceId,
            progress: progress,
            message: 'Downloading voice package...',
          );
        }
      } finally {
        await sink.close();
      }

      if (await destination.exists()) {
        await destination.delete();
      }
      await temporaryFile.rename(destination.path);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _seedLegacyArchiveCache() async {
    final cacheFile = File(
      '$cacheDirectory${Platform.pathSeparator}voices-v1.0.bin',
    );
    if (await cacheFile.exists() && await cacheFile.length() > 0) {
      return;
    }

    final legacyArchive = _legacyArchiveFile();
    if (legacyArchive != null && await legacyArchive.exists()) {
      await cacheFile.parent.create(recursive: true);
      await legacyArchive.copy(cacheFile.path);
    }
  }

  File? _legacyArchiveFile() {
    final homeDirectory =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (homeDirectory == null || homeDirectory.isEmpty) {
      return null;
    }

    return File(
      <String>[
        homeDirectory,
        '.read-aloud',
        'kokoro-runtime',
        'models',
        'voices-v1.0.bin',
      ].join(Platform.pathSeparator),
    );
  }

  void _setDownloadState(
    String voiceId, {
    required double? progress,
    required String message,
  }) {
    _downloadProgress[voiceId] = progress;
    _downloadMessages[voiceId] = message;
    _notifyChanged();
  }

  void _clearDownloadState(String voiceId) {
    _downloadProgress.remove(voiceId);
    _downloadMessages.remove(voiceId);
  }

  void _notifyChanged() {
    _onChanged?.call();
  }
}
