import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';
import 'package:read_aloud/src/services/tts_engine.dart';

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

    test('plans append-only resume from the next buffered chunk', () {
      final snapshot = KokoroPlaybackQueueSnapshot(
        activeChunkCount: 3,
        currentChunkIndex: 0,
        currentQueueBaseIndex: 0,
        pendingChunkCount: 0,
        remainingPlannedChunkCount: 0,
        playerRelativeIndex: 0,
      );

      final plan = kokoroPlanForwardRecovery(snapshot);

      expect(
        plan.action,
        KokoroForwardRecoveryAction.resumeFromNextBufferedChunk,
      );
      expect(plan.nextChunkIndex, 1);
    });

    test('waits for prepared audio when starvation has only pending chunks', () {
      final snapshot = KokoroPlaybackQueueSnapshot(
        activeChunkCount: 1,
        currentChunkIndex: 0,
        currentQueueBaseIndex: 0,
        pendingChunkCount: 2,
        remainingPlannedChunkCount: 1,
        playerRelativeIndex: 0,
      );

      final plan = kokoroPlanForwardRecovery(snapshot);

      expect(plan.action, KokoroForwardRecoveryAction.waitForPreparedAudio);
      expect(plan.nextChunkIndex, isNull);
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

    test('classifies buffered lead pressure thresholds', () {
      expect(
        kokoroBufferPressureForLeadTime(const Duration(seconds: 9)),
        TtsBufferPressure.healthy,
      );
      expect(
        kokoroBufferPressureForLeadTime(const Duration(seconds: 4)),
        TtsBufferPressure.lowWater,
      );
      expect(
        kokoroBufferPressureForLeadTime(const Duration(seconds: 2)),
        TtsBufferPressure.critical,
      );
      expect(
        kokoroBufferPressureForLeadTime(const Duration(milliseconds: 500)),
        TtsBufferPressure.critical,
      );
    });

    test('requires startup warmup when only one short chunk is buffered', () {
      expect(
        kokoroIsStartupWarmEnough(
          bufferedChunkCount: 1,
          bufferedLeadTime: const Duration(seconds: 3),
          pendingChunkCount: 2,
          remainingPlannedChunkCount: 4,
        ),
        isFalse,
      );
    });

    test('allows startup when enough buffered runway exists', () {
      expect(
        kokoroIsStartupWarmEnough(
          bufferedChunkCount: 2,
          bufferedLeadTime: const Duration(seconds: 5),
          pendingChunkCount: 2,
          remainingPlannedChunkCount: 3,
        ),
        isTrue,
      );
      expect(
        kokoroIsStartupWarmEnough(
          bufferedChunkCount: 1,
          bufferedLeadTime: const Duration(seconds: 8),
          pendingChunkCount: 1,
          remainingPlannedChunkCount: 2,
        ),
        isTrue,
      );
    });

    test('does not hold startup when no future work remains', () {
      expect(
        kokoroIsStartupWarmEnough(
          bufferedChunkCount: 1,
          bufferedLeadTime: const Duration(seconds: 2),
          pendingChunkCount: 0,
          remainingPlannedChunkCount: 0,
        ),
        isTrue,
      );
    });

    test('builds the initial playback queue from first and staged chunks', () {
      final queue = kokoroBuildInitialPlaybackQueue<_FakePlaybackChunk>(
        firstChunk: const _FakePlaybackChunk(
          chunkId: 'chunk-1',
          startWordIndex: 0,
          startOffset: 0,
        ),
        stagedChunks: const <_FakePlaybackChunk>[
          _FakePlaybackChunk(
            chunkId: 'chunk-3',
            startWordIndex: 8,
            startOffset: 40,
          ),
          _FakePlaybackChunk(
            chunkId: 'chunk-2',
            startWordIndex: 4,
            startOffset: 20,
          ),
          _FakePlaybackChunk(
            chunkId: 'chunk-1',
            startWordIndex: 0,
            startOffset: 0,
          ),
        ],
        chunkIdOf: (chunk) => chunk.chunkId,
        startWordIndexOf: (chunk) => chunk.startWordIndex,
        startOffsetOf: (chunk) => chunk.startOffset,
      );

      expect(
        queue.map((chunk) => chunk.chunkId).toList(growable: false),
        <String>['chunk-1', 'chunk-2', 'chunk-3'],
      );
    });

    test('inserts ready chunks by document order instead of arrival order', () {
      final insertIndex = kokoroPlaybackInsertIndex<_FakePlaybackChunk>(
        activeChunks: const <_FakePlaybackChunk>[
          _FakePlaybackChunk(
            chunkId: 'chunk-1',
            startWordIndex: 0,
            startOffset: 0,
          ),
          _FakePlaybackChunk(
            chunkId: 'chunk-3',
            startWordIndex: 8,
            startOffset: 40,
          ),
        ],
        incomingChunk: const _FakePlaybackChunk(
          chunkId: 'chunk-2',
          startWordIndex: 4,
          startOffset: 20,
        ),
        chunkIdOf: (chunk) => chunk.chunkId,
        startWordIndexOf: (chunk) => chunk.startWordIndex,
        startOffsetOf: (chunk) => chunk.startOffset,
      );

      expect(insertIndex, 1);
    });

    test('finds first future buffered chunk that must be replaced', () {
      final pruneIndex = kokoroFirstFutureReplacementIndex<_FakePlaybackChunk>(
        activeChunks: const <_FakePlaybackChunk>[
          _FakePlaybackChunk(
            chunkId: 'chunk-1',
            startWordIndex: 0,
            startOffset: 0,
          ),
          _FakePlaybackChunk(
            chunkId: 'chunk-2',
            startWordIndex: 4,
            startOffset: 20,
          ),
          _FakePlaybackChunk(
            chunkId: 'chunk-3',
            startWordIndex: 8,
            startOffset: 40,
          ),
          _FakePlaybackChunk(
            chunkId: 'chunk-4',
            startWordIndex: 12,
            startOffset: 60,
          ),
        ],
        currentChunkIndex: 0,
        replacementStartWordIndex: 8,
        startWordIndexOf: (chunk) => chunk.startWordIndex,
      );

      expect(pruneIndex, 2);
    });
  });
}

class _FakePlaybackChunk {
  const _FakePlaybackChunk({
    required this.chunkId,
    required this.startWordIndex,
    required this.startOffset,
  });

  final String chunkId;
  final int startWordIndex;
  final int startOffset;
}
