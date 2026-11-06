import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/character.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/character_linguistic_evidence.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/modernbooknlp_character_adapter.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';
import 'package:read_aloud/src/services/work_character_store.dart';
import 'package:read_aloud/src/services/mlx_voice_library.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';

// Deliberately supplied upstream evidence, not generated from the implementation.
Map<String, dynamic> result(ModernBookNlpRequest r, {String cluster = '42'}) {
  final words = RegExp(r'[A-Za-z]+|[^\sA-Za-z]').allMatches(r.text).toList();
  int token(String word) => words.indexWhere((m) => m.group(0) == word);
  String entity(String id, String word, String prop, String cat) =>
      '$id\t${token(word)}\t${token(word)}\t$prop\t$cat\t$word';
  return {
    ...r.toJson(),
    'ok': true,
    'providerId': 'modernbooknlp-joint',
    'providerVersion': modernBookNlpRevision,
    'modelIdentity': modernBookNlpModelIdentity,
    'adapterVersion': modernBookNlpAdapterVersion,
    'tokenCount': words.length,
    'entities': [
      {
        'entityId': cluster,
        'mentions': [
          for (final word in ['Ada', 'She'])
            {
              'startUtf16': r.text.indexOf(word),
              'endUtf16': r.text.indexOf(word) + word.length,
              'text': word,
              'proper': word == 'Ada',
            },
        ],
      },
      {
        'entityId': '7',
        'mentions': [
          {
            'startUtf16': r.text.indexOf('Mira'),
            'endUtf16': r.text.indexOf('Mira') + 4,
            'text': 'Mira',
            'proper': true,
          },
        ],
      },
    ],
    'quotes': [
      {
        'startUtf16': r.text.indexOf('"'),
        'endUtf16': r.text.lastIndexOf('"') + 1,
        'entityId': cluster,
        'confidence': null,
      },
    ],
    'linguisticArtifacts': {
      'schema': 1,
      'pipeline': 'entity,quote,coref',
      'coordinateSystem': 'python-codepoint',
      'files': {
        'tokens':
            'token_ID_within_document\tbyte_onset\tbyte_offset\tword\n${[for (var i = 0; i < words.length; i++) '$i\t${words[i].start}\t${words[i].end}\t${words[i].group(0)}'].join('\n')}',
        'entities':
            'COREF\tstart_token\tend_token\tprop\tcat\ttext\n${[entity(cluster, 'Ada', 'PROP', 'PER'), entity(cluster, 'She', 'PRON', 'PER'), entity('7', 'Mira', 'PROP', 'PER'), entity('8', 'London', 'PROP', 'LOC')].join('\n')}',
        'quotes': 'quote_start\tquote_end\tchar_id\n',
        'book': jsonEncode({
          'characters': [
            {
              'id': int.parse(cluster),
              'agent': [
                {'w': 'smiled', 'i': token('smiled')},
              ],
              'patient': [],
              'mod': [],
              'poss': [],
              'g': {
                'inference': {'he/him/his': 0.99, 'she/her': 0.01},
              },
            },
          ],
        }),
      },
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const text = 'Ada said "Go". She smiled. London glittered. Mira waited.';
  ModernBookNlpRequest request(int n, {String source = 's'}) =>
      ModernBookNlpRequest(
        requestId: 'r$n',
        ownerId: 'o',
        workId: 'w',
        sourceRevision: source,
        analysisRevision: 1,
        sequence: n,
        text: text,
      );
  CharacterCastRegistry empty() => CharacterCastRegistry(
    documentId: 'd',
    registryVersion: 'test',
    entries: [
      CastEntry(
        castId: 'cast_narrator',
        roleKind: CastEntryRoleKind.narrator,
        displayLabel: 'Narrator',
        confidence: 1,
        provenance: CastEntryProvenance.syntheticNarrator,
      ),
    ],
  );
  WorkCharacterStore store() =>
      WorkCharacterStore()
        ..begin(workId: 'w', sourceRevision: 's', analysisRevision: 1);
  CharacterAnalysisDelta adapt(
    ModernBookNlpRequest r,
    CharacterCastRegistry registry, {
    String cluster = '42',
  }) => modernBookNlpCharacterDelta(
    request: r,
    result: result(r, cluster: cluster),
    registry: registry,
    turns: [
      ModernBookNlpTurnBinding(
        startUtf16: text.indexOf('"'),
        endUtf16: text.lastIndexOf('"') + 1,
        dialogue: const CharacterDialogueReference(
          attributionId: 'a',
          dialogueSpanId: 'q',
          segmentId: 's1',
          startWord: 0,
          endWord: 1,
        ),
      ),
    ],
  );

  test(
    'VS36 native Fish catalog matching is stable; explicit choice and Reset win',
    () async {
      await MlxVoiceLibrary.load();
      final voices = mlxVoicesFor('fish_drama3');
      final owner = store();
      final d = adapt(request(1), empty());
      owner.apply(d);
      final id = d.dialogues.single.castId!;
      String resolve(List<VoiceProfile> catalog) => owner
          .resolve(
            workId: 'w',
            engineId: 'fish_drama3',
            voices: catalog,
            narratorVoiceId: 'library_fishadrian',
          )
          .forCastId(id)!
          .effectiveVoiceId;
      final automatic = resolve(voices);
      expect(
        voices.singleWhere((v) => v.id == automatic).gender,
        VoiceGender.female,
      );
      owner.apply(
        adapt(request(2), owner.registry('w', documentId: 'd'), cluster: '99'),
      );
      expect(resolve(voices.reversed.toList()), automatic);
      owner.select('w', id, 'library_fishadrian');
      expect(resolve(voices), 'library_fishadrian');
      owner.select('w', id, null);
      expect(
        voices.singleWhere((v) => v.id == resolve(voices)).gender,
        VoiceGender.female,
      );
      // This verifies catalog resolution only; it makes no emitted-audio claim.
    },
  );

  test(
    'VS30 typed people include singletons; places and name priors cannot cast',
    () {
      final d = adapt(request(1), empty());
      expect(
        d.registry.characterEntries.map((e) => e.displayLabel),
        unorderedEquals(['Ada', 'Mira']),
      );

      final ada = d.registry.characterEntries.firstWhere(
        (e) => e.displayLabel == 'Ada',
      );
      expect(ada.inferredGender, VoiceGender.female);
      expect(ada.explicitGender.value, CharacterGenderIdentityLabel.unknown);
      expect(ada.presentedGender, isEmpty);
      final evidence = ada.characterState.linguisticEvidence.single;
      expect(evidence.referentialGender['he/him/his'], 0.99);
      expect(
        evidence.observations.any(
          (o) => o.kind == CharacterObservationKind.agent && o.text == 'smiled',
        ),
        true,
      );
      expect(d.dialogues.single.castId, ada.castId);
    },
  );
  test(
    'VS39 rejected alias cannot be resurrected through overlapping pronouns',
    () {
      final owner = store();
      final first = adapt(request(1), empty());
      owner.apply(first);
      final id = first.dialogues.single.castId!;
      owner.correctAlias('w', id, 'Ada', belongs: false);
      final corrected = adapt(request(2), owner.registry('w', documentId: 'd'));
      expect(corrected.dialogues.single.castId, isNull);
      owner.correctAlias('w', id, 'Ada', belongs: true);
      expect(owner.apply(corrected), false);
      expect(
        adapt(
          request(3),
          owner.registry('w', documentId: 'd'),
        ).dialogues.single.castId,
        id,
      );
    },
  );
  test(
    'VS31 local ID changes preserve canonical identity, evidence and explicit voice',
    () {
      final owner = store();
      final first = adapt(request(1), empty());
      owner.apply(first);
      final ada = first.registry.characterEntries.firstWhere(
        (e) => e.displayLabel == 'Ada',
      );
      owner.select('w', ada.castId, 'explicit-male-voice');
      final second = adapt(
        request(2),
        owner.registry('w', documentId: 'd'),
        cluster: '901',
      );
      expect(second.dialogues.single.castId, ada.castId);
      expect(owner.apply(second), true);
      expect(
        owner.character('w', ada.castId)!.selectedVoice.voiceId,
        'explicit-male-voice',
      );
      expect(
        owner.character('w', ada.castId)!.characterState.linguisticEvidence,
        hasLength(2),
      );
      final restored = WorkCharacterStore.fromJson(
        jsonDecode(jsonEncode(owner.toJson())),
      );
      expect(
        restored.character('w', ada.castId)!.selectedVoice.voiceId,
        'explicit-male-voice',
      );
      expect(
        restored.character('w', ada.castId)!.characterState.linguisticEvidence,
        hasLength(2),
      );
    },
  );
  test(
    'VS32 Reset and correction survive stale neural publication and reopen',
    () {
      final owner = store();
      final d = adapt(request(1), empty());
      owner.apply(d);
      final id = d.dialogues.single.castId!;
      owner.select('w', id, 'selected');
      final captured = adapt(request(2), owner.registry('w', documentId: 'd'));
      owner.select('w', id, null);
      expect(owner.apply(captured), true);
      expect(
        owner.character('w', id)!.selectedVoice.mode,
        VoiceSelectionMode.automatic,
      );
      final stale = adapt(request(3), owner.registry('w', documentId: 'd'));
      owner.correctGender('w', id, CharacterGenderIdentityLabel.male);
      expect(owner.apply(stale), false);
      expect(owner.character('w', id)!.inferredGender, VoiceGender.male);
      final restored = WorkCharacterStore.fromJson(
        jsonDecode(jsonEncode(owner.toJson())),
      );
      expect(restored.character('w', id)!.inferredGender, VoiceGender.male);
      owner.correctGender('w', id, null);
      expect(owner.apply(stale), false);
      expect(owner.character('w', id)!.inferredGender, VoiceGender.female);
    },
  );
  test(
    'VS33 conflicting canonical aliases abstain; typed source corruption is atomic',
    () {
      final d = adapt(request(1), empty());
      final ada = d.registry.characterEntries.firstWhere(
        (e) => e.displayLabel == 'Ada',
      );
      final registry = CharacterCastRegistry(
        documentId: 'd',
        registryVersion: 'test',
        entries: [
          ...d.registry.entries,
          CastEntry(
            castId: 'other',
            roleKind: CastEntryRoleKind.character,
            displayLabel: 'Ada',
            confidence: 1,
            provenance: CastEntryProvenance.sourceMetadata,
          ),
        ],
      );
      expect(adapt(request(2), registry).dialogues.single.castId, isNull);
      final owner = store()..apply(d);
      final bad = result(request(2));
      bad['linguisticArtifacts']['files']['tokens'] =
          (bad['linguisticArtifacts']['files']['tokens'] as String)
              .replaceFirst('Ada', 'Bad');
      expect(
        () => modernBookNlpCharacterDelta(
          request: request(2),
          result: bad,
          registry: registry,
          turns: [],
        ),
        throwsFormatException,
      );
      expect(owner.character('w', ada.castId)!.revision, 1);
    },
  );
}
