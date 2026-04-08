import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_voice_assignment.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/voice_preview_state.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/theme/read_aloud_theme.dart';
import 'package:read_aloud/src/widgets/voice_management_dialog.dart';

void main() {
  testWidgets('groups narrator and character assignments with override state', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? changedCastId;
    String? changedVoiceId;
    String? clearedCastId;
    String? previewVoiceId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceManagementDialog(
            isCharacterModeEnabled: true,
            voiceLibrary: <VoiceLibraryEntry>[
              VoiceLibraryEntry(
                voice: _voice(
                  id: 'af_bella',
                  label: 'Bella',
                  gender: VoiceGender.female,
                  qualityGrade: 'A-',
                  traits: const <String>['warm'],
                  description: 'Balanced and clear.',
                ),
                isBundled: true,
                isInstalled: true,
              ),
              VoiceLibraryEntry(
                voice: _voice(id: 'am_michael', label: 'Michael'),
                isBundled: false,
                isInstalled: true,
              ),
            ],
            availableVoices: <VoiceProfile>[
              _voice(
                id: 'af_bella',
                label: 'Bella',
                gender: VoiceGender.female,
                qualityGrade: 'A-',
                traits: const <String>['warm'],
                description: 'Balanced and clear.',
              ),
              _voice(id: 'am_michael', label: 'Michael'),
            ],
            characterCastRegistry: _richRegistry(),
            castVoiceAssignments: CastVoiceAssignmentSet(
              documentId: 'doc_1',
              assignmentVersion: 'v1',
              assignments: <CastVoiceAssignment>[
                CastVoiceAssignment(
                  castId: 'cast_narrator',
                  effectiveVoiceId: 'af_bella',
                  decisionKind: VoiceAssignmentDecisionKind.automatic,
                  automaticVoiceId: 'af_bella',
                ),
                CastVoiceAssignment(
                  castId: 'cast_character_jennifer',
                  effectiveVoiceId: 'am_michael',
                  decisionKind: VoiceAssignmentDecisionKind.userOverride,
                  automaticVoiceId: 'af_bella',
                  userOverrideVoiceId: 'am_michael',
                ),
              ],
            ),
            selectedVoiceId: 'af_bella',
            previewStateForVoice: (_) => VoicePreviewState.idle,
            onClose: () {},
            onSelectLibraryVoice: (_) {},
            onInstallVoice: (_) {},
            onToggleVoicePreview: (voiceId) {
              previewVoiceId = voiceId;
            },
            onAssignCastVoice: (castId, voiceId) {
              changedCastId = castId;
              changedVoiceId = voiceId;
            },
            onClearCastVoiceOverride: (castId) {
              clearedCastId = castId;
            },
          ),
        ),
      ),
    );

    expect(find.text('Cast Assignments'), findsOneWidget);
    expect(find.text('Narrator'), findsOneWidget);
    expect(find.text('Characters'), findsOneWidget);
    expect(find.text('Jennifer'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Overridden'), findsOneWidget);
    expect(find.text('Automatic voice: Bella (en-US)'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Balanced and clear.'), findsWidgets);
    expect(find.text('Use Automatic Assignment'), findsOneWidget);

    await tester.tap(find.byTooltip('Preview voice').first);
    await tester.pump();

    expect(previewVoiceId, 'af_bella');

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bella (en-US)').last);
    await tester.pumpAndSettle();

    expect(changedCastId, 'cast_character_jennifer');
    expect(changedVoiceId, 'af_bella');

    await tester.tap(
      find.widgetWithText(TextButton, 'Use Automatic Assignment'),
    );
    await tester.pumpAndSettle();

    expect(clearedCastId, 'cast_character_jennifer');
  });

  testWidgets('reduces to narrator management when no characters exist', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceManagementDialog(
            isCharacterModeEnabled: false,
            voiceLibrary: <VoiceLibraryEntry>[
              VoiceLibraryEntry(
                voice: _voice(id: 'af_bella', label: 'Bella'),
                isBundled: true,
                isInstalled: true,
              ),
            ],
            availableVoices: <VoiceProfile>[
              _voice(id: 'af_bella', label: 'Bella'),
            ],
            characterCastRegistry: _narratorOnlyRegistry(),
            castVoiceAssignments: CastVoiceAssignmentSet(
              documentId: 'doc_2',
              assignmentVersion: 'v1',
              assignments: <CastVoiceAssignment>[
                CastVoiceAssignment(
                  castId: 'cast_narrator',
                  effectiveVoiceId: 'af_bella',
                  decisionKind: VoiceAssignmentDecisionKind.automatic,
                  automaticVoiceId: 'af_bella',
                ),
              ],
            ),
            selectedVoiceId: 'af_bella',
            previewStateForVoice: (_) => VoicePreviewState.idle,
            onClose: () {},
            onSelectLibraryVoice: (_) {},
            onInstallVoice: (_) {},
            onToggleVoicePreview: (_) {},
            onAssignCastVoice: (_, _) {},
            onClearCastVoiceOverride: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Narrator'), findsOneWidget);
    expect(find.text('Characters'), findsNothing);
  });

  testWidgets('uses readable dark-theme card and field surfaces', (
    WidgetTester tester,
  ) async {
    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFE9C46A),
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF171B22),
        onSurface: const Color(0xFFE8EDF5),
        surfaceContainerHighest: const Color(0xFF202734),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: VoiceManagementDialog(
            isCharacterModeEnabled: false,
            voiceLibrary: <VoiceLibraryEntry>[
              VoiceLibraryEntry(
                voice: _voice(id: 'af_bella', label: 'Bella'),
                isBundled: true,
                isInstalled: true,
              ),
            ],
            availableVoices: <VoiceProfile>[
              _voice(id: 'af_bella', label: 'Bella'),
            ],
            characterCastRegistry: _narratorOnlyRegistry(),
            castVoiceAssignments: CastVoiceAssignmentSet(
              documentId: 'doc_2',
              assignmentVersion: 'v1',
              assignments: <CastVoiceAssignment>[
                CastVoiceAssignment(
                  castId: 'cast_narrator',
                  effectiveVoiceId: 'af_bella',
                  decisionKind: VoiceAssignmentDecisionKind.automatic,
                  automaticVoiceId: 'af_bella',
                ),
              ],
            ),
            selectedVoiceId: 'af_bella',
            previewStateForVoice: (_) => VoicePreviewState.idle,
            onClose: () {},
            onSelectLibraryVoice: (_) {},
            onInstallVoice: (_) {},
            onToggleVoicePreview: (_) {},
            onAssignCastVoice: (_, _) {},
            onClearCastVoiceOverride: (_) {},
          ),
        ),
      ),
    );

    final card = tester.widget<DecoratedBox>(
      find.byKey(const Key('voice-assignment-card-Narrator')),
    );
    final cardDecoration = card.decoration as BoxDecoration;
    expect(cardDecoration.color, ReadAloudThemeTokens.dark.elevatedSurface);

    final narratorField = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    expect(narratorField.decoration.fillColor, isNull);
  });

  testWidgets(
    'assigns an installed library voice directly to a character in character mode',
    (WidgetTester tester) async {
      String? assignedCastId;
      String? assignedVoiceId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceManagementDialog(
              isCharacterModeEnabled: true,
              voiceLibrary: <VoiceLibraryEntry>[
                VoiceLibraryEntry(
                  voice: _voice(id: 'am_michael', label: 'Michael'),
                  isBundled: false,
                  isInstalled: true,
                ),
              ],
              availableVoices: <VoiceProfile>[
                _voice(id: 'af_bella', label: 'Bella'),
                _voice(id: 'am_michael', label: 'Michael'),
              ],
              characterCastRegistry: _richRegistry(),
              castVoiceAssignments: CastVoiceAssignmentSet(
                documentId: 'doc_1',
                assignmentVersion: 'v1',
                assignments: <CastVoiceAssignment>[
                  CastVoiceAssignment(
                    castId: 'cast_narrator',
                    effectiveVoiceId: 'af_bella',
                    decisionKind: VoiceAssignmentDecisionKind.automatic,
                    automaticVoiceId: 'af_bella',
                  ),
                ],
              ),
              selectedVoiceId: 'af_bella',
              previewStateForVoice: (_) => VoicePreviewState.idle,
              onClose: () {},
              onSelectLibraryVoice: (_) {},
              onInstallVoice: (_) {},
              onToggleVoicePreview: (_) {},
              onAssignCastVoice: (castId, voiceId) {
                assignedCastId = castId;
                assignedVoiceId = voiceId;
              },
              onClearCastVoiceOverride: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Assign', skipOffstage: false), findsOneWidget);
      expect(
        find.byType(DropdownButtonFormField<String>, skipOffstage: false),
        findsNWidgets(3),
      );
      expect(find.text('Use', skipOffstage: false), findsNothing);
      expect(
        find.byKey(const Key('voice-library-assign-button-am_michael')),
        findsNothing,
      );

      await tester.scrollUntilVisible(
        find.text('Assign', skipOffstage: false),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byType(DropdownButtonFormField<String>, skipOffstage: false).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jennifer').last);
      await tester.pumpAndSettle();

      expect(assignedCastId, 'cast_character_jennifer');
      expect(assignedVoiceId, 'am_michael');
    },
  );
}

CharacterCastRegistry _richRegistry() {
  return CharacterCastRegistry(
    documentId: 'doc_1',
    registryVersion: 'v1',
    entries: <CastEntry>[
      CastEntry(
        castId: 'cast_narrator',
        roleKind: CastEntryRoleKind.narrator,
        displayLabel: 'Narrator',
        confidence: 1,
        provenance: CastEntryProvenance.syntheticNarrator,
      ),
      CastEntry(
        castId: 'cast_character_jennifer',
        roleKind: CastEntryRoleKind.character,
        displayLabel: 'Jennifer',
        confidence: 0.9,
        provenance: CastEntryProvenance.attributedDialogueInference,
      ),
    ],
  );
}

CharacterCastRegistry _narratorOnlyRegistry() {
  return CharacterCastRegistry(
    documentId: 'doc_2',
    registryVersion: 'v1',
    entries: <CastEntry>[
      CastEntry(
        castId: 'cast_narrator',
        roleKind: CastEntryRoleKind.narrator,
        displayLabel: 'Narrator',
        confidence: 1,
        provenance: CastEntryProvenance.syntheticNarrator,
      ),
    ],
  );
}

VoiceProfile _voice({
  required String id,
  required String label,
  VoiceGender? gender,
  String? qualityGrade,
  List<String> traits = const <String>[],
  String? description,
}) {
  return VoiceProfile(
    id: id,
    label: label,
    locale: 'en-US',
    rawValue: <String, dynamic>{},
    gender: gender,
    qualityGrade: qualityGrade,
    traits: traits,
    description: description,
  );
}
