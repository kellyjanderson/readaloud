// Off-by-default native queue diagnosis, read only after playback measurement.
// The native plugin owns its bounded ring. This consumer neither schedules nor
// mutates playback and does not infer emitted speech from native queue state.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

Future<Map<String, Object?>?> readNativeQueueBoundaryAudit() async {
  if (Platform.environment['READALOUD_QUEUE_BOUNDARY_AUDIT'] != '1') return null;
  final reply = await const MethodChannel('com.ryanheise.just_audio.methods')
      .invokeMapMethod<String, Object?>('readAloudQueueBoundaryAudit')
      .timeout(const Duration(seconds: 2));
  if (reply == null ||
      reply['schema'] != 'readaloud-native-queue-boundary-audit-v1' ||
      reply['enabled'] != true) {
    throw StateError('Native queue boundary audit missing or disabled.');
  }
  final players = reply['players'];
  if (players is! List || players.length > 8) {
    throw StateError('Native boundary player bound exceeded.');
  }
  for (final player in players) {
    if (player is! Map ||
        player['events'] is! List ||
        (player['events'] as List).length > 2048) {
      throw StateError('Invalid or oversized native boundary event ring.');
    }
  }
  if (utf8.encode(jsonEncode(reply)).length > 8 * 1024 * 1024) {
    throw StateError('Native boundary receipt exceeds 8 MiB.');
  }
  return reply;
}
