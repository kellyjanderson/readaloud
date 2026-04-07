class KokoroPlaybackQueueSnapshot {
  const KokoroPlaybackQueueSnapshot({
    required this.activeChunkCount,
    required this.currentChunkIndex,
    required this.currentQueueBaseIndex,
    required this.pendingChunkCount,
    required this.remainingPlannedChunkCount,
    this.playerRelativeIndex,
  });

  final int activeChunkCount;
  final int currentChunkIndex;
  final int currentQueueBaseIndex;
  final int pendingChunkCount;
  final int remainingPlannedChunkCount;
  final int? playerRelativeIndex;
}

class KokoroRecoveryWordBoundary {
  const KokoroRecoveryWordBoundary({
    required this.start,
    required this.end,
    required this.word,
  });

  final int start;
  final int end;
  final String word;
}

class KokoroRecoveryWordSlice {
  const KokoroRecoveryWordSlice({
    required this.startWordOffset,
    required this.endWordOffset,
  });

  final int startWordOffset;
  final int endWordOffset;

  int get wordCount => endWordOffset - startWordOffset;
}

bool kokoroShouldEnterUnderrunRecovery(KokoroPlaybackQueueSnapshot snapshot) {
  return kokoroHasBufferedFutureChunks(snapshot) ||
      snapshot.pendingChunkCount > 0 ||
      snapshot.remainingPlannedChunkCount > 0;
}

bool kokoroHasBufferedFutureChunks(KokoroPlaybackQueueSnapshot snapshot) {
  return kokoroNextRecoveryStartIndex(snapshot) != null;
}

int? kokoroNextRecoveryStartIndex(KokoroPlaybackQueueSnapshot snapshot) {
  if (snapshot.activeChunkCount <= 0) {
    return null;
  }

  final absolutePlayerIndex = snapshot.playerRelativeIndex == null
      ? snapshot.currentChunkIndex
      : snapshot.currentQueueBaseIndex + snapshot.playerRelativeIndex!;
  final lastConsumedIndex = _clampChunkIndex(
    snapshot,
    absolutePlayerIndex > snapshot.currentChunkIndex
        ? absolutePlayerIndex
        : snapshot.currentChunkIndex,
  );
  final nextChunkIndex = lastConsumedIndex + 1;
  if (nextChunkIndex >= snapshot.activeChunkCount) {
    return null;
  }
  return nextChunkIndex;
}

int _clampChunkIndex(KokoroPlaybackQueueSnapshot snapshot, int index) {
  if (snapshot.activeChunkCount <= 0) {
    return 0;
  }
  if (index < 0) {
    return 0;
  }
  if (index >= snapshot.activeChunkCount) {
    return snapshot.activeChunkCount - 1;
  }
  return index;
}

List<KokoroRecoveryWordSlice> kokoroPlanRecoverableChunkSlices({
  required List<KokoroRecoveryWordBoundary> wordBoundaries,
  int preferredTargetWords = 8,
  int minimumSliceWords = 3,
}) {
  if (wordBoundaries.length < minimumSliceWords * 2) {
    return const <KokoroRecoveryWordSlice>[];
  }

  final slices = <KokoroRecoveryWordSlice>[];
  var cursor = 0;
  while (cursor < wordBoundaries.length) {
    final remaining = wordBoundaries.length - cursor;
    if (remaining <= preferredTargetWords) {
      slices.add(
        KokoroRecoveryWordSlice(
          startWordOffset: cursor,
          endWordOffset: wordBoundaries.length,
        ),
      );
      break;
    }

    final minEnd = cursor + minimumSliceWords;
    final maxEnd = (cursor + preferredTargetWords + 2)
        .clamp(minEnd, wordBoundaries.length - minimumSliceWords)
        .toInt();
    final preferredEnd =
        (cursor + preferredTargetWords).clamp(minEnd, maxEnd).toInt();
    final chosenEnd =
        _findRecoveryBoundary(
          wordBoundaries: wordBoundaries,
          minEnd: minEnd,
          preferredEnd: preferredEnd,
          maxEnd: maxEnd,
        ) ??
        preferredEnd;

    slices.add(
      KokoroRecoveryWordSlice(
        startWordOffset: cursor,
        endWordOffset: chosenEnd,
      ),
    );
    cursor = chosenEnd;
  }

  if (slices.length <= 1 || slices.any((slice) => slice.wordCount < minimumSliceWords)) {
    return const <KokoroRecoveryWordSlice>[];
  }
  return List<KokoroRecoveryWordSlice>.unmodifiable(slices);
}

int? _findRecoveryBoundary({
  required List<KokoroRecoveryWordBoundary> wordBoundaries,
  required int minEnd,
  required int preferredEnd,
  required int maxEnd,
}) {
  int? weakMatch;

  for (var end = preferredEnd; end >= minEnd; end -= 1) {
    final boundaryWord = wordBoundaries[end - 1].word;
    if (_isStrongRecoveryBoundary(boundaryWord)) {
      return end;
    }
    weakMatch ??= _isWeakRecoveryBoundary(boundaryWord) ? end : null;
  }
  for (var end = preferredEnd + 1; end <= maxEnd; end += 1) {
    final boundaryWord = wordBoundaries[end - 1].word;
    if (_isStrongRecoveryBoundary(boundaryWord)) {
      return end;
    }
    weakMatch ??= _isWeakRecoveryBoundary(boundaryWord) ? end : null;
  }

  return weakMatch;
}

bool _isStrongRecoveryBoundary(String word) {
  final terminal = _terminalPunctuationCodeUnit(word);
  return terminal == 0x2E || terminal == 0x21 || terminal == 0x3F;
}

bool _isWeakRecoveryBoundary(String word) {
  final terminal = _terminalPunctuationCodeUnit(word);
  return terminal == 0x2C || terminal == 0x3B || terminal == 0x3A;
}

int? _terminalPunctuationCodeUnit(String word) {
  if (word.isEmpty) {
    return null;
  }

  var index = word.length - 1;
  while (index >= 0) {
    final codeUnit = word.codeUnitAt(index);
    final isClosingQuote =
        codeUnit == 0x22 ||
        codeUnit == 0x27 ||
        codeUnit == 0x2019 ||
        codeUnit == 0x201D;
    if (!isClosingQuote) {
      return codeUnit;
    }
    index -= 1;
  }

  return null;
}
