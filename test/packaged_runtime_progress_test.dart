import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/packaged_python_runtime.dart';

Map<String, dynamic> progress(
  int? completed, {
  String stage = 'runtimeNative',
  int? total = 1000,
  String unit = 'entries',
}) => {
  'runtimeId': 'mlx',
  'attemptId': 'attempt/one',
  'signedTreeDigest': 'verified-digest',
  'stage': stage,
  'message': 'Verified $completed of $total',
  'completed': completed,
  'total': total,
  'unit': unit,
};

void main() {
  testWidgets('same-stage burst publishes at most every 100 ms, latest wins', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    final sent = <Map<String, dynamic>>[];
    final times = <Duration>[];
    final publisher = RuntimeProgressPublisher(
      elapsed: () => elapsed,
      publish: (value) {
        sent.add(value);
        times.add(elapsed);
      },
    );
    addTearDown(publisher.close);
    publisher.add(progress(0));
    for (var count = 1; count < 1000; count++) {
      elapsed += const Duration(milliseconds: 1);
      await tester.pump(const Duration(milliseconds: 1));
      publisher.add(progress(count));
    }
    expect(times, List.generate(10, (i) => Duration(milliseconds: i * 100)));
    expect(sent.last['completed'], 899);
    expect(sent.last['message'], 'Verified 899 of 1000');
    publisher.add(progress(1000));
    expect(sent.last['completed'], 1000);
    expect(times.last, const Duration(milliseconds: 999));
    elapsed += const Duration(seconds: 1);
    await tester.pump(const Duration(seconds: 1));
    expect(sent, hasLength(11));
    expect(sent.every((value) => value['attemptId'] == 'attempt/one'), true);
    expect(
      sent.every((value) => value['signedTreeDigest'] == 'verified-digest'),
      true,
    );
  });

  testWidgets('quiet producer flushes immutable latest value at its deadline', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    final sent = <Map<String, dynamic>>[];
    final publisher = RuntimeProgressPublisher(
      elapsed: () => elapsed,
      publish: sent.add,
    );
    addTearDown(publisher.close);
    publisher.add(progress(1));
    elapsed = const Duration(milliseconds: 70);
    await tester.pump(elapsed);
    final mutable = progress(2);
    publisher.add(mutable);
    mutable['completed'] = 900;
    mutable['attemptId'] = 'mutated';
    elapsed = const Duration(milliseconds: 99);
    await tester.pump(const Duration(milliseconds: 29));
    expect(sent, hasLength(1));
    elapsed = const Duration(milliseconds: 100);
    await tester.pump(const Duration(milliseconds: 1));
    expect(sent.map((value) => value['completed']), [1, 2]);
    expect(sent.last['attemptId'], 'attempt/one');
    expect(() => sent.last['completed'] = 3, throwsUnsupportedError);
    elapsed = const Duration(milliseconds: 500);
    await tester.pump(const Duration(milliseconds: 400));
    expect(sent, hasLength(2));
  });

  testWidgets(
    'stage, counter reset, unit and denominator boundaries are immediate',
    (tester) async {
      var elapsed = Duration.zero;
      final sent = <Map<String, dynamic>>[];
      final publisher = RuntimeProgressPublisher(
        elapsed: () => elapsed,
        publish: sent.add,
      );
      addTearDown(publisher.close);
      publisher.add(progress(1));
      publisher.add(progress(90));
      publisher.add(progress(2)); // Reset relative to pending, not last sent.
      publisher.add(progress(3));
      publisher.add(progress(4, total: 2000));
      publisher.add(progress(5, total: 2000, unit: 'bytes'));
      publisher.add(progress(6, stage: 'runtimeArchive'));
      expect(sent.map((value) => value['completed']), [1, 2, 4, 5, 6]);
      elapsed = const Duration(milliseconds: 100);
      await tester.pump(elapsed);
      expect(sent, hasLength(5)); // No superseded stage/reset value returns.
    },
  );

  testWidgets(
    'unknown or invalid totals retain actual counts and unknown stages',
    (tester) async {
      var elapsed = Duration.zero;
      final sent = <Map<String, dynamic>>[];
      final publisher = RuntimeProgressPublisher(
        elapsed: () => elapsed,
        publish: sent.add,
      );
      addTearDown(publisher.close);
      publisher.add(progress(null, total: null, stage: 'runtimeExtract'));
      publisher.add(progress(1, total: null));
      publisher.add(progress(2, total: null));
      expect(sent.last['completed'], 1);
      elapsed = const Duration(milliseconds: 100);
      await tester.pump(elapsed);
      expect(sent.last['completed'], 2);
      expect(sent.last['total'], isNull);
      publisher.add(progress(-1, total: -1));
      publisher.add(progress(-1, total: -1));
      expect(sent, hasLength(4)); // Invalid equal counters are not completion.
      publisher.add(progress(10, total: 0));
      publisher.add(progress(11, total: 0));
      expect(sent.last['completed'], 10);
      elapsed = const Duration(milliseconds: 200);
      await tester.pump(const Duration(milliseconds: 100));
      expect(sent.last['completed'], 11);
      expect(sent.last['total'], 0); // No invented denominator or clamping.
    },
  );

  for (final terminal in ['success', 'failure', 'cancellation']) {
    testWidgets(
      '$terminal closes pending progress before terminal publication',
      (tester) async {
        var elapsed = Duration.zero;
        final events = <Object>[];
        final publisher = RuntimeProgressPublisher(
          elapsed: () => elapsed,
          publish: events.add,
        );
        publisher.add(progress(1));
        publisher.add(progress(2));
        publisher.close();
        publisher.close();
        events.add(terminal);
        publisher.add(progress(1000));
        elapsed = const Duration(seconds: 1);
        await tester.pump(elapsed);
        expect(events, hasLength(2));
        expect(events.last, terminal);
      },
    );
  }
}
