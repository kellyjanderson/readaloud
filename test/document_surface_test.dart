import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/widgets/document_surface.dart';

void main() {
  testWidgets('auto-follow scrolls toward the focused block', (
    WidgetTester tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 180,
            child: DocumentSurface(
              document: ReaderDocument.sample(),
              fontFamily: 'serif',
              fontScale: 1.6,
              focusedDisplayBlockId: 'b_6',
              autoFollowActive: true,
              scrollController: scrollController,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(scrollController.offset, greaterThan(0));
  });

  testWidgets('manual scrolling yields follow control while active', (
    WidgetTester tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    var manualScrollCallbacks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 180,
            child: DocumentSurface(
              document: ReaderDocument.sample(),
              fontFamily: 'serif',
              fontScale: 1.6,
              focusedDisplayBlockId: 'b_6',
              autoFollowActive: true,
              scrollController: scrollController,
              onManualScrollWhileFollowing: () {
                manualScrollCallbacks += 1;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(manualScrollCallbacks, 0);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -80));
    await tester.pumpAndSettle();

    expect(manualScrollCallbacks, greaterThan(0));
  });
}
