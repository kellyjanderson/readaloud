import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/modernbooknlp_analysis.dart';
import 'package:read_aloud/src/widgets/modernbooknlp_settings.dart';

class _Analysis extends ModernBookNlpAnalysis {
  _Analysis() : super(() async => throw StateError('Runtime unavailable'));
  void publish(Map<String, dynamic> value) {
    progress = value;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'stable actions, measured bars and actionable errors without spinning',
    (tester) async {
      final owner = _Analysis();
      addTearDown(owner.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: ModernBookNlpSettings(analysis: owner),
            ),
          ),
        ),
      );
      expect(find.text('Prepare and evaluate'), findsOneWidget);
      owner.publish({
        'message': 'Downloading model',
        'completed': 25,
        'total': 100,
        'unit': 'bytes',
      });
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.25,
      );
      owner.publish({
        'message': 'Loading analysis model',
        'completed': 0,
        'total': null,
      });
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byKey(const Key('modernbooknlp-prepare')));
      await tester.pumpAndSettle();
      expect(find.text('Retry analysis'), findsOneWidget);
      expect(find.textContaining('Runtime unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
