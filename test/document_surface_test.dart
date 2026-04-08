import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/theme/read_aloud_theme.dart';
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

  testWidgets('follow request tick recenters even when auto-follow is idle', (
    WidgetTester tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    Widget buildSurface({required int followRequestTick}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 180,
            child: DocumentSurface(
              document: ReaderDocument.sample(),
              fontFamily: 'serif',
              fontScale: 1.6,
              focusedDisplayBlockId: 'b_6',
              autoFollowActive: false,
              followRequestTick: followRequestTick,
              scrollController: scrollController,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildSurface(followRequestTick: 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(scrollController.offset, 0);

    await tester.pumpWidget(buildSurface(followRequestTick: 1));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(scrollController.offset, greaterThan(0));
  });

  testWidgets('reading content resolves the editorial serif role', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 240,
            child: DocumentSurface(
              document: ReaderDocument.sample(),
              fontFamily: 'serif',
              fontScale: 1.0,
            ),
          ),
        ),
      ),
    );

    final html = tester.widget<Html>(find.byType(Html));
    expect(html.style['body']?.fontFamily, kReadingFontFamily);
  });
}
