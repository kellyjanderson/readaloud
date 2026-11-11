/// One immutable PCM file within a still-incomplete native synthesis scene.
/// Source words belong to the parent scene, never to individual packets.
class SpeechAudioPacket {
  SpeechAudioPacket({
    required this.sessionId,
    required this.generationId,
    required this.chunkId,
    required this.audioPath,
    required this.packetIndex,
    required this.frameStart,
    required this.frameCount,
    required this.sampleRate,
    this.channels = 1,
    this.bitsPerSample = 16,
  }) {
    if (sessionId.isEmpty ||
        generationId.isEmpty ||
        chunkId.isEmpty ||
        audioPath.isEmpty ||
        packetIndex < 0 ||
        packetIndex >= maxPackets ||
        frameStart < 0 ||
        frameCount <= 0 ||
        sampleRate <= 0 ||
        sampleRate > 192000 ||
        frameEnd > sampleRate * maxSceneSeconds ||
        channels != 1 ||
        bitsPerSample != 16) {
      throw const FormatException('Invalid native audio packet.');
    }
  }

  static const maxPackets = 2048;
  static const maxSceneSeconds = 600;
  final String sessionId;
  final String generationId;
  final String chunkId;
  final String audioPath;
  final int packetIndex;

  /// Offset in the raw parent scene's PCM, before boundary onset trimming.
  final int frameStart;
  final int frameCount;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  int get frameEnd => frameStart + frameCount;
  Duration get duration => Duration(
    microseconds: (frameCount * Duration.microsecondsPerSecond ~/ sampleRate),
  );

  Map<String, Object?> toMap() => {
    'sessionId': sessionId,
    'generationId': generationId,
    'chunkId': chunkId,
    'audioPath': audioPath,
    'packetIndex': packetIndex,
    'frameStart': frameStart,
    'frameCount': frameCount,
    'sampleRate': sampleRate,
    'channels': channels,
    'bitsPerSample': bitsPerSample,
  };

  factory SpeechAudioPacket.fromMap(Map<String, Object?> map) {
    String string(String key) {
      final value = map[key];
      if (value is! String) throw FormatException('Missing packet $key.');
      return value;
    }

    int integer(String key) {
      final value = map[key];
      if (value is! int) throw FormatException('Missing packet $key.');
      return value;
    }

    return SpeechAudioPacket(
      sessionId: string('sessionId'),
      generationId: string('generationId'),
      chunkId: string('chunkId'),
      audioPath: string('audioPath'),
      packetIndex: integer('packetIndex'),
      frameStart: integer('frameStart'),
      frameCount: integer('frameCount'),
      sampleRate: integer('sampleRate'),
      channels: integer('channels'),
      bitsPerSample: integer('bitsPerSample'),
    );
  }
}
