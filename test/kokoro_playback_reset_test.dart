import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';

void main() {
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
          released = release.takeIfCurrent(
            resourceEpoch: resource,
            playbackEpoch: playback,
            generationActive: active,
          );
        }();
        if (replacement == 'document') resource++;
        if (replacement == 'replay') playback++;
        if (replacement == 'active generation') active = true;
        exportDrain.complete();
        await completion;
        expect(released, replacement == 'none');
        expect(
          release.takeIfCurrent(
            resourceEpoch: resource,
            playbackEpoch: playback,
            generationActive: false,
          ),
          isFalse,
          reason: 'release debt consumed once',
        );
      },
    );
  }
  test('pause alone never creates end-of-document release debt', () {
    final release = KokoroDeferredResourceRelease();
    expect(
      release.takeIfCurrent(
        resourceEpoch: 1,
        playbackEpoch: 2,
        generationActive: false,
      ),
      isFalse,
    );
  });

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
