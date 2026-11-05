import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/character.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/work_character_store.dart';

// Provider-independent oracle. Later providers must supply these same stable
// characters; their entity/quote accuracy is tested separately, never inferred
// from a correct voice ID. Add transitions here rather than replacing cases.
const catalog = [
  VoiceProfile(
    id: 'narrator',
    label: 'Narrator',
    locale: 'en',
    gender: VoiceGender.male,
    rawValue: {},
  ),
  VoiceProfile(
    id: 'female_a',
    label: 'A',
    locale: 'en',
    gender: VoiceGender.female,
    rawValue: {},
  ),
  VoiceProfile(
    id: 'female_b',
    label: 'B',
    locale: 'en',
    gender: VoiceGender.female,
    rawValue: {},
  ),
  VoiceProfile(
    id: 'male_a',
    label: 'C',
    locale: 'en',
    gender: VoiceGender.male,
    rawValue: {},
  ),
];

CastEntry person(String id, {VoiceGender? gender = VoiceGender.female}) =>
    CastEntry(
      castId: id,
      roleKind: CastEntryRoleKind.character,
      displayLabel: id,
      confidence: .9,
      provenance: CastEntryProvenance.providerOutput,
      observedAliases: [id],
      inferredGender: gender,
      inferredGenderConfidence: .9,
    );
CharacterCastRegistry cast(List<CastEntry> people) => CharacterCastRegistry(
  documentId: 'fragment',
  registryVersion: 'oracle',
  entries: [
    CastEntry(
      castId: 'cast_narrator',
      roleKind: CastEntryRoleKind.narrator,
      displayLabel: 'Narrator',
      confidence: 1,
      provenance: CastEntryProvenance.syntheticNarrator,
    ),
    ...people,
  ],
);

void main() {
  late WorkCharacterStore store;
  var sequence = 0;
  void publish(
    List<CastEntry> people, {
    int revision = 1,
    String work = 'work-a',
  }) {
    store.apply(
      CharacterAnalysisDelta(
        workId: work,
        sourceRevision: 'source-a',
        analysisRevision: revision,
        sequence: ++sequence,
        providerId: 'oracle',
        registry: cast(people),
      ),
    );
  }

  Map<String, String> resolve({
    String work = 'work-a',
    String engine = 'fish',
    List<VoiceProfile> voices = catalog,
  }) => {
    for (final assignment
        in store
            .resolve(
              workId: work,
              engineId: engine,
              voices: voices,
              narratorVoiceId: 'narrator',
            )
            .assignments)
      assignment.castId: assignment.effectiveVoiceId,
  };
  setUp(() {
    store = WorkCharacterStore();
    sequence = 0;
    store.begin(
      workId: 'work-a',
      sourceRevision: 'source-a',
      analysisRevision: 1,
    );
  });

  test(
    'VS01 repeated, reordered and enlarged cast retains compatible automatic voices',
    () {
      publish([person('Lena'), person('Nora')]);
      final expected = resolve();
      for (final people in [
        [person('Nora'), person('Lena')],
        [person('Alice'), person('Nora'), person('Lena')],
        [person('Nora')],
      ]) {
        publish(people);
        expect(resolve()['Lena'], expected['Lena']);
        expect(resolve()['Nora'], expected['Nora']);
      }
    },
  );

  test(
    'VS02 explicit choice survives contradictory inference and unavailable engine then A/B/A',
    () {
      publish([person('Lena')]);
      store.select('work-a', 'Lena', 'female_b');
      publish([person('Lena', gender: VoiceGender.male)]);
      expect(resolve()['Lena'], 'female_b');
      resolve(
        engine: 'other',
        voices: catalog.where((v) => v.id != 'female_b').toList(),
      );
      expect(
        store.character('work-a', 'Lena')!.selectedVoice.voiceId,
        'female_b',
      );
      expect(resolve()['Lena'], 'female_b');
    },
  );

  test('VS03 choosing automatic result is explicit and survives reopen', () {
    publish([person('Lena')]);
    final chosen = resolve()['Lena']!;
    store.select('work-a', 'Lena', chosen);
    store = WorkCharacterStore.fromJson(store.toJson());
    expect(
      store.character('work-a', 'Lena')!.selectedVoice.mode,
      VoiceSelectionMode.explicit,
    );
    expect(resolve()['Lena'], chosen);
  });

  test(
    'VS04 Reset survives reopen, stale analysis and repeated legacy migration',
    () {
      publish([person('Lena')]);
      store.select('work-a', 'Lena', 'male_a');
      store.select('work-a', 'Lena', null);
      final revision = store
          .character('work-a', 'Lena')!
          .selectedVoice
          .revision;
      store = WorkCharacterStore.fromJson(store.toJson());
      store.migrateLegacy({
        'work-a': {'Lena': 'male_a'},
      });
      store.begin(
        workId: 'work-a',
        sourceRevision: 'source-a',
        analysisRevision: 2,
      );
      publish([person('Lena', gender: VoiceGender.male)], revision: 1);
      expect(
        store.character('work-a', 'Lena')!.selectedVoice.revision,
        revision,
      );
      expect(
        store.character('work-a', 'Lena')!.selectedVoice.mode,
        VoiceSelectionMode.automatic,
      );
      expect(resolve()['Lena'], isNot('male_a'));
    },
  );

  test(
    'VS05 same-named characters in different works never share a selection',
    () {
      publish([person('Lena')]);
      store.select('work-a', 'Lena', 'male_a');
      store.begin(
        workId: 'work-b',
        sourceRevision: 'source-a',
        analysisRevision: 1,
      );
      publish([person('Lena')], work: 'work-b');
      expect(resolve(work: 'work-b')['Lena'], isNot('male_a'));
      expect(resolve()['Lena'], 'male_a');
    },
  );

  test(
    'VS06 new gender evidence may improve automatic match without editing selection intent',
    () {
      publish([person('Lena', gender: VoiceGender.male)]);
      expect(resolve()['Lena'], 'male_a');
      publish([person('Lena')]);
      expect(resolve()['Lena'], startsWith('female_'));
      expect(store.character('work-a', 'Lena')!.selectedVoice.revision, 0);
    },
  );

  test(
    'VS07 unknown future storage schema fails instead of erasing selections',
    () {
      expect(
        () => WorkCharacterStore.fromJson({'schema': 999}),
        throwsFormatException,
      );
    },
  );

  test(
    'VS08 stale success, wrong source, duplicate and cancelled deltas cannot edit a successor',
    () {
      publish([person('Lena')]);
      final before = store.character('work-a', 'Lena')!.revision;
      for (final delta in [
        CharacterAnalysisDelta(
          workId: 'work-a',
          sourceRevision: 'old-source',
          analysisRevision: 1,
          sequence: 99,
          providerId: 'oracle',
          registry: cast([person('Intruder')]),
        ),
        CharacterAnalysisDelta(
          workId: 'work-a',
          sourceRevision: 'source-a',
          analysisRevision: 1,
          sequence: 1,
          providerId: 'oracle',
          registry: cast([person('Intruder')]),
        ),
      ]) {
        expect(store.apply(delta), isFalse);
      }
      store.cancelAnalysis();
      publish([person('Intruder')]);
      expect(store.character('work-a', 'Intruder'), isNull);
      expect(store.character('work-a', 'Lena')!.revision, before);
    },
  );

  test(
    'VS09 alias redirect carries selection and old-ID publications cannot resurrect a duplicate',
    () {
      publish([person('Lena'), person('Lady Lena')]);
      store.select('work-a', 'Lady Lena', 'female_b');
      store.mergeEvidence(
        'work-a',
        CharacterCastRegistry(
          documentId: 'fragment',
          registryVersion: 'oracle',
          entries: cast([person('Lena')]).entries,
          castIdRedirects: {'Lady Lena': 'Lena'},
        ),
      );
      publish([person('Lady Lena')]);
      expect(
        store
            .entries('work-a')
            .where((e) => e.roleKind == CastEntryRoleKind.character),
        hasLength(1),
      );
      expect(store.character('work-a', 'Lady Lena')!.id, 'Lena');
      expect(resolve()['Lena'], 'female_b');
      store = WorkCharacterStore.fromJson(store.toJson());
      store.select('work-a', 'Lady Lena', null);
      expect(
        store.character('work-a', 'Lena')!.selectedVoice.mode,
        VoiceSelectionMode.automatic,
      );
    },
  );

  test(
    'VS10 conflicting alias choices retain both characters and choices for reconciliation',
    () {
      publish([person('Lena'), person('Lady Lena')]);
      store.select('work-a', 'Lena', 'female_a');
      store.select('work-a', 'Lady Lena', 'female_b');
      final evidence = CharacterCastRegistry(
        documentId: 'fragment',
        registryVersion: 'oracle',
        entries: cast([person('Lena')]).entries,
        castIdRedirects: {'Lady Lena': 'Lena'},
      );
      store.mergeEvidence('work-a', evidence);
      store.mergeEvidence('work-a', evidence);
      expect(store.redirects('work-a'), isEmpty);
      expect(resolve()['Lena'], 'female_a');
      expect(resolve()['Lady Lena'], 'female_b');
      expect(
        store.character('work-a', 'Lena')!.characterState.selectionConflicts,
        hasLength(1),
      );
    },
  );

  test(
    'VS11 explicit, implicit and scoped presented gender survive sparse refinement independently',
    () {
      final character = CastEntry(
        castId: 'Lena',
        roleKind: CastEntryRoleKind.character,
        displayLabel: 'Lena',
        confidence: 1,
        provenance: CastEntryProvenance.providerOutput,
        identityProfile: CharacterIdentityProfile(
          genderIdentityLabel: CharacterGenderIdentityLabel.female,
          genderConfidence: 1,
          genderSource: CharacterGenderEvidenceSource.explicitIdentity,
        ),
        characterState: CharacterState(
          explicitGender: GenderEvidence(
            value: CharacterGenderIdentityLabel.female,
          ),
          implicitGender: GenderEvidence(
            value: CharacterGenderIdentityLabel.male,
          ),
          presentedGender: [
            ScopedGenderEvidence(
              sourceRevision: 'source-a',
              segmentIds: ['s5'],
              evidence: GenderEvidence(
                value: CharacterGenderIdentityLabel.nonbinary,
              ),
            ),
          ],
        ),
      );
      publish([character]);
      expect(resolve()['Lena'], startsWith('female_'));
      publish([person('Lena', gender: null)]);
      store = WorkCharacterStore.fromJson(store.toJson());
      final restored = store.character('work-a', 'Lena')!;
      expect(
        restored.explicitGender.value,
        CharacterGenderIdentityLabel.female,
      );
      expect(restored.implicitGender.value, CharacterGenderIdentityLabel.male);
      expect(restored.presentedGender.single.segmentIds, ['s5']);
      expect(
        restored.presentedGender.single.evidence.value,
        CharacterGenderIdentityLabel.nonbinary,
      );
      expect(resolve()['Lena'], startsWith('female_'));
    },
  );

  test(
    'VS12 canonical work alias and stale document import cannot resurrect Reset',
    () {
      publish([person('Lena')]);
      store.select('work-a', 'Lena', 'male_a');
      final imported = store.registry('work-a', documentId: 'canonical');
      store.select('work-a', 'Lena', null);
      store.associate('work-a', 'canonical');
      store = WorkCharacterStore.fromJson(store.toJson());
      store.restoreDocument('imported-copy', imported);
      store.migrateLegacy({
        'canonical': {'Lena': 'male_a'},
      });
      for (final key in ['work-a', 'canonical', 'imported-copy']) {
        expect(
          store.character(key, 'Lena')!.selectedVoice.mode,
          VoiceSelectionMode.automatic,
        );
        expect(resolve(work: key)['Lena'], startsWith('female_'));
      }
    },
  );

  test(
    'VS13 captured persistence and caller-owned collections are immutable',
    () {
      final voices = <String, String>{'fish': 'female_a'};
      final state = CharacterState(automaticVoices: voices);
      voices['fish'] = 'male_a';
      expect(state.automaticVoices['fish'], 'female_a');
      publish([person('Lena')]);
      store.select('work-a', 'Lena', 'female_a');
      final captured = store.snapshot();
      store.select('work-a', 'Lena', 'female_b');
      expect(
        captured.restore().character('work-a', 'Lena')!.selectedVoice.voiceId,
        'female_a',
      );
    },
  );

  test(
    'VS14 available voices may reorder or temporarily disappear without erasing intent',
    () {
      publish([person('Lena'), person('Nora')]);
      final first = resolve();
      expect(resolve(voices: catalog.reversed.toList()), first);
      store.select('work-a', 'Lena', 'female_b');
      final missing = store.resolve(
        workId: 'work-a',
        engineId: 'fish',
        voices: catalog.where((v) => v.id != 'female_b').toList(),
        narratorVoiceId: 'narrator',
      );
      expect(missing.forCastId('Lena')!.effectiveVoiceId, isNot('female_b'));
      expect(
        store.character('work-a', 'Lena')!.selectedVoice.voiceId,
        'female_b',
      );
      expect(resolve()['Lena'], 'female_b');
    },
  );
  test(
    'VS19 correcting an earlier automatic gender must not steal a later character voice',
    () {
      publish([person('Lena', gender: VoiceGender.male), person('Nora')]);
      final nora = resolve()['Nora'];
      publish([person('Lena'), person('Nora')]);
      final after = resolve();
      expect(after['Lena'], startsWith('female_'));
      expect(after['Nora'], nora);
      expect(after['Lena'], isNot(after['Nora']));
    },
  );
}
