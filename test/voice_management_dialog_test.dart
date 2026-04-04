import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_voice_assignment.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/widgets/voice_management_dialog.dart';

void main() {
  testWidgets('groups narrator and character assignments with override state', (
    WidgetTester tester,
  ) async {
    String? changedCastId;
    String? changedVoiceId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceManagementDialog(
            voiceLibrary: <VoiceLibraryEntry>[
              VoiceLibraryEntry(
                voice: _voice(
                  id: 'af_bella',
                  label: 'Bella',
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
            onClose: () {},
            onSelectLibraryVoice: (_) {},
            onInstallVoice: (_) {},
            onAssignCastVoice: (castId, voiceId) {
              changedCastId = castId;
              changedVoiceId = voiceId;
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

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bella (en-US)').last);
    await tester.pumpAndSettle();

    expect(changedCastId, 'cast_character_jennifer');
    expect(changedVoiceId, 'af_bella');
  });

  testWidgets('reduces to narrator management when no characters exist', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceManagementDialog(
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
            onClose: () {},
            onSelectLibraryVoice: (_) {},
            onInstallVoice: (_) {},
            onAssignCastVoice: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.text('Narrator'), findsOneWidget);
    expect(find.text('Characters'), findsNothing);
  });
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
  String? qualityGrade,
  List<String> traits = const <String>[],
  String? description,
}) {
  return VoiceProfile(
    id: id,
    label: label,
    locale: 'en-US',
    rawValue: <String, dynamic>{},
    qualityGrade: qualityGrade,
    traits: traits,
    description: description,
  );
}
