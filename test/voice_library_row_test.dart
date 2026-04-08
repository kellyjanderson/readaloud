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
                gender: VoiceGender.female,
                qualityGrade: 'A-',
                description: 'Balanced and smooth.',
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
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Included'), findsOneWidget);
    expect(find.text('Balanced and smooth.'), findsWidgets);
    expect(find.byTooltip('Preview voice'), findsOneWidget);
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
    expect(find.text('Balanced and smooth.'), findsWidgets);
  });

  testWidgets(
    'keeps metadata and preview slots stable when quality is missing',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: Column(
                children: [
                  VoiceLibraryRow(
                    entry: VoiceLibraryEntry(
                      voice: const VoiceProfile(
                        id: 'emma',
                        label: 'Emma',
                        locale: 'en-GB',
                        rawValue: <String, dynamic>{},
                        gender: VoiceGender.female,
                        qualityGrade: 'B-',
                      ),
                      isBundled: true,
                      isInstalled: true,
                    ),
                    onTogglePreview: () {},
                  ),
                  VoiceLibraryRow(
                    entry: VoiceLibraryEntry(
                      voice: const VoiceProfile(
                        id: 'george',
                        label: 'George',
                        locale: 'en-GB',
                        rawValue: <String, dynamic>{},
                        gender: VoiceGender.male,
                      ),
                      isBundled: false,
                      isInstalled: false,
                    ),
                    onTogglePreview: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final previewButtons = find.byTooltip('Preview voice');
      expect(previewButtons, findsNWidgets(2));

      final firstPreviewDx = tester.getCenter(previewButtons.first).dx;
      final secondPreviewDx = tester.getCenter(previewButtons.last).dx;

      expect((firstPreviewDx - secondPreviewDx).abs(), lessThanOrEqualTo(1.0));
    },
  );

  testWidgets(
    'keeps supporting text stable when descriptions are missing',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: Column(
                children: [
                  VoiceLibraryRow(
                    entry: VoiceLibraryEntry(
                      voice: const VoiceProfile(
                        id: 'emma',
                        label: 'Emma',
                        locale: 'en-GB',
                        rawValue: <String, dynamic>{},
                        gender: VoiceGender.female,
                        qualityGrade: 'B-',
                        description: 'Balanced and smooth.',
                      ),
                      isBundled: true,
                      isInstalled: true,
                    ),
                    onTogglePreview: () {},
                  ),
                  VoiceLibraryRow(
                    entry: VoiceLibraryEntry(
                      voice: const VoiceProfile(
                        id: 'george',
                        label: 'George',
                        locale: 'en-GB',
                        rawValue: <String, dynamic>{},
                        gender: VoiceGender.male,
                      ),
                      isBundled: false,
                      isInstalled: false,
                    ),
                    onTogglePreview: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final rows = find.byType(ListTile);
      expect(rows, findsNWidgets(2));
      expect(find.text('No description available'), findsOneWidget);

      final firstRowHeight = tester.getSize(rows.first).height;
      final secondRowHeight = tester.getSize(rows.last).height;

      expect((firstRowHeight - secondRowHeight).abs(), lessThanOrEqualTo(1.0));
    },
  );
}
