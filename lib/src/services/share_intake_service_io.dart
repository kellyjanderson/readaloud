import 'dart:io';

import 'package:flutter/services.dart';
import 'package:share_intent_package/share_intent_package.dart';

import 'share_intake_service.dart';

class _IoShareIntakeService implements ShareIntakeService {
  bool get _isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  @override
  Future<SharedIntake?> getInitialShare() async {
    if (!_isSupportedPlatform) {
      return null;
    }

    try {
      final shared = await ShareIntentPackage.instance.getInitialSharing();
      if (shared == null || !shared.hasContent) {
        return null;
      }
      return _map(shared);
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<SharedIntake> getMediaStream() {
    if (!_isSupportedPlatform) {
      return const Stream<SharedIntake>.empty();
    }

    return ShareIntentPackage.instance
        .getMediaStream()
        .map(_map)
        .where((shared) => shared.hasContent)
        .handleError((_) {});
  }

  @override
  Future<void> clearSharedData() async {
    if (!_isSupportedPlatform) {
      return;
    }

    try {
      await ShareIntentPackage.instance.reset();
    } on MissingPluginException {
      // Plugin is not present in the current build.
    } catch (_) {
      // Shared content was already cleared or unavailable.
    }
  }
}

SharedIntake _map(SharedData shared) {
  return SharedIntake(
    text: shared.text,
    filePaths: shared.filePaths,
    mimeType: shared.mimeType,
  );
}

ShareIntakeService createShareIntakeServiceImpl() => _IoShareIntakeService();
