import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/spoken_chunk_record.dart';
import '../tools/p3_native_playback_probe.dart';

void main() {
  test('old completion cannot finish configuration or fresh startup', () async {
    final gate = P3ProbeScenarioGate();
    expect(gate.observe(ReaderPlaybackPrimaryState.completed), isNull);
    gate.request();
    expect(gate.observe(ReaderPlaybackPrimaryState.completed), isNull);
    expect(gate.isCompleted, isFalse);
    gate.markStarted();
    expect(gate.observe(ReaderPlaybackPrimaryState.playing), isNull);
    expect(
      gate.observe(ReaderPlaybackPrimaryState.completed),
      'documentCompleted',
    );
    await gate.done;
    expect(gate.observe(ReaderPlaybackPrimaryState.completed), isNull);
    final next = P3ProbeScenarioGate()..request();
    expect(next.observe(ReaderPlaybackPrimaryState.completed), isNull);
    expect(next.isCompleted, isFalse);
  });

  test('fresh startup failure remains terminal before native start', () async {
    final gate = P3ProbeScenarioGate()..request();
    expect(
      gate.observe(ReaderPlaybackPrimaryState.failed, status: 'worker failed'),
      'controllerFailure',
    );
    await gate.done;
    expect(gate.failure, 'worker failed');
  });
}
