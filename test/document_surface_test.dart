import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/theme/read_aloud_theme.dart';
import 'package:read_aloud/src/widgets/document_surface.dart';

void main() {
  testWidgets(
    'drag and copy selected passage from an inline reader range',
    (tester) async {
      const passage = 'Select this passage for a report.';
      String? copied;
      String? selected;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: SelectionArea(
              onSelectionChanged: (selection) =>
                  selected = selection?.plainText,
              child: DocumentSurface(
                document: DocumentImportService().importPastedText(passage),
                fontFamily: 'serif',
                fontScale: 1,
                inline: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = find.text(passage, findRichText: true).last;
      final start = tester.getTopLeft(paragraph) + const Offset(5, 18);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(235, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, contains('Select this'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(copied, selected);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

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
