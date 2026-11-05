import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/character.dart';
import 'package:read_aloud/src/models/character_cast_registry.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/services/character_analysis_adapter.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/work_character_store.dart';

void main() {
  const adapter = CharacterAnalysisAdapter();
  CharacterAnalysisDelta adapt(ReaderDocument doc, {int sequence = 1}) =>
      adapter.refined(
        workId: 'work',
        sourceRevision: 'source',
        analysisRevision: 7,
        sequence: sequence,
        document: doc,
      );
  WorkCharacterStore owner() =>
      WorkCharacterStore()
        ..begin(workId: 'work', sourceRevision: 'source', analysisRevision: 7);
  test(
    'VS20 independently labeled prose maps explicit speakers and preserves unknown',
    () {
      final importer = DocumentImportService();
      for (final entry in <String, List<String?>>{
        '“Close the gate,” Ada said.\n\n“Already closed,” Bruno replied.': [
          'Ada',
          'Bruno',
        ],
        '“Who is there?”': [null],
        '“Ed said it was blue,” Lena said.': ['Lena'],
        '“Stay here. Wait for me,” Ada said.': ['Ada'],
      }.entries) {
        final doc = importer.importPastedText(entry.key);
        final delta = adapt(doc);
        final bySpan = <String, String?>{};
        for (final turn in delta.dialogues) {
          bySpan[turn.dialogueSpanId] = turn.castId == null
              ? null
              : delta.registry.forCastId(turn.castId!)!.displayLabel;
          expect(doc.speechDocument.segmentIndexById, contains(turn.segmentId));
        }
        expect(bySpan.values, entry.value, reason: entry.key);
        expect(delta.providerVersion, doc.dialogueAttributions.providerVersion);
        expect(() => delta.dialogues.clear(), throwsUnsupportedError);
      }
    },
  );
  test(
    'VS21 whole and split publications preserve speaker sequence and selected voice',
    () {
      const first = '“Ready,” Alice said.\n\n“Yes,” Bob replied.';
      const second = '“Then let us go.”\n\n“Lead the way.”';
      final importer = DocumentImportService();
      final store = owner();
      CharacterCastRegistry? early;
      final a = importer.importTextFragment(
        text: first,
        title: 'Test',
        sessionId: 'one',
        sourceStart: 0,
        onCharacterDiscovery: (registry) => early = registry,
      );
      expect(
        store.apply(
          adapter.discovery(
            workId: 'work',
            sourceRevision: 'source',
            analysisRevision: 7,
            sequence: 1,
            registry: early!,
          ),
        ),
        isTrue,
      );
      final alice = early!.characterEntries.singleWhere(
        (e) => e.displayLabel == 'Alice',
      );
      store.select('work', alice.castId, 'chosen-older-rough-voice');
      final b = importer.importTextFragment(
        text: second,
        title: 'Test',
        sessionId: 'one',
        sourceStart: first.length + 2,
      );
      final deltas = [adapt(a), adapt(b, sequence: 2)];
      for (final delta in deltas) {
        expect(store.apply(delta), isTrue);
      }
      final split = deltas
          .expand(
            (d) => d.dialogues.map(
              (t) => d.registry.forCastId(t.castId!)!.displayLabel,
            ),
          )
          .toList();
      final whole = adapt(
        DocumentImportService().importPastedText('$first\n\n$second'),
      );
      expect(split, ['Alice', 'Bob', 'Alice', 'Bob']);
      expect(
        whole.dialogues.map(
          (t) => whole.registry.forCastId(t.castId!)!.displayLabel,
        ),
        split,
      );
      expect(
        store.character('work', alice.castId)!.selectedVoice.voiceId,
        'chosen-older-rough-voice',
      );
      expect(store.apply(deltas.first), isFalse);
      store.cancelAnalysis();
      expect(store.apply(adapt(b, sequence: 3)), isFalse);
    },
  );
  test('VS23 adapter refuses missing and ambiguous character links', () {
    final doc = DocumentImportService().importPastedText('“Wait,” Ada said.');
    final ada = doc.characterCastRegistry.characterEntries.single;
    for (final ambiguous in [false, true]) {
      final registry = CharacterCastRegistry(
        documentId: doc.characterCastRegistry.documentId,
        registryVersion: 'oracle',
        entries: [
          doc.characterCastRegistry.narratorEntry,
          if (ambiguous) ada,
          if (ambiguous)
            CastEntry(
              castId: 'other-ada',
              roleKind: CastEntryRoleKind.character,
              displayLabel: 'Another Ada',
              confidence: 1,
              provenance: CastEntryProvenance.providerOutput,
              attributionIds: ada.attributionIds,
            ),
        ],
      );
      final malformed = ReaderDocument.restored(
        title: doc.title,
        type: doc.type,
        displayHtml: doc.displayHtml,
        speakableText: doc.speakableText,
        normalizedImportResult: doc.normalizedImportResult,
        baseSpeechAnnotations: doc.baseSpeechAnnotations,
        dialogueAttributions: doc.dialogueAttributions,
        characterCastRegistry: registry,
        documentVoiceAttribution: doc.documentVoiceAttribution,
        basePronunciationArtifacts: doc.basePronunciationArtifacts,
        presentation: doc.presentation,
      );
      expect(() => adapt(malformed), throwsFormatException);
    }
  });

  test(
    'VS22 malformed dialogue admission is atomic and does not consume sequence',
    () {
      final valid = adapt(
        DocumentImportService().importPastedText('“Wait,” Ada said.'),
      );
      final store = owner();
      final malformed = CharacterAnalysisDelta(
        workId: valid.workId,
        sourceRevision: valid.sourceRevision,
        analysisRevision: valid.analysisRevision,
        sequence: valid.sequence,
        providerId: valid.providerId,
        registry: valid.registry,
        dialogues: const [
          CharacterDialogueReference(
            attributionId: 'bad',
            dialogueSpanId: 'bad',
            segmentId: 'bad',
            startWord: 0,
            endWord: 1,
            castId: 'missing',
          ),
        ],
      );
      expect(() => store.apply(malformed), throwsFormatException);
      expect(store.entries('work'), isEmpty);
      expect(store.apply(valid), isTrue);
    },
  );
}
