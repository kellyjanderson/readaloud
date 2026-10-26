import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/widgets/preparation_status.dart';

void main() {
  testWidgets(
    'actual stage counts stay honest across waiting, failure and retry',
    (tester) async {
      var cancelled = 0;
      var retried = 0;
      Future<void> render(
        PreparationProgress? stage, {
        bool failed = false,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  PreparationStatus(
                    progress: stage == null ? [] : [stage],
                    isImporting: stage != null && !failed,
                    isInitializing: false,
                    isComplete: stage == null,
                    onCancel: failed ? null : () => cancelled++,
                    onRetry: failed ? () => retried++ : null,
                  ),
                  const Text('Reader stays here'),
                ],
              ),
            ),
          ),
        );
      }

      await render(
        const PreparationProgress(
          stage: PreparationStage.parsing,
          state: PreparationWorkState.working,
          completed: 4,
          total: 8,
          unit: 'blocks',
        ),
      );
      final anchor = tester.getTopLeft(find.text('Reader stays here'));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.5,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(cancelled, 1);
      await render(
        const PreparationProgress(
          stage: PreparationStage.parsing,
          state: PreparationWorkState.waiting,
          completed: 8,
          total: 8,
          discovered: 8,
          unit: 'blocks',
          waitingReason: 'Awaiting next input range',
        ),
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(find.textContaining('total may grow'), findsOneWidget);
      expect(find.textContaining('Awaiting next input range'), findsOneWidget);
      await render(
        const PreparationProgress(
          stage: PreparationStage.parsing,
          state: PreparationWorkState.failed,
          completed: 8,
          unit: 'blocks',
          error: 'Unreadable source',
        ),
        failed: true,
      );
      expect(find.textContaining('total unknown'), findsOneWidget);
      await tester.tap(find.text('Retry document'));
      expect(retried, 1);
      expect(tester.getTopLeft(find.text('Reader stays here')), anchor);
      await render(null);
      expect(find.text('Ready to read'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Reader stays here')), anchor);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('status exposes startup retry and scrolls at narrow large text', (
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
                progress: const [
                  PreparationProgress(
                    stage: PreparationStage.persistence,
                    state: PreparationWorkState.waiting,
                    completed: 2,
                    total: 9,
                    unit: 'checkpoints',
                    waitingReason: 'Waiting for committed source coverage',
                  ),
                ],
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
    expect(find.textContaining('checkpoints'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
