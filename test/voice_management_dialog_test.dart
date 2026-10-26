import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:read_aloud/src/models/voice_assignment_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_voice_assignment.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/voice_preview_state.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/theme/read_aloud_theme.dart';
import 'package:read_aloud/src/widgets/voice_management_dialog.dart';

void main() {
  testWidgets(
    'narrow voice dialog keeps loading and installed choices usable at large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final voices = [
        _voice(id: 'af_bella', label: 'Bella'),
        _voice(id: 'am_michael', label: 'Michael'),
      ];
      String? assigned;
      Future<void> render(List<VoiceProfile> installed) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Scaffold(
                body: VoiceManagementDialog(
                  isCharacterModeEnabled: true,
                  voiceLibrary: installed
                      .map(
                        (voice) => VoiceLibraryEntry(
                          voice: voice,
                          isBundled: true,
                          isInstalled: true,
                        ),
                      )
                      .toList(),
                  availableVoices: installed,
                  characterCastRegistry: _narratorOnlyRegistry(),
                  castVoiceAssignments: null,
                  selectedVoiceId: null,
                  previewStateForVoice: (_) => VoicePreviewState.idle,
                  onClose: () {},
                  onSelectLibraryVoice: (_) {},
                  onInstallVoice: (_) {},
                  onToggleVoicePreview: (_) {},
                  onAssignCastVoice: (castId, _) => assigned = castId,
                  onClearCastVoiceOverride: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await render([]);
      await tester.scrollUntilVisible(
        find.textContaining('Speech voices are loading'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await render(voices);
      final libraryControl = find.byKey(
        const Key('voice-library-assign-control-af_bella'),
      );
      await tester.scrollUntilVisible(
        libraryControl,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.descendant(
          of: libraryControl,
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: libraryControl,
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Narrator').last);
      await tester.pumpAndSettle();
      expect(assigned, 'cast_narrator');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'assignment feedback preserves current and requested choices and keyboard apply',
    (tester) async {
      var applied = 0;
      var retried = 0;
      Future<void> render(
        VoiceAssignmentPhase phase, {
        bool initial = false,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 480,
                  child: VoiceAssignmentFeedback(
                    state: VoiceAssignmentState(
                      requestedRevision: 2,
                      effectiveRevision: 1,
                      requestedDefaultVoiceId: 'am_michael',
                      effectiveDefaultVoiceId: 'af_bella',
                      phase: phase,
                      isInitialBuffering: initial,
                      errorMessage: phase == VoiceAssignmentPhase.failed
                          ? 'Voice unavailable.'
                          : null,
                    ),
                    voices: [
                      _voice(id: 'af_bella', label: 'Bella'),
                      _voice(id: 'am_michael', label: 'Michael'),
                    ],
                    castRegistry: _narratorOnlyRegistry(),
                    onApply: () => applied++,
                    onRetry: () => retried++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await render(VoiceAssignmentPhase.pending);
      expect(find.text('Current: Bella (en-US)'), findsOneWidget);
      expect(find.text('Pending: Michael (en-US)'), findsOneWidget);
      final before = tester.getTopLeft(
        find.byKey(const Key('voice-assignment-feedback')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(applied, 1);
      await render(VoiceAssignmentPhase.preparing, initial: true);
      expect(
        find.text('Preparing latest choices before playback.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('apply-voice-assignments')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('voice-assignment-feedback'))),
        before,
      );
      await render(VoiceAssignmentPhase.applying);
      expect(find.text('Applying choices and rebuffering.'), findsOneWidget);
      await render(VoiceAssignmentPhase.failed);
      expect(find.textContaining('Voice unavailable.'), findsOneWidget);
      await tester.tap(find.text('Retry voice change'));
      expect(retried, 1);
      expect(applied, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'assignment feedback remains scrollable at narrow width and large text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 280,
                child: VoiceAssignmentFeedback(
                  state: VoiceAssignmentState(
                    requestedRevision: 1,
                    phase: VoiceAssignmentPhase.failed,
                    errorMessage:
                        'An unusually long failure message explains which requested voice could not be prepared and asks for a retry.',
                  ),
                  voices: const [],
                  castRegistry: _narratorOnlyRegistry(),
                  onRetry: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Retry voice change'));
      await tester.pumpAndSettle();
      expect(find.text('Retry voice change').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Balanced and clear.'), findsWidgets);

    await tester.tap(find.byTooltip('Preview voice').first);
    await tester.pump();

    expect(previewVoiceId, 'af_bella');

    await tester.scrollUntilVisible(
      find.text('Jennifer'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Jennifer'), findsOneWidget);
    expect(find.text('Overridden'), findsOneWidget);
    expect(find.text('Automatic voice: Bella (en-US)'), findsOneWidget);

    await tester.ensureVisible(
      find.descendant(
        of: find.byKey(const Key('voice-assignment-card-Jennifer')),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('voice-assignment-card-Jennifer')),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bella (en-US)').last);
    await tester.pumpAndSettle();

    expect(changedCastId, 'cast_character_jennifer');
    expect(changedVoiceId, 'af_bella');

    await tester.ensureVisible(find.text('Use Automatic Assignment'));

    await tester.tap(
      find.widgetWithText(TextButton, 'Use Automatic Assignment'),
    );
    await tester.pumpAndSettle();

    expect(clearedCastId, 'cast_character_jennifer');
  });

  testWidgets('reduces to narrator management when no characters exist', (
    WidgetTester tester,
  ) async {
    String? narratorVoice;
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
              _voice(id: 'am_michael', label: 'Michael'),
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
            onSelectLibraryVoice: (voiceId) => narratorVoice = voiceId,
            onInstallVoice: (_) {},
            onToggleVoicePreview: (_) {},
            onAssignCastVoice: (_, _) {},
            onClearCastVoiceOverride: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Narrator'), findsOneWidget);
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<String>).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Michael (en-US)').last);
    await tester.pumpAndSettle();
    expect(narratorVoice, 'am_michael');
    await tester.scrollUntilVisible(
      find.text('Characters'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Characters'), findsOneWidget);
    expect(
      find.textContaining('No dialogue speakers discovered yet'),
      findsOneWidget,
    );
  });

  testWidgets('uses readable dark-theme card and field surfaces', (
    WidgetTester tester,
  ) async {
    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
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

      await tester.scrollUntilVisible(
        find.text('Assign', skipOffstage: false),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Assign', skipOffstage: false), findsOneWidget);
      expect(
        find.byType(DropdownButtonFormField<String>, skipOffstage: false),
        findsWidgets,
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
