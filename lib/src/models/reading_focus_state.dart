enum ReadingFocusFollowMode {
  following,
  suspendedByUser,
}

class ReadingFocusState {
  const ReadingFocusState({
    this.playbackActive = false,
    this.followMode = ReadingFocusFollowMode.following,
    this.activeDisplayBlockId,
  });

  final bool playbackActive;
  final ReadingFocusFollowMode followMode;
  final String? activeDisplayBlockId;

  bool get shouldAutoFollow =>
      playbackActive &&
      followMode == ReadingFocusFollowMode.following &&
      activeDisplayBlockId != null;

  bool get canRecenter =>
      activeDisplayBlockId != null &&
      followMode == ReadingFocusFollowMode.suspendedByUser;

  ReadingFocusState copyWith({
    bool? playbackActive,
    ReadingFocusFollowMode? followMode,
    String? activeDisplayBlockId,
    bool clearActiveDisplayBlockId = false,
  }) {
    return ReadingFocusState(
      playbackActive: playbackActive ?? this.playbackActive,
      followMode: followMode ?? this.followMode,
      activeDisplayBlockId: clearActiveDisplayBlockId
          ? null
          : (activeDisplayBlockId ?? this.activeDisplayBlockId),
    );
  }
}
