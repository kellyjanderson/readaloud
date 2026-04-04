enum ReaderPlaybackPrimaryState {
  idle,
  bufferingFirstChunk,
  playing,
  paused,
  completed,
  failed,
}

class SpokenChunkRecord {
  const SpokenChunkRecord({
    required this.chunkId,
    required this.documentId,
    required this.segmentIds,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.wordCount,
    required this.audioDuration,
    required this.playbackOffset,
    required this.voiceId,
    required this.rate,
    required this.completed,
    this.routeId,
    this.castId,
    this.dialogueSpanId,
  });

  final String chunkId;
  final String documentId;
  final List<String> segmentIds;
  final int startWordIndex;
  final int endWordIndex;
  final int wordCount;
  final Duration audioDuration;
  final Duration playbackOffset;
  final String voiceId;
  final double rate;
  final bool completed;
  final String? routeId;
  final String? castId;
  final String? dialogueSpanId;

  SpokenChunkRecord copyWith({
    Duration? playbackOffset,
    Duration? audioDuration,
    bool? completed,
  }) {
    return SpokenChunkRecord(
      chunkId: chunkId,
      documentId: documentId,
      segmentIds: segmentIds,
      startWordIndex: startWordIndex,
      endWordIndex: endWordIndex,
      wordCount: wordCount,
      audioDuration: audioDuration ?? this.audioDuration,
      playbackOffset: playbackOffset ?? this.playbackOffset,
      voiceId: voiceId,
      rate: rate,
      completed: completed ?? this.completed,
      routeId: routeId,
      castId: castId,
      dialogueSpanId: dialogueSpanId,
    );
  }
}
