import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../models/voice_profile.dart';

/// One immutable, versioned asset manifest; no synthesis or model loading here.
class MlxVoiceLibrary {
  static Future<void>? _loading;
  static List<VoiceProfile> _profiles = const [];
  static List<VoiceProfile> get profiles => _profiles;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final manifest =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/voice_library/library.json',
                ),
              )
              as Map<String, dynamic>;
      final entries = manifest['voices'] as List<dynamic>;
      if (entries.length < 30 || manifest['schema'] != 1) {
        throw StateError('The reference voice library is incomplete.');
      }
      final digests = <String>{};
      final ids = <String>{};
      final voices = <VoiceProfile>[];
      for (final item in entries.cast<Map<String, dynamic>>()) {
        final id = item['id'] as String;
        final asset = item['asset'] as String;
        final digest = item['sha256'] as String;
        if (!ids.add(id) ||
            !digests.add(digest) ||
            !RegExp(r'^library_[a-z]+$').hasMatch(id) ||
            !RegExp(r'^assets/voice_library/[a-z]+\.wav$').hasMatch(asset) ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
          throw StateError('Invalid or duplicate reference voice: $id');
        }
        voices.add(
          VoiceProfile(
            id: id,
            label: item['label'] as String,
            locale: item['locale'] as String,
            gender: item['gender'] == 'male'
                ? VoiceGender.male
                : VoiceGender.female,
            description:
                'Synthetic reference. Designed: ${item['description']}',
            metadataSource: VoiceMetadataSource.appDerived,
            rawValue: Map<String, Object?>.unmodifiable({
              ...item,
              'libraryVersion': manifest['version'],
            }),
          ),
        );
      }
      final fish =
          jsonDecode(
                await rootBundle.loadString('assets/fish_voice_library.json'),
              )
              as Map<String, dynamic>;
      for (final item
          in (fish['voices'] as List).cast<Map<String, dynamic>>()) {
        final id = item['id'] as String;
        if (!ids.add(id) || !RegExp(r'^library_fish[a-z]+$').hasMatch(id)) {
          throw StateError('Invalid Fish reference voice: $id');
        }
        voices.add(
          VoiceProfile(
            id: id,
            label: item['label'] as String,
            locale: item['locale'] as String,
            gender: item['gender'] == 'male'
                ? VoiceGender.male
                : VoiceGender.female,
            description:
                'Fish Official designed reference. ${item['description']}',
            metadataSource: VoiceMetadataSource.engineCatalog,
            rawValue: Map<String, Object?>.unmodifiable({
              ...item,
              'libraryVersion': fish['version'],
            }),
          ),
        );
      }
      _profiles = List.unmodifiable(voices);
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  static VoiceProfile voice(String id) => _profiles.firstWhere(
    (profile) => profile.id == id,
    orElse: () => throw StateError('Unknown reference voice: $id'),
  );

  /// Materialize only requested voices, in content-addressed immutable files.
  static Future<File> prepare(
    String id,
    Directory root, {
    Future<void>? cancelled,
  }) async {
    await load();
    final profile = voice(id);
    final digest = profile.rawValue['sha256'] as String;
    final remote = profile.rawValue['url'] as String?;
    final extension = remote == null ? 'wav' : 'mp3';
    final target = File('${root.path}/voice-library/$digest.$extension');
    if (await target.exists() &&
        sha256.convert(await target.readAsBytes()).toString() == digest) {
      return target;
    }
    final List<int> bytes;
    if (remote != null) {
      final uri = Uri.parse(remote);
      if (uri.scheme != 'https' || uri.host != 'platform.r2.fish.audio') {
        throw StateError('Unexpected Fish reference host.');
      }
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      if (cancelled != null) {
        cancelled.then((_) => client.close(force: true));
      }
      try {
        final response = await (await client.getUrl(
          uri,
        )).close().timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException('Voice download failed: ${response.statusCode}');
        }
        final buffer = <int>[];
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          buffer.addAll(chunk);
          if (buffer.length > 10 * 1024 * 1024) {
            throw StateError('Reference download too large');
          }
        }
        bytes = buffer;
      } finally {
        client.close(force: true);
      }
    } else {
      final data = await rootBundle.load(profile.rawValue['asset'] as String);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    if (sha256.convert(bytes).toString() != digest) {
      throw StateError('Reference voice integrity check failed: $id');
    }
    await target.parent.create(recursive: true);
    final stage = await target.parent.createTemp('.voice-');
    final staged = File('${stage.path}/reference.$extension');
    await staged.writeAsBytes(bytes, flush: true);
    try {
      await staged.rename(target.path);
    } finally {
      await stage.delete(recursive: true);
    }
    return target;
  }
}
