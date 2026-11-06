import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/modernbooknlp_analysis.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';

class _Provider extends ModernBookNlpProvider {
  _Provider()
    : super(pythonPath: 'unused', helperPath: 'unused', runtimePath: 'unused');
  final started = <ModernBookNlpRequest>[];
  final replies = <Completer<Map<String, dynamic>>>[];
  var preparations = 0, closed = false;
  bool ignoreCancellation = false;
  @override
  Future<void> prepare({
    bool offline = false,
    void Function(Map<String, dynamic>)? onProgress,
  }) async {
    preparations++;
  }

  @override
  Future<Map<String, dynamic>> analyze(
    ModernBookNlpRequest r, {
    void Function(Map<String, dynamic>)? onProgress,
  }) {
    started.add(r);
    final reply = Completer<Map<String, dynamic>>();
    replies.add(reply);
    return reply.future;
  }

  @override
  Future<void> cancel() async {
    if (ignoreCancellation) return;
    if (replies.isNotEmpty && !replies.last.isCompleted) {
      replies.last.completeError(const ModernBookNlpCancelled());
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    await cancel();
  }
}

void main() {
  ModernBookNlpRequest request(int n, {String source = 's'}) =>
      ModernBookNlpRequest(
        requestId: 'r$n',
        ownerId: 'o',
        workId: 'w',
        sourceRevision: source,
        analysisRevision: 1,
        sequence: n,
        text: 'Text $n',
      );
  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(ready(), true);
  }

  test(
    'one active and latest pending; same window is not repeatedly analyzed',
    () async {
      final provider = _Provider();
      final owner = ModernBookNlpAnalysis(() async => provider);
      addTearDown(owner.shutdown);
      owner.offer(request(1));
      owner.enable();
      await until(() => provider.started.length == 1);
      owner.offer(request(2));
      owner.offer(request(3));
      owner.offer(request(4));
      expect(provider.started.length, 1);
      expect(owner.hasPendingWindow, true);
      provider.replies[0].complete({'quotes': [], 'window': 1});
      await until(() => provider.started.length == 2);
      expect(provider.started.last.sequence, 4);
      provider.replies[1].complete({'quotes': [], 'window': 4});
      await until(() => !owner.busy);
      owner.offer(request(4));
      await Future<void>.delayed(Duration.zero);
      expect(provider.started.length, 2);
      expect(provider.preparations, 1);
      expect(owner.completedWindows, 1); // Superseded demand cannot publish.
    },
  );
  test(
    'source replacement cancels old result; Stop drains and never restarts',
    () async {
      final provider = _Provider();
      final owner = ModernBookNlpAnalysis(() async => provider);
      addTearDown(owner.shutdown);
      owner.offer(request(1));
      owner.enable();
      await until(() => provider.started.isNotEmpty);
      owner.invalidateWindow();
      owner.offer(request(2, source: 'new'));
      await until(() => provider.started.length == 2);
      expect(owner.error, isNull);
      expect(owner.result, isNull);
      provider.replies.last.complete({'quotes': [], 'source': 'new'});
      await until(() => !owner.busy);
      expect(owner.result!['source'], 'new');
      owner.offer(request(3, source: 'new'));
      await until(() => provider.started.length == 3);
      await owner.stop();
      expect(owner.busy, false);
      expect(owner.enabled, false);
      expect(owner.error, isNull);
      owner.offer(request(4));
      expect(provider.started.length, 3);
    },
  );
  test('setup failure is actionable and Retry reuses the same owner', () async {
    var attempts = 0;
    final provider = _Provider();
    final owner = ModernBookNlpAnalysis(() async {
      if (++attempts == 1) throw StateError('runtime missing');
      return provider;
    });
    addTearDown(owner.shutdown);
    owner.enable();
    await until(() => !owner.busy);
    expect(owner.error, contains('runtime missing'));
    owner.enable();
    await until(() => !owner.busy);
    expect(owner.error, isNull);
    expect(owner.ready, true);
  });
  for (final fails in [false, true]) {
    test(
      'late obsolete ${fails ? 'failure' : 'success'} cannot publish',
      () async {
        final provider = _Provider()..ignoreCancellation = true;
        final owner = ModernBookNlpAnalysis(() async => provider);
        addTearDown(owner.shutdown);
        owner.offer(request(1));
        owner.enable();
        await until(() => provider.started.length == 1);
        owner.invalidateWindow();
        owner.offer(request(2, source: 'replacement'));
        if (fails) {
          provider.replies.first.completeError(
            StateError('Obsolete model error'),
          );
        } else {
          provider.replies.first.complete({'quotes': [], 'source': 'obsolete'});
        }
        await until(() => provider.started.length == 2);
        expect(owner.error, isNull);
        expect(owner.result, isNull);
        expect(owner.completedWindows, 0);
        provider.replies.last.complete({'quotes': [], 'source': 'replacement'});
        await until(() => !owner.busy);
        expect(owner.result!['source'], 'replacement');
        expect(owner.completedWindows, 1);
      },
    );
  }
}
