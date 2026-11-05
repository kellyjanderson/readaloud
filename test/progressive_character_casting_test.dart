import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/dialogue_attribution.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/speech_document.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/document_preparation_supervisor.dart';
import 'package:read_aloud/src/services/cast_voice_assignment_service.dart';
import 'package:read_aloud/src/services/mlx_speech_worker_processor.dart';
import 'package:read_aloud/src/services/mlx_voice_library.dart';
import 'package:read_aloud/src/services/speaker_attribution_service.dart';
import 'package:read_aloud/src/services/reader_document_codec.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';

const prose =
    'Lena watched the ferry on Tuesdays. She knew its schedule. '
    '“It is late,” Lena said.\n\n'
    'Nora unwrapped the parcel. Her coat was damp. “It will come,” Nora replied.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native cast cache identity is scoped to Drama', () {
    expect(
      mlxTtsVersionFor(0, engineId: 'qwen3_tts_1_7b'),
      mlxTtsVersionFor(0),
    );
    expect(
      mlxTtsVersionFor(0, engineId: 'fish_drama3'),
      isNot(mlxTtsVersionFor(0)),
    );
  });

  test('refinement adds halo evidence absent from fast discovery', () {
    CharacterCastRegistry? early;
    final refined = DocumentImportService().importTextFragment(
      text: '“Wait,” Lena said.\n\nLena watched the boat.',
      title: 'Halo',
      sessionId: 'halo',
      sourceStart: 0,
      onCharacterDiscovery: (registry) => early = registry,
      followingUnit: const DocumentImportUnit(text: 'Lena is a woman.'),
    );
    expect(early!.characterEntries.single.inferredGender, isNull);
    expect(
      refined.characterCastRegistry.characterEntries.single.inferredGender,
      VoiceGender.female,
    );
  });

  test(
    'later discovery preserves existing automatic voices and temporal tags',
    () async {
      await MlxVoiceLibrary.load();
      final importer = DocumentImportService();
      final first = importer.importTextFragment(
        text: prose,
        title: 'Stable cast',
        sessionId: 'stable',
        sourceStart: 0,
      );
      final second = importer.importTextFragment(
        text:
            'Later Lena asked about the ferry. “Here,” Alice said. She waved.',
        title: 'Stable cast',
        sessionId: 'stable',
        sourceStart: prose.length,
      );
      final registry = CharacterCastRegistry(
        documentId: 'stable',
        registryVersion: 'test',
        entries: {
          ...{for (final e in first.characterCastRegistry.entries) e.castId: e},
          ...{
            for (final e in second.characterCastRegistry.entries) e.castId: e,
          },
        }.values.toList(),
      );
      final service = CastVoiceAssignmentService();
      CastVoiceAssignmentInput input(CharacterCastRegistry cast) =>
          CastVoiceAssignmentInput(
            characterCastRegistry: cast,
            availableVoices: mlxVoicesFor('fish_drama3'),
            fallbackVoiceId: 'library_fishadrian',
            preferredNarratorVoiceId: 'library_fishadrian',
          );
      final before = service.resolve(input(first.characterCastRegistry));
      final after = service.resolve(input(registry));
      for (final character in first.characterCastRegistry.characterEntries) {
        expect(
          after.forCastId(character.castId)!.effectiveVoiceId,
          before.forCastId(character.castId)!.effectiveVoiceId,
        );
      }
      expect(
        registry.characterEntries.any((e) => e.castId.contains('later')),
        isFalse,
      );
    },
  );

  test(
    'fast identities and female evidence publish before deeper attribution',
    () {
      CharacterCastRegistry? early;
      final importer = DocumentImportService(
        speakerAttributionService: _ObservedAttribution(() {
          expect(early, isNotNull);
          expect(early!.characterEntries.map((c) => c.displayLabel), [
            'Lena',
            'Nora',
          ]);
          expect(
            early!.characterEntries.map((c) => c.inferredGender),
            everyElement(VoiceGender.female),
          );
          expect(
            early!.characterEntries.every((c) => c.attributionIds.isEmpty),
            isTrue,
          );
        }),
      );
      final refined = importer.importTextFragment(
        text: prose,
        title: 'Synthetic cast',
        sessionId: 'one',
        sourceStart: 0,
        onCharacterDiscovery: (registry) => early = registry,
      );
      expect(
        refined.characterCastRegistry.characterEntries.map((c) => c.castId),
        early!.characterEntries.map((c) => c.castId),
      );
      expect(
        refined.characterCastRegistry.characterEntries.every(
          (c) => c.attributionIds.isNotEmpty,
        ),
        isTrue,
      );
      final reopened = decodeReaderDocument(
        const ReaderDocumentSerializationService().serializeToJsonString(
          refined,
        ),
      );
      expect(
        reopened.characterCastRegistry.characterEntries.map(
          (c) => c.inferredGender,
        ),
        everyElement(VoiceGender.female),
      );
    },
  );

  test(
    'Fish automatic cast matches evidence and native references regardless of catalog order',
    () async {
      await MlxVoiceLibrary.load();
      final registry = DocumentImportService()
          .importPastedText(prose)
          .characterCastRegistry;
      final voices = mlxVoicesFor('fish_drama3');
      expect(
        voices
            .where(
              (v) =>
                  v.gender == VoiceGender.female &&
                  v.rawValue['provider'] == 'Fish Official',
            )
            .length,
        greaterThanOrEqualTo(5),
      );
      final ids = <List<String>>[];
      for (final catalog in [voices, voices.reversed.toList()]) {
        final assignments = const CastVoiceAssignmentService().resolve(
          CastVoiceAssignmentInput(
            characterCastRegistry: registry,
            availableVoices: catalog,
            fallbackVoiceId: 'library_fishadrian',
            preferredNarratorVoiceId: 'library_fishadrian',
          ),
        );
        final selected = registry.characterEntries
            .map((c) => assignments.forCastId(c.castId)!.effectiveVoiceId)
            .toList();
        ids.add(selected);
        for (final id in selected) {
          final voice = voices.singleWhere((v) => v.id == id);
          expect(voice.gender, VoiceGender.female);
          expect(voice.rawValue['provider'], 'Fish Official');
        }
        expect(selected.toSet(), hasLength(2));
      }
      expect(ids.first, ids.last);
      final manual = const CastVoiceAssignmentService().resolve(
        CastVoiceAssignmentInput(
          characterCastRegistry: registry,
          availableVoices: voices,
          fallbackVoiceId: 'library_fishadrian',
          userOverrides: {'cast_character_lena': 'library_fishadrian'},
        ),
      );
      expect(
        manual.forCastId('cast_character_lena')!.effectiveVoiceId,
        'library_fishadrian',
      );
    },
  );

  test(
    'fragment boundary preserves dialogue alternation and does not leak into next work',
    () {
      const first = '“Ready,” Alice said.\n\n“Yes,” Bob replied.';
      const second = '“Then let us go.”\n\n“Lead the way.”';
      final importer = DocumentImportService();
      final a = importer.importTextFragment(
        text: first,
        title: 'Synthetic',
        sessionId: 'one',
        sourceStart: 0,
      );
      final b = importer.importTextFragment(
        text: second,
        title: 'Synthetic',
        sessionId: 'one',
        sourceStart: first.length + 2,
      );
      final speakers = [
        ...a.dialogueAttributions.outcomes,
        ...b.dialogueAttributions.outcomes,
      ].map((o) => o.speakerReference?.displayLabel);
      expect(speakers, ['Alice', 'Bob', 'Alice', 'Bob']);
      final other = importer.importTextFragment(
        text: second,
        title: 'Other',
        sessionId: 'two',
        sourceStart: 0,
      );
      expect(other.characterCastRegistry.characterEntries, isEmpty);
    },
  );

  test('discovery does not turn quoted name tags into real speakers', () {
    final doc = DocumentImportService().importPastedText(
      '“Ed said it was blue,” Lena said.',
    );
    expect(
      doc.characterCastRegistry.characterEntries.map((c) => c.displayLabel),
      ['Lena'],
    );
  });

  test(
    'native worker discovery precedes refined range and cancellation suppresses refinement',
    () async {
      for (final cancel in [false, true]) {
        final supervisor = DocumentPreparationSupervisor();
        final events = <String>[];
        final result = await supervisor.prepareRanges(
          DocumentPreparationRequest(
            ownerId: 'test',
            revision: 1,
            kind: DocumentPreparationKind.pastedText,
            text: prose,
          ),
          onCharacterDiscovery: (value) {
            expect(value.sequence, 1);
            expect(value.registry.characterEntries, hasLength(2));
            events.add('discovery');
            if (cancel) supervisor.cancel();
          },
          onPublication: (value) async {
            events.add('refined');
          },
        );
        await supervisor.shutdown();
        expect(events, cancel ? ['discovery'] : ['discovery', 'refined']);
        expect(
          result.outcome,
          cancel
              ? DocumentPreparationOutcome.cancelled
              : DocumentPreparationOutcome.ready,
        );
      }
    },
  );
}

class _ObservedAttribution extends SpeakerAttributionService {
  _ObservedAttribution(this.observe);
  final void Function() observe;
  @override
  DialogueAttributionSet attribute({
    required SpeechDocument speechDocument,
    required BaseSpeechAnnotationSet baseAnnotations,
    List<SpeechSegment> contextSegments = const [],
    List<SpeechSegment> followingContextSegments = const [],
    List<SpeechAnnotation> contextAnnotations = const [],
  }) {
    observe();
    return super.attribute(
      speechDocument: speechDocument,
      baseAnnotations: baseAnnotations,
      contextSegments: contextSegments,
      followingContextSegments: followingContextSegments,
      contextAnnotations: contextAnnotations,
    );
  }
}
