import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';

/// Packet playback resets the native position for each WAV. Record movement
/// across distinct queued files; no individual packet must be 500ms long.
class NativePlaybackPositionProbe {
  NativePlaybackPositionProbe(this.player);
  final AudioPlayer player;
  final Map<String, int> _maximumBySource = {};
  int maxPositionMs = 0;
  bool overflow = false;
  int get sampledPositionTotalMs =>
      _maximumBySource.values.fold(0, (sum, value) => sum + value);

  void sample(Duration position) {
    if (!player.playing) return;
    maxPositionMs = math.max(maxPositionMs, position.inMilliseconds);
    final sources = player.sequence;
    final index = player.currentIndex;
    if (index == null || index < 0 || index >= sources.length) return;
    final source = sources[index];
    if (source is! UriAudioSource || source.uri.scheme != 'file') return;
    final path = source.uri.toString();
    if (!_maximumBySource.containsKey(path) &&
        _maximumBySource.length >= 2048) {
      overflow = true;
      return;
    }
    _maximumBySource[path] = math.max(
      _maximumBySource[path] ?? 0,
      position.inMilliseconds,
    );
  }

  Map<String, Object?> toMap() => {
    'sampledSourceCount': _maximumBySource.length,
    'sampledSourcePositionTotalMs': sampledPositionTotalMs,
    'maxNativePositionMs': maxPositionMs,
    'overflow': overflow,
    'scope':
        'Observed maximum native positions per distinct queued local WAV; '
        'not emitted duration. Exact captured waveform comparison is required.',
  };
}
