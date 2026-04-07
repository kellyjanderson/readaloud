import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_voice_assignment.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/cast_voice_assignment_service.dart';

void main() {
  group('CastVoiceAssignmentService', () {
    const service = CastVoiceAssignmentService();

    test(
      'assigns narrator and characters deterministically from available voices',
      () {
        final assignments = service.resolve(
          CastVoiceAssignmentInput(
            characterCastRegistry: _registry(),
            availableVoices: <VoiceProfile>[
              _voice(
                id: 'am_michael',
                label: 'Michael',
                qualityGrade: 'C+',
                gender: VoiceGender.male,
              ),
              _voice(
                id: 'af_bella',
                label: 'Bella',
                qualityGrade: 'A-',
                gender: VoiceGender.female,
              ),
              _voice(
                id: 'bf_emma',
                label: 'Emma',
                qualityGrade: 'B-',
                gender: VoiceGender.female,
              ),
            ],
            fallbackVoiceId: 'af_bella',
            preferredNarratorVoiceId: 'af_bella',
          ),
        );

        expect(
          assignments.forCastId('cast_narrator')?.effectiveVoiceId,
          'af_bella',
        );
        expect(
          assignments.forCastId('cast_character_jennifer')?.effectiveVoiceId,
          'am_michael',
        );
        expect(
          assignments.forCastId('cast_character_john')?.effectiveVoiceId,
          'bf_emma',
        );
        expect(
          assignments.forCastId('cast_character_jennifer')?.decisionKind,
          VoiceAssignmentDecisionKind.automatic,
        );
      },
    );

    test('stored assignments override automatic choices', () {
      final assignments = service.resolve(
        CastVoiceAssignmentInput(
          characterCastRegistry: _registry(),
          availableVoices: <VoiceProfile>[
            _voice(
              id: 'am_michael',
              label: 'Michael',
              qualityGrade: 'C+',
              gender: VoiceGender.male,
            ),
            _voice(
              id: 'af_bella',
              label: 'Bella',
              qualityGrade: 'A-',
              gender: VoiceGender.female,
            ),
          ],
          fallbackVoiceId: 'af_bella',
          preferredNarratorVoiceId: 'af_bella',
          storedAssignments: const <String, String>{
            'cast_character_jennifer': 'am_michael',
          },
        ),
      );

      expect(
        assignments.forCastId('cast_character_jennifer')?.effectiveVoiceId,
        'am_michael',
      );
      expect(
        assignments.forCastId('cast_character_jennifer')?.decisionKind,
        VoiceAssignmentDecisionKind.storedDocumentChoice,
      );
    });

    test('user overrides win over stored and automatic choices', () {
      final assignments = service.resolve(
        CastVoiceAssignmentInput(
          characterCastRegistry: _registry(),
          availableVoices: <VoiceProfile>[
            _voice(
              id: 'am_michael',
              label: 'Michael',
              qualityGrade: 'C+',
              gender: VoiceGender.male,
            ),
            _voice(
              id: 'af_bella',
              label: 'Bella',
              qualityGrade: 'A-',
              gender: VoiceGender.female,
            ),
          ],
          fallbackVoiceId: 'af_bella',
          preferredNarratorVoiceId: 'af_bella',
          storedAssignments: const <String, String>{
            'cast_character_jennifer': 'am_michael',
          },
          userOverrides: const <String, String>{
            'cast_character_jennifer': 'af_bella',
          },
        ),
      );

      expect(
        assignments.forCastId('cast_character_jennifer')?.effectiveVoiceId,
        'af_bella',
      );
      expect(
        assignments.forCastId('cast_character_jennifer')?.decisionKind,
        VoiceAssignmentDecisionKind.userOverride,
      );
    });

    test('falls back explicitly when no automatic voice is available', () {
      final assignments = service.resolve(
        CastVoiceAssignmentInput(
          characterCastRegistry: _registry(),
          availableVoices: const <VoiceProfile>[],
          fallbackVoiceId: 'af_bella',
        ),
      );

      expect(
        assignments.forCastId('cast_narrator')?.effectiveVoiceId,
        'af_bella',
      );
      expect(
        assignments.forCastId('cast_character_jennifer')?.decisionKind,
        VoiceAssignmentDecisionKind.fallback,
      );
    });
  });
}

CharacterCastRegistry _registry() {
  return CharacterCastRegistry(
    documentId: 'doc_1',
    registryVersion: 'registry-v1',
    entries: <CastEntry>[
      CastEntry(
        castId: 'cast_narrator',
        roleKind: CastEntryRoleKind.narrator,
        displayLabel: 'Narrator',
        confidence: 1.0,
        provenance: CastEntryProvenance.syntheticNarrator,
      ),
      CastEntry(
        castId: 'cast_character_jennifer',
        roleKind: CastEntryRoleKind.character,
        displayLabel: 'Jennifer',
        confidence: 0.8,
        provenance: CastEntryProvenance.attributedDialogueInference,
        attributionIds: const <String>['attr_0'],
      ),
      CastEntry(
        castId: 'cast_character_john',
        roleKind: CastEntryRoleKind.character,
        displayLabel: 'John',
        confidence: 0.8,
        provenance: CastEntryProvenance.attributedDialogueInference,
        attributionIds: const <String>['attr_1'],
      ),
    ],
  );
}

VoiceProfile _voice({
  required String id,
  required String label,
  String? qualityGrade,
  VoiceGender? gender,
}) {
  return VoiceProfile(
    id: id,
    label: label,
    locale: 'en-US',
    rawValue: <String, dynamic>{'name': label, 'locale': 'en-US'},
    gender: gender,
    qualityGrade: qualityGrade,
  );
}
