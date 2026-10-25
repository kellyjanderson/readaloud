import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';

void main() {
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
