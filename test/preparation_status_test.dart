import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/reader_operation.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/widgets/preparation_status.dart';

void main() {
  testWidgets('Clear error is keyboard operable and carries exact identity', (
    tester,
  ) async {
    final failure = ReaderOperation(
      operationId: 'save-1',
      ownerKind: OperationOwnerKind.readingStage,
      ownerEpoch: 1,
      stage: 'persistence',
      scope: 'Save audio book',
      state: OperationState.failed,
      completedUnits: 0,
      unit: 'members',
      updatedAt: DateTime(2026),
      error: 'Destination unavailable',
      recoveryActions: [OperationRecoveryAction.clear],
    );
    ReaderOperation? cleared;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreparationStatus(
            progress: const [],
            operations: [failure],
            isImporting: false,
            isInitializing: false,
            isComplete: true,
            onClearFailure: (value) => cleared = value,
          ),
        ),
      ),
    );
    for (var i = 0; i < 6 && cleared == null; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused?.findAncestorWidgetOfExactType<TextButton>()?.key ==
          const Key('clear-operation-failure')) {
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
      }
    }
    expect(cleared, same(failure));
    expect(tester.takeException(), isNull);
  });
  testWidgets('failure owns summary and never borrows unrelated resource bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PreparationStatus(
            progress: [
              PreparationProgress(
                stage: PreparationStage.parsing,
                state: PreparationWorkState.failed,
                completed: 1,
                unit: 'blocks',
                error: 'Unreadable document',
              ),
            ],
            isImporting: false,
            isInitializing: true,
            isComplete: false,
            resourceProgress: TtsResourceProgress(
              stage: 'download',
              message: 'Downloading speech',
              completed: 2,
              total: 8,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Unreadable document'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('reduced motion removes completed row immediately at expiry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: PreparationStatus(
              activityExpanded: true,
              progress: [
                PreparationProgress(
                  stage: PreparationStage.parsing,
                  state: PreparationWorkState.complete,
                  completed: 8,
                  total: 8,
                  unit: 'words',
                ),
              ],
              isImporting: false,
              isInitializing: false,
              isComplete: true,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('activity-parsing')), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('activity-parsing')), findsNothing);
    // A reduced-motion row has no additional fade/removal timer to drain.
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'scoped operations preserve fast completion and active deep work',
    (tester) async {
      ReaderOperation scoped(String pass, OperationState state) =>
          ReaderOperation(
            operationId: pass,
            ownerKind: OperationOwnerKind.readingStage,
            ownerEpoch: 1,
            stage: 'analysis',
            scope: pass,
            state: state,
            completedUnits: 2,
            totalUnits: 4,
            unit: 'words',
            updatedAt: DateTime(2026),
          );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PreparationStatus(
              activityExpanded: true,
              progress: const [],
              operations: [
                scoped('fast', OperationState.succeeded),
                scoped('deep', OperationState.running),
              ],
              isImporting: false,
              isInitializing: false,
              isComplete: false,
            ),
          ),
        ),
      );
      expect(
        find.text('Finding characters · fast · succeeded'),
        findsOneWidget,
      );
      expect(find.text('Finding characters · deep · running'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Finding characters · deep · running')).dy,
        lessThan(
          tester
              .getTopLeft(find.text('Finding characters · fast · succeeded'))
              .dy,
        ),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('narrow large-text Activity toggle remains keyboard operable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool? preference;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: PreparationStatus(
              progress: const [],
              isImporting: false,
              isInitializing: false,
              isComplete: true,
              onActivityExpandedChanged: (value) => preference = value,
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6 && preference == null; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused != null &&
          focused.findAncestorWidgetOfExactType<TextButton>()?.key ==
              const Key('toggle-activity')) {
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
      }
    }
    expect(preference, isTrue);
    await tester.pump();
    expect(find.text('Hide activity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'mouse selection and Command-C work before and after resize',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      const error =
          'Synthesis failed before the remaining passage was prepared.\n'
          'ValueError: Expected finite, non-empty mono audio';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PreparationStatus(
              progress: [],
              isImporting: false,
              isInitializing: false,
              isComplete: false,
              message: error,
            ),
          ),
        ),
      );
      for (final width in [1200.0, 420.0, 900.0]) {
        await tester.binding.setSurfaceSize(Size(width, 600));
        await tester.pump();
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(error),
            matching: find.byType(RichText),
          ),
        );
        Offset position(int offset) => paragraph.localToGlobal(
          paragraph.getOffsetForCaret(TextPosition(offset: offset), Rect.zero) +
              const Offset(0, 8),
        );
        final mouse = await tester.startGesture(
          position(0),
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveTo(position(9));
        await mouse.up();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(copied, 'Synthesis', reason: 'selection at width $width');
        copied = null;
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('long errors can be selected and copied without truncation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final error = 'Failed to load speech: ${'diagnostic detail ' * 40}END';
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreparationStatus(
            progress: const [
              PreparationProgress(
                stage: PreparationStage.analysis,
                state: PreparationWorkState.failed,
                completed: 3,
                total: 9,
                unit: 'ranges',
                error: 'Analysis failed in a later range',
              ),
            ],
            isImporting: false,
            isInitializing: false,
            isComplete: false,
            startupError: error,
          ),
        ),
      ),
    );
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text(error), findsOneWidget);
    await tester.tap(find.byKey(const Key('copy-reader-status')));
    await tester.pump();
    expect(copied, contains(error));
    expect(copied, contains('Analysis failed in a later range'));
    expect(copied, contains('3 of 9 ranges'));
    expect(tester.takeException(), isNull);
  });
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
      // The selectable output is keyboard reachable before the action column.
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
