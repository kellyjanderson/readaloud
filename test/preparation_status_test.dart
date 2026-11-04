import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/widgets/preparation_status.dart';

void main() {
  Future<void> render(
    WidgetTester tester,
    List<PreparationProgress> stages, {
    bool failed = false,
    VoidCallback? cancel,
    VoidCallback? retry,
    TtsResourceProgress? resource,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PreparationStatus(
                progress: stages,
                isImporting: stages.isNotEmpty && !failed,
                isInitializing: resource != null,
                isComplete: stages.isEmpty,
                resourceProgress: resource,
                onCancel: cancel,
                onRetry: retry,
              ),
              const Text('Reader stays here'),
            ],
          ),
        ),
      ),
    );
  }

  const working = PreparationProgress(
    stage: PreparationStage.parsing,
    state: PreparationWorkState.working,
    completed: 4,
    total: 8,
    unit: 'blocks',
  );

  testWidgets(
    'simple summary has measured progress, keyboard cancellation and optional details',
    (tester) async {
      var cancelled = 0;
      await render(tester, [working], cancel: () => cancelled++);
      final anchor = tester.getTopLeft(find.text('Reader stays here'));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
      expect(find.byKey(const ValueKey('activity-parsing')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(cancelled, 1);
      await tester.tap(find.text('Activity'));
      await tester.pump();
      expect(find.byKey(const ValueKey('activity-parsing')), findsOneWidget);
      await tester.tap(find.text('Hide activity'));
      await tester.pump();
      await render(tester, []);
      expect(find.text('Ready to read'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Reader stays here')), anchor);
    },
  );

  testWidgets(
    'unknown and finished-but-not-confirmed counters never spin or claim 100%',
    (tester) async {
      for (final p in [
        const PreparationProgress(
          stage: PreparationStage.parsing,
          state: PreparationWorkState.working,
          completed: 8,
          unit: 'blocks',
        ),
        const PreparationProgress(
          stage: PreparationStage.parsing,
          state: PreparationWorkState.working,
          completed: 8,
          total: 8,
          unit: 'blocks',
        ),
        working.withState(
          PreparationWorkState.waiting,
          waitingReason: 'Awaiting next input range',
        ),
      ]) {
        await render(tester, [p]);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.textContaining('100%'), findsNothing);
      }
      await render(
        tester,
        [],
        resource: const TtsResourceProgress(
          stage: 'modelLoad',
          message: 'Loading saved model',
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Loading saved model'), findsOneWidget);
    },
  );

  testWidgets(
    'active work precedes completed history; completion fades and restart cancels expiry',
    (tester) async {
      final done = working.withState(PreparationWorkState.complete);
      const active = PreparationProgress(
        stage: PreparationStage.persistence,
        state: PreparationWorkState.working,
        completed: 1,
        total: 4,
        unit: 'ranges',
      );
      await render(tester, [done, active]);
      await tester.tap(find.text('Activity'));
      await tester.pump();
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('activity-persistence')))
            .dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('activity-parsing'))).dy,
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('activity-parsing')),
            )
            .opacity,
        0,
      );
      await render(tester, [working, active]);
      await tester.pump(const Duration(seconds: 10));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('activity-parsing')),
            )
            .opacity,
        1,
      );
      await render(tester, [done, active]);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('activity-parsing')), findsNothing);
      expect(
        find.byKey(const ValueKey('activity-persistence')),
        findsOneWidget,
      );
    },
  );

  testWidgets('failures remain visible and recoverable after history expires', (
    tester,
  ) async {
    var retried = 0;
    await render(
      tester,
      [
        const PreparationProgress(
          stage: PreparationStage.parsing,
          state: PreparationWorkState.failed,
          completed: 8,
          unit: 'blocks',
          error: 'Unreadable source',
        ),
      ],
      failed: true,
      retry: () => retried++,
    );
    await tester.pump(const Duration(minutes: 1));
    expect(find.textContaining('Unreadable source'), findsOneWidget);
    await tester.tap(find.text('Retry document'));
    expect(retried, 1);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('narrow large text retains scrollable error and retry controls', (
    tester,
  ) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SizedBox(
              width: 300,
              child: PreparationStatus(
                progress: const [],
                isImporting: false,
                isInitializing: false,
                isComplete: false,
                startupError:
                    'Required speech assets are unavailable. Open a document or retry speech startup.',
                onRetryStartup: () => retried++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Retry speech'));
    expect(retried, 1);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -400),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
