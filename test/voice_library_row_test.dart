import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/widgets/voice_library_row.dart';

void main() {
  testWidgets('shows quality and install metadata directly in the row', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceLibraryRow(
            entry: VoiceLibraryEntry(
              voice: const VoiceProfile(
                id: 'af_bella',
                label: 'Bella',
                locale: 'en-US',
                rawValue: <String, dynamic>{},
                qualityGrade: 'A-',
              ),
              isBundled: true,
              isInstalled: true,
              statusMessage: 'Included with the app',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Bella'), findsOneWidget);
    expect(find.text('en-US'), findsOneWidget);
    expect(find.text('A-'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Included'), findsOneWidget);
  });

  testWidgets('shows info affordance only when metadata details exist', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              VoiceLibraryRow(
                entry: VoiceLibraryEntry(
                  voice: const VoiceProfile(
                    id: 'voice_with_meta',
                    label: 'Narrator One',
                    locale: 'en-US',
                    rawValue: <String, dynamic>{},
                    traits: <String>['warm', 'clear'],
                    description: 'Balanced and smooth.',
                    trainingDurationLabel: 'extended',
                  ),
                  isBundled: false,
                  isInstalled: true,
                ),
              ),
              VoiceLibraryRow(
                entry: VoiceLibraryEntry(
                  voice: const VoiceProfile(
                    id: 'voice_plain',
                    label: 'Plain Voice',
                    locale: 'en-US',
                    rawValue: <String, dynamic>{},
                  ),
                  isBundled: false,
                  isInstalled: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Narrator One'), findsWidgets);
    expect(find.text('warm'), findsOneWidget);
    expect(find.text('clear'), findsOneWidget);
    expect(find.text('Training: extended'), findsOneWidget);
    expect(find.text('Balanced and smooth.'), findsOneWidget);
  });
}
