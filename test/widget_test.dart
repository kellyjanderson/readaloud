import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:read_aloud/src/app.dart';

void main() {
  testWidgets('renders the reader shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ReadAloudApp());
    await tester.pump();

    expect(find.text('Read Aloud'), findsWidgets);
    expect(find.text('Reader Controls'), findsOneWidget);
    expect(find.text('For Probe'), findsNothing);
    expect(
      tester.widgetList<Title>(find.byType(Title)).any(
        (widget) => widget.title == 'Read Aloud - For Probe',
      ),
      isTrue,
    );
    expect(
      find.textContaining('Rich document surface with room for images'),
      findsNothing,
    );
    expect(
      find.textContaining(
        'Short phrases for tracing how "for" is realized by the TTS pipeline.',
      ),
      findsWidgets,
    );
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.byType(SelectionArea), findsWidgets);
  });

  testWidgets('does not overflow on short desktop-sized windows', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ReadAloudApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('For Probe'), findsNothing);
  });
}
