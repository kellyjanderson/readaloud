import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';

void main() {
  group('kokoro playback coordination', () {
    test('enters underrun recovery when future chunks are already buffered', () {
      final snapshot = KokoroPlaybackQueueSnapshot(
        activeChunkCount: 3,
        currentChunkIndex: 0,
        currentQueueBaseIndex: 0,
        pendingChunkCount: 0,
        remainingPlannedChunkCount: 0,
        playerRelativeIndex: 0,
      );

      expect(kokoroHasBufferedFutureChunks(snapshot), isTrue);
      expect(kokoroShouldEnterUnderrunRecovery(snapshot), isTrue);
      expect(kokoroNextRecoveryStartIndex(snapshot), 1);
    });

    test('enters underrun recovery when later chunks are still pending', () {
      final snapshot = KokoroPlaybackQueueSnapshot(
        activeChunkCount: 1,
        currentChunkIndex: 0,
        currentQueueBaseIndex: 0,
        pendingChunkCount: 1,
        remainingPlannedChunkCount: 0,
        playerRelativeIndex: 0,
      );

      expect(kokoroHasBufferedFutureChunks(snapshot), isFalse);
      expect(kokoroShouldEnterUnderrunRecovery(snapshot), isTrue);
      expect(kokoroNextRecoveryStartIndex(snapshot), isNull);
    });

    test('computes recovery start from absolute queue position after rebasing', () {
      final snapshot = KokoroPlaybackQueueSnapshot(
        activeChunkCount: 5,
        currentChunkIndex: 2,
        currentQueueBaseIndex: 2,
        pendingChunkCount: 0,
        remainingPlannedChunkCount: 0,
        playerRelativeIndex: 1,
      );

      expect(kokoroNextRecoveryStartIndex(snapshot), 4);
    });

    test('returns null when playback is already at the final buffered chunk', () {
      final snapshot = KokoroPlaybackQueueSnapshot(
        activeChunkCount: 3,
        currentChunkIndex: 2,
        currentQueueBaseIndex: 0,
        pendingChunkCount: 0,
        remainingPlannedChunkCount: 0,
        playerRelativeIndex: 2,
      );

      expect(kokoroHasBufferedFutureChunks(snapshot), isFalse);
      expect(kokoroShouldEnterUnderrunRecovery(snapshot), isFalse);
      expect(kokoroNextRecoveryStartIndex(snapshot), isNull);
    });

    test('plans recoverable chunk slices on punctuation boundaries', () {
      final slices = kokoroPlanRecoverableChunkSlices(
        wordBoundaries: const <KokoroRecoveryWordBoundary>[
          KokoroRecoveryWordBoundary(start: 0, end: 3, word: 'One'),
          KokoroRecoveryWordBoundary(start: 4, end: 9, word: 'small'),
          KokoroRecoveryWordBoundary(start: 10, end: 15, word: 'quote,'),
          KokoroRecoveryWordBoundary(start: 16, end: 20, word: 'then'),
          KokoroRecoveryWordBoundary(start: 21, end: 26, word: 'more'),
          KokoroRecoveryWordBoundary(start: 27, end: 35, word: 'narration'),
          KokoroRecoveryWordBoundary(start: 36, end: 40, word: 'that'),
          KokoroRecoveryWordBoundary(start: 41, end: 47, word: 'keeps'),
          KokoroRecoveryWordBoundary(start: 48, end: 57, word: 'failing.'),
        ],
        preferredTargetWords: 4,
        minimumSliceWords: 3,
      );

      expect(slices.length, greaterThanOrEqualTo(2));
      expect(slices[0].startWordOffset, 0);
      expect(slices[0].endWordOffset, 3);
      expect(slices.last.startWordOffset, greaterThanOrEqualTo(3));
      expect(slices.last.endWordOffset, 9);
    });

    test('does not plan recovery slices for short chunks', () {
      final slices = kokoroPlanRecoverableChunkSlices(
        wordBoundaries: const <KokoroRecoveryWordBoundary>[
          KokoroRecoveryWordBoundary(start: 0, end: 5, word: 'Short'),
          KokoroRecoveryWordBoundary(start: 6, end: 11, word: 'later'),
          KokoroRecoveryWordBoundary(start: 12, end: 17, word: 'chunk'),
          KokoroRecoveryWordBoundary(start: 18, end: 22, word: 'only'),
          KokoroRecoveryWordBoundary(start: 23, end: 27, word: 'has'),
        ],
      );

      expect(slices, isEmpty);
    });
  });
}
