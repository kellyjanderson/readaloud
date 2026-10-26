import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/speech_document.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/character_cast_registry_service.dart';
import 'package:read_aloud/src/services/cast_voice_assignment_service.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/speaker_attribution_service.dart';

List<SpeechSegment> halo(String prefix, List<SpeechSegment> segments) => [
  for (final segment in segments)
    SpeechSegment(
      segmentId: '${prefix}_${segment.segmentId}',
      blockId: '${prefix}_${segment.blockId}',
      ordinal: segment.ordinal,
      paragraphIndex: segment.paragraphIndex,
      sentenceIndex: segment.sentenceIndex,
      normalizedText: segment.normalizedText,
      wordCount: segment.wordCount,
      sourceRange: segment.sourceRange,
      displayAnchor: segment.displayAnchor,
      wordSpans: segment.wordSpans,
    ),
];

void main() {
  const service = CharacterCastRegistryService();
  test(
    'bounded preceding halo resolves first pronoun without promoting named non-speakers',
    () {
      final importer = DocumentImportService();
      final before = importer.importPastedText(
        'Beatrice stood with a tin against her chest. Ada had left a ladder.',
      );
      final current = importer.importPastedText('“Wait,” she said.');
      final attribution = const SpeakerAttributionService().attribute(
        speechDocument: current.speechDocument,
        baseAnnotations: current.baseSpeechAnnotations,
        contextSegments: halo('before', before.speechDocument.segments),
      );
      expect(
        attribution.outcomes.single.speakerReference!.displayLabel,
        'Beatrice',
      );
      final registry = service.build(
        dialogueAttributions: attribution,
        speechDocument: current.speechDocument,
        previousRegistry: before.characterCastRegistry,
        contextSegments: halo('before', before.speechDocument.segments),
      );
      expect(
        registry.characterEntries.single.castId,
        'cast_character_beatrice',
      );
      expect(
        registry.characterEntries.single.inferredGender,
        VoiceGender.female,
      );
    },
  );
  test(
    'bounded following tag belongs to current quote but not a subsequent quotation',
    () {
      final importer = DocumentImportService();
      final current = importer.importPastedText('“Wait.”');
      final after = importer.importPastedText('Mara said.');
      final attributed = const SpeakerAttributionService().attribute(
        speechDocument: current.speechDocument,
        baseAnnotations: current.baseSpeechAnnotations,
        followingContextSegments: halo('after', after.speechDocument.segments),
      );
      expect(attributed.outcomes.single.speakerReference!.displayLabel, 'Mara');
      final followingTurn = importer.importPastedText('Mara said, “Go.”');
      final unresolved = const SpeakerAttributionService().attribute(
        speechDocument: current.speechDocument,
        baseAnnotations: current.baseSpeechAnnotations,
        followingContextSegments: halo(
          'following',
          followingTurn.speechDocument.segments,
        ),
      );
      expect(unresolved.outcomes, hasLength(1));
      expect(unresolved.outcomes.single.speakerReference, isNull);
    },
  );
  test(
    'later alias merge retains first encounter, both evidence sets and redirects',
    () {
      final importer = DocumentImportService();
      final first = importer.importPastedText(
        'Lex lifted her hand. “Wait,” Lex said.\n\nAlex touched his coat. “Ready,” Alex replied.',
      );
      final later = importer.importPastedText(
        'Alex, known as Lex, looked outside. “Listen,” Lex said.',
      );
      final registry = service.build(
        dialogueAttributions: later.dialogueAttributions,
        speechDocument: later.speechDocument,
        previousRegistry: first.characterCastRegistry,
      );
      final entry = registry.characterEntries.single;
      expect(entry.castId, 'cast_character_lex');
      expect(registry.castIdRedirects['cast_character_alex'], entry.castId);
      expect(entry.identityProfile!.conflictFlag, isTrue);
      expect(entry.inferredGender, isNull);
      expect(
        entry.identityProfile!.evidenceSpans.map((e) => e.text).toSet(),
        containsAll({'his', 'her'}),
      );
      expect(
        entry.attributionIds.toSet(),
        containsAll(
          first.dialogueAttributions.outcomes.map((o) => o.attributionId),
        ),
      );
    },
  );
  test(
    'two compatible antecedents do not become a nearest-name attribution',
    () {
      final doc = DocumentImportService().importPastedText(
        'Mara lifted her hand. Saira folded her arms. “Wait,” she said.',
      );
      expect(doc.dialogueAttributions.outcomes.single.speakerReference, isNull);
    },
  );
  test(
    'explicit later alias declaration preserves original canonical ID and evidence',
    () {
      final importer = DocumentImportService();
      final first = importer.importPastedText(
        'Alex lifted his hand. “Wait,” Alex said.',
      );
      final later = importer.importPastedText(
        'Alex, known as Lex, opened the gate. “Ready,” Lex said.',
      );
      final registry = service.build(
        dialogueAttributions: later.dialogueAttributions,
        speechDocument: later.speechDocument,
        previousRegistry: first.characterCastRegistry,
      );
      expect(registry.characterEntries, hasLength(1));
      final entry = registry.characterEntries.single;
      expect(entry.castId, 'cast_character_alex');
      expect(entry.observedAliases.toSet(), {'Alex', 'Lex'});
      expect(entry.inferredGender, VoiceGender.male);
      expect(
        entry.identityProfile!.evidenceSpans.map((e) => e.text),
        contains('his'),
      );
    },
  );
  CharacterIdentityProfile infer(
    String prose,
    String name, {
    CharacterIdentityProfile? previous,
  }) {
    final doc = DocumentImportService().importPastedText(prose);
    return service.inferIdentity(
      speechDocument: doc.speechDocument,
      aliases: [name],
      previousProfile: previous,
    );
  }

  test(
    'pronoun precedence retains conflicting contextual evidence and offsets',
    () {
      final profile = infer('Alex was a man. Alex lifted her hand.', 'Alex');
      expect(profile.preferredVoiceGender, VoiceGender.female);
      expect(profile.genderSource, CharacterGenderEvidenceSource.pronoun);
      expect(profile.conflictFlag, isTrue);
      expect(profile.evidenceSpans.map((e) => e.text), contains('her'));
      expect(
        profile.evidenceSpans.map((e) => e.text),
        contains('Alex was a man'),
      );
      final doc = DocumentImportService().importPastedText(
        'Alex was a man. Alex lifted her hand.',
      );
      for (final evidence in profile.evidenceSpans) {
        final segment = doc.speechDocument.segments.firstWhere(
          (s) => s.segmentId == evidence.segmentId,
        );
        expect(
          segment.normalizedText.substring(
            evidence.startUtf16,
            evidence.endUtf16,
          ),
          evidence.text,
        );
      }
    },
  );

  test('unique adjacent subjects attach pronouns to separate characters', () {
    final prose =
        'Mara lifted the lid. She waited.\n\nJonah opened the gate. He paused.';
    expect(infer(prose, 'Mara').preferredVoiceGender, VoiceGender.female);
    expect(infer(prose, 'Jonah').preferredVoiceGender, VoiceGender.male);
    final ambiguous = infer(
      'Alex met Jonah. He waited. Alex was a woman.',
      'Alex',
    );
    expect(
      ambiguous.genderSource,
      CharacterGenderEvidenceSource.explicitIdentity,
    );
    expect(ambiguous.pronounProfile.countFor('he'), 0);
    expect(ambiguous.preferredVoiceGender, VoiceGender.female);
  });

  test('contradictory pronouns remain unknown even with a majority', () {
    final result = infer(
      'Alex lifted his hand. Alex touched his coat. Alex lifted her hand.',
      'Alex',
    );
    expect(result.preferredVoiceGender, isNull);
    expect(result.conflictFlag, isTrue);
    expect(result.genderSource, CharacterGenderEvidenceSource.pronoun);
  });

  test('neutral pronouns and stereotypes do not imply binary presentation', () {
    for (final prose in [
      'Sasha worked as a nurse and wore a dress.',
      'Sasha opened the box. They waited.',
      'Sasha waited beside Morgan. She opened the box.',
    ]) {
      expect(infer(prose, 'Sasha').preferredVoiceGender, isNull);
    }
  });

  test(
    'later pronouns replace contextual provenance without losing conflict',
    () {
      final first = infer('Alex was a man.', 'Alex');
      final second = infer('Alex lifted her hand.', 'Alex', previous: first);
      expect(second.preferredVoiceGender, VoiceGender.female);
      expect(second.genderSource, CharacterGenderEvidenceSource.pronoun);
      expect(second.conflictFlag, isTrue);
      expect(
        second.evidenceSpans.map((e) => e.text),
        contains('Alex was a man'),
      );
    },
  );

  test('incremental cast preserves IDs and named non-speakers stay absent', () {
    final importer = DocumentImportService();
    final first = importer.importPastedText(
      'Ellis left a note. “Wait,” Mara said.',
    );
    final second = importer.importPastedText('“Ready,” Jonah replied.');
    final registry = service.build(
      dialogueAttributions: second.dialogueAttributions,
      speechDocument: second.speechDocument,
      previousRegistry: first.characterCastRegistry,
    );
    expect(registry.characterEntries.map((e) => e.castId).toSet(), {
      'cast_character_mara',
      'cast_character_jonah',
    });
    expect(registry.documentId, second.speechDocument.documentId);
  });

  test('fixed catalog follows hints and manual redirects preserve choice', () {
    final profile = infer('Alex lifted his hand.', 'Alex');
    final registry = CharacterCastRegistry(
      documentId: 'doc',
      registryVersion: 'test',
      castIdRedirects: {'old_alex': 'cast_character_alex'},
      entries: [
        CastEntry(
          castId: 'cast_narrator',
          roleKind: CastEntryRoleKind.narrator,
          displayLabel: 'Narrator',
          confidence: 1,
          provenance: CastEntryProvenance.syntheticNarrator,
        ),
        CastEntry(
          castId: 'cast_character_alex',
          roleKind: CastEntryRoleKind.character,
          displayLabel: 'Alex',
          confidence: 1,
          provenance: CastEntryProvenance.attributedDialogueInference,
          identityProfile: profile,
        ),
      ],
    );
    const voices = [
      VoiceProfile(
        id: 'n',
        label: 'Narrator',
        locale: 'en-US',
        rawValue: {},
        gender: VoiceGender.female,
      ),
      VoiceProfile(
        id: 'f',
        label: 'High quality',
        locale: 'en-US',
        rawValue: {},
        gender: VoiceGender.female,
        qualityGrade: 'A+',
      ),
      VoiceProfile(
        id: 'm',
        label: 'Low quality',
        locale: 'en-US',
        rawValue: {},
        gender: VoiceGender.male,
        qualityGrade: 'D-',
      ),
    ];
    final automatic = const CastVoiceAssignmentService().resolve(
      CastVoiceAssignmentInput(
        characterCastRegistry: registry,
        availableVoices: voices,
        fallbackVoiceId: 'n',
        preferredNarratorVoiceId: 'n',
      ),
    );
    expect(automatic.forCastId('cast_character_alex')!.effectiveVoiceId, 'm');
    final manual = const CastVoiceAssignmentService().resolve(
      CastVoiceAssignmentInput(
        characterCastRegistry: registry,
        availableVoices: voices,
        fallbackVoiceId: 'n',
        preferredNarratorVoiceId: 'n',
        userOverrides: {'old_alex': 'f'},
      ),
    );
    expect(manual.forCastId('cast_character_alex')!.effectiveVoiceId, 'f');
  });
}
