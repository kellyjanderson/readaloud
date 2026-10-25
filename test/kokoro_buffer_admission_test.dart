import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';

void main() {
  group('KokoroBufferAdmission', () {
    for (final speed in <double>[0.5, 1, 2]) {
      test('refill hysteresis uses wall time at ${speed}x', () {
        final policy = KokoroBufferAdmission();
        Duration audio(int wallMillis) =>
            Duration(microseconds: (wallMillis * 1000 * speed).round());
        bool admit(int wallMillis) => policy.admits(
          audioLead: audio(wallMillis),
          outstandingChunks: 2,
          playerSpeed: speed,
        );

        expect(admit(7999), isTrue);
        expect(admit(8000), isFalse);
        expect(admit(6000), isFalse, reason: 'retain high-water latch');
        expect(admit(4001), isFalse);
        expect(admit(4000), isTrue, reason: 'refill at low-water boundary');
        expect(
          admit(6000),
          isTrue,
          reason: 'continue refill toward high water',
        );
        expect(admit(8000), isFalse);
      });
    }

    test('count cap releases credit without latching duration admission', () {
      final policy = KokoroBufferAdmission(maxChunks: 8);
      expect(
        policy.admits(audioLead: Duration.zero, outstandingChunks: 8),
        isFalse,
      );
      expect(
        policy.admits(audioLead: Duration.zero, outstandingChunks: 7),
        isTrue,
      );
    });

    for (final chunkDuration in <Duration>[
      Duration.zero,
      const Duration(microseconds: 1),
    ]) {
      test('bounded startup explicitly refuses $chunkDuration chunks', () {
        final policy = KokoroBufferAdmission();
        var ready = 0;
        var lead = Duration.zero;
        while (policy.admits(audioLead: lead, outstandingChunks: ready)) {
          ready++;
          lead += chunkDuration;
          if (ready > policy.maxChunks) {
            fail('admission exceeded its declared count bound');
          }
        }
        expect(ready, policy.maxChunks);
        expect(
          kokoroIsStartupWarmEnough(
            bufferedChunkCount: ready,
            bufferedLeadTime: lead,
            pendingChunkCount: 0,
            remainingPlannedChunkCount: 1,
          ),
          isFalse,
          reason: 'count exhaustion must not lower startup lead',
        );
        expect(
          policy.startupCapacityExhausted(
            audioLead: lead,
            bufferedChunkCount: ready,
            pendingChunkCount: 0,
            remainingPlannedChunkCount: 1,
          ),
          isTrue,
          reason: 'return a terminal reason instead of waiting forever',
        );
      });
    }

    test('legal short document exceeds old nominal planning window', () {
      // Twelve small chunks exceed both the original 3-chunk window and the
      // proposed 6-chunk cap. The complete document is a legal startup prefix.
      const count = 12;
      const duration = Duration(milliseconds: 100);
      final policy = KokoroBufferAdmission();
      var lead = Duration.zero;
      for (var ready = 0; ready < count; ready++) {
        expect(
          policy.admits(audioLead: lead, outstandingChunks: ready),
          isTrue,
          reason: 'short document blocked before chunk ${ready + 1}',
        );
        lead += duration;
        expect(
          kokoroIsStartupWarmEnough(
            bufferedChunkCount: ready + 1,
            bufferedLeadTime: lead,
            pendingChunkCount: 0,
            remainingPlannedChunkCount: count - ready - 1,
          ),
          ready + 1 == count,
        );
      }
      expect(
        policy.startupCapacityExhausted(
          audioLead: lead,
          bufferedChunkCount: count,
          pendingChunkCount: 0,
          remainingPlannedChunkCount: 0,
        ),
        isFalse,
      );
    });

    test(
      'startup terminal decision respects player speed and pending work',
      () {
        final policy = KokoroBufferAdmission(maxChunks: 8);
        bool exhausted({
          double speed = 1,
          int ready = 8,
          int pending = 0,
          int remaining = 1,
        }) => policy.startupCapacityExhausted(
          audioLead: const Duration(seconds: 6),
          bufferedChunkCount: ready,
          pendingChunkCount: pending,
          remainingPlannedChunkCount: remaining,
          playerSpeed: speed,
        );
        expect(exhausted(), isFalse);
        expect(exhausted(speed: 2), isTrue);
        expect(
          exhausted(speed: 1.5),
          isFalse,
          reason: 'exactly four playable seconds',
        );
        expect(exhausted(speed: 2, ready: 7), isFalse);
        expect(
          exhausted(speed: 2, pending: 1),
          isFalse,
          reason: 'an admitted result can still increase lead',
        );
        expect(
          exhausted(speed: 2, remaining: 0),
          isFalse,
          reason: 'complete short document can start below target',
        );
      },
    );

    test('invalid speed is rejected on admission and startup paths', () {
      final policy = KokoroBufferAdmission();
      for (final speed in <double>[0, -1, double.nan, double.infinity]) {
        expect(
          () => policy.admits(
            audioLead: Duration.zero,
            outstandingChunks: 0,
            playerSpeed: speed,
          ),
          throwsArgumentError,
        );
        expect(
          () => policy.startupCapacityExhausted(
            audioLead: Duration.zero,
            bufferedChunkCount: 64,
            pendingChunkCount: 0,
            remainingPlannedChunkCount: 1,
            playerSpeed: speed,
          ),
          throwsArgumentError,
        );
      }
    });
  });
}
