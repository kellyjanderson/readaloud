import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/widgets/reading_focus_recenter_button.dart';

void main() {
  testWidgets('invokes the recenter callback when tapped', (
    WidgetTester tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingFocusRecenterButton(
            onPressed: () {
              tapped = true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Recenter'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
