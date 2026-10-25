import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';

void main() {
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
