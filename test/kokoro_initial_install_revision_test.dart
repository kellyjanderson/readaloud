import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';

void main() {
  test(
    'held old mutation cannot release reused chunk pin owned by new generation',
    () async {
      final registry = AudioArtifactPins();
      final pins = KokoroPlaybackArtifactPins(registry);
      const path = '/private-test/immutable-same-content.wav';
      pins.pin('A', 'reused-chunk', path);
      final oldSnapshot = pins.snapshot();
      final held = Completer<void>();
      final late = () async {
        await held.future;
        pins.release('A', 'reused-chunk');
        pins.releaseSnapshot(oldSnapshot);
      }();
      pins.pin('C', 'reused-chunk', path);
      expect(registry.pinCount(path), 2);
      held.complete();
      await late;
      expect(registry.pinCount(path), 1);
      expect(pins.length, 1);
      pins.releaseSnapshot(pins.snapshot());
      expect(registry.pinCount(path), 0);
    },
  );
  test('clear acknowledgment snapshot cannot release a replaced handle', () {
    final registry = AudioArtifactPins();
    final pins = KokoroPlaybackArtifactPins(registry);
    pins.pin('A', 'chunk', '/private-test/old.wav');
    final beforeClear = pins.snapshot();
    pins.release('A', 'chunk');
    pins.pin('A', 'chunk', '/private-test/new.wav');
    pins.releaseSnapshot(beforeClear);
    expect(registry.pinCount('/private-test/new.wav'), 1);
    pins.releaseSnapshot(pins.snapshot());
    expect(registry.pinCount('/private-test/new.wav'), 0);
  });
  for (final fails in [false, true]) {
    test(
      'late A install ${fails ? 'failure' : 'success'} clears before newest C can install',
      () async {
        final queue = KokoroPlaylistMutationQueue();
        final a = Completer<void>();
        final cleanup = Completer<void>();
        var revision = 1;
        final events = <String>[];
        final first = queue.run(
          () async {
            final installed = await kokoroInstallPreparedPlayback(
              isCurrent: () => revision == 1,
              install: () {
                events.add('install A');
                return a.future;
              },
              clearStale: () {
                events.add('clear A');
                return cleanup.future;
              },
            );
            if (installed) events.add('ack A');
          },
          onFailure: (e, s) async {
            events.add('failure A');
          },
        );
        await Future<void>.delayed(Duration.zero);
        revision = 2;
        final b = queue.run(
          () async {
            final installed = await kokoroInstallPreparedPlayback(
              isCurrent: () => revision == 2,
              install: () async {
                events.add('install B');
              },
              clearStale: () async {
                events.add('clear B');
              },
            );
            if (installed) events.add('ack B');
          },
          onFailure: (e, s) async {
            events.add('failure B');
          },
        );
        revision = 3;
        final c = queue.run(
          () async {
            final installed = await kokoroInstallPreparedPlayback(
              isCurrent: () => revision == 3,
              install: () async {
                events.add('install C');
              },
              clearStale: () async {
                events.add('clear C');
              },
            );
            if (installed) events.add('ack C');
          },
          onFailure: (e, s) async {
            events.add('failure C');
          },
        );
        if (fails) {
          a.completeError(StateError('obsolete native A failure'));
        } else {
          a.complete();
        }
        await Future<void>.delayed(Duration.zero);
        expect(events, ['install A', 'clear A']);
        cleanup.complete();
        await Future.wait([first, b, c]);
        expect(events, ['install A', 'clear A', 'install C', 'ack C']);
      },
    );
  }
}
