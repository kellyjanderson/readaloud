import 'package:flutter_test/flutter_test.dart';

import 'package:read_aloud/src/app.dart';

void main() {
  testWidgets('renders the reader shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ReadAloudApp());
    await tester.pump();

    expect(find.text('Read Aloud'), findsWidgets);
    expect(find.text('Reader Controls'), findsOneWidget);
    expect(find.text('Sample Document'), findsWidgets);
    expect(find.text('Play'), findsOneWidget);
  });
}
