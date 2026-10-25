import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';

void main() {
  test(
    'tail failure drains cancellation and native reset before reporting',
    () async {
      final cancel = Completer<void>();
      final reset = Completer<void>();
      final events = <String>[];
      final terminal = kokoroTerminatePreparationFailure(
        invalidate: () => events.add('invalidated'),
        isCurrent: () => true,
        cancel: () {
          events.add('cancel');
          return cancel.future;
        },
        reset: () {
          events.add('reset');
          return reset.future;
        },
        report: (_) => events.add('reported'),
      );
      expect(events, ['invalidated', 'cancel']);
      cancel.complete();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['invalidated', 'cancel', 'reset']);
      reset.complete();
      await terminal;
      expect(events, ['invalidated', 'cancel', 'reset', 'reported']);
    },
  );
  for (final failedStep in ['cancel', 'reset']) {
    test(
      'tail failure reports original terminal after $failedStep throws',
      () async {
        final events = <String>[];
        final failure = StateError(failedStep);
        await kokoroTerminatePreparationFailure(
          invalidate: () => events.add('invalidate'),
          isCurrent: () => true,
          cancel: () async {
            events.add('cancel');
            if (failedStep == 'cancel') throw failure;
          },
          reset: () async {
            events.add('reset');
            if (failedStep == 'reset') throw failure;
          },
          report: (errors) {
            events.add('original reported');
            expect(errors, [failure]);
          },
        );
        expect(events, ['invalidate', 'cancel', 'reset', 'original reported']);
      },
    );
  }
  test(
    'replacement while cancellation drains suppresses old reset and terminal',
    () async {
      final cancel = Completer<void>();
      var current = true;
      var reset = false;
      var reported = false;
      final terminal = kokoroTerminatePreparationFailure(
        invalidate: () {},
        isCurrent: () => current,
        cancel: () => cancel.future,
        reset: () async {
          reset = true;
        },
        report: (_) => reported = true,
      );
      current = false;
      cancel.complete();
      await terminal;
      expect(reset, isFalse);
      expect(reported, isFalse);
    },
  );
  for (final replacement in [
    'none',
    'document',
    'replay',
    'active generation',
  ]) {
    test(
      'deferred end release respects $replacement while export drains',
      () async {
        final exportDrain = Completer<void>();
        final release = KokoroDeferredResourceRelease();
        var resource = 1;
        var playback = 2;
        var active = false;
        var released = false;
        release.defer(resourceEpoch: resource, playbackEpoch: playback);
        final completion = () async {
          await exportDrain.future;
          released = await release.takeIfCurrent(
            resourceEpoch: () => resource,
            playbackEpoch: () => playback,
            generationActive: () => active,
          );
        }();
        if (replacement == 'document') resource++;
        if (replacement == 'replay') playback++;
        if (replacement == 'active generation') active = true;
        exportDrain.complete();
        await completion;
        expect(released, replacement == 'none');
        expect(
          await release.takeIfCurrent(
            resourceEpoch: () => resource,
            playbackEpoch: () => playback,
            generationActive: () => false,
          ),
          isFalse,
          reason: 'release debt consumed once',
        );
      },
    );
  }
  test('pause alone never creates end-of-document release debt', () async {
    final release = KokoroDeferredResourceRelease();
    expect(
      await release.takeIfCurrent(
        resourceEpoch: () => 1,
        playbackEpoch: () => 2,
        generationActive: () => false,
      ),
      isFalse,
    );
  });

  for (final replaced in [false, true]) {
    test(
      'export joins old end reset before release (replaced=$replaced)',
      () async {
        final reset = Completer<void>();
        final release = KokoroDeferredResourceRelease();
        var resource = 1;
        var playback = 2;
        var endingGenerationActive = true;
        var settled = false;
        release.defer(
          resourceEpoch: resource,
          playbackEpoch: playback,
          resetDrained: reset.future,
        );
        final decision = release
            .takeIfCurrent(
              resourceEpoch: () => resource,
              playbackEpoch: () => playback,
              generationActive: () => endingGenerationActive,
            )
            .then((value) {
              settled = true;
              return value;
            });
        await Future<void>.delayed(Duration.zero);
        expect(
          settled,
          isFalse,
          reason: 'export completion cannot consume debt before reset',
        );
        if (replaced) {
          resource++;
          playback++;
        }
        endingGenerationActive = false;
        reset.complete();
        expect(await decision, !replaced);
      },
    );
  }

  test(
    'failed playlist mutation owns cleanup before reset and new sources',
    () async {
      final cleanup = Completer<void>();
      final queue = KokoroPlaylistMutationQueue();
      final events = <String>[];
      final failed = queue.run(
        () async {
          events.add('remove attempted');
          throw StateError('native removal failed');
        },
        onFailure: (error, stack) async {
          events.add('terminal failure');
          await cleanup.future;
          events.add('old player cleared');
        },
      );
      final replay = queue.run(() async {
        events.add('new sources installed');
      }, onFailure: (error, stack) async => fail('Unexpected replay failure'));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['remove attempted', 'terminal failure']);
      cleanup.complete();
      expect(await failed, isFalse);
      expect(await replay, isTrue);
      await queue.drained;
      expect(events, [
        'remove attempted',
        'terminal failure',
        'old player cleared',
        'new sources installed',
      ]);
    },
  );

  test('failure reporter cannot poison subsequent playlist drain', () async {
    final queue = KokoroPlaylistMutationQueue();
    await expectLater(
      queue.run(
        () async => throw StateError('mutation'),
        onFailure: (error, stack) async => throw StateError('reporter'),
      ),
      throwsStateError,
    );
    var replayed = false;
    expect(
      await queue.run(() async {
        replayed = true;
      }, onFailure: (error, stack) async => fail('Unexpected failure')),
      isTrue,
    );
    await queue.drained;
    expect(replayed, isTrue);
  });

  test(
    'replay joins old stop before replacing sources or reporting playing',
    () async {
      final oldStop = Completer<void>();
      final operations = <String>[];
      final reset = KokoroPlaybackResetBarrier(() async {
        operations.add('stop');
        await oldStop.future;
        operations.add('clear old sources');
        operations.add('idle');
      });
      final endOfDocument = reset.reset();
      final replay = () async {
        await reset.reset();
        operations.add('install new sources');
        operations.add('playing');
      }();
      await Future<void>.delayed(Duration.zero);
      expect(operations, ['stop']);
      oldStop.complete();
      await Future.wait([endOfDocument, replay]);
      expect(operations, [
        'stop',
        'clear old sources',
        'idle',
        'install new sources',
        'playing',
      ]);
      await reset.reset();
      expect(operations.where((value) => value == 'stop').length, 2);
    },
  );
}
