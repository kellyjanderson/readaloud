import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/character.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';
import 'package:read_aloud/src/services/modernbooknlp_character_adapter.dart';
import 'package:read_aloud/src/services/work_character_store.dart';

void main() {
  test(
    'VS29 neural admission keeps canonical voice owner and original turn coordinates',
    () {
      const text = '"Hello," Ada said. "Welcome," Bruno replied.';
      final document = DocumentImportService().importPastedText(text);
      final registry = document.characterCastRegistry;
      final ada = registry.characterEntries.singleWhere(
        (c) => c.displayLabel == 'Ada',
      );
      final request = ModernBookNlpRequest(
        requestId: 'r',
        ownerId: 'o',
        workId: 'w',
        sourceRevision: 's',
        analysisRevision: 2,
        sequence: 3,
        text: text,
      );
      final result = <String, dynamic>{
        ...request.toJson(),
        'ok': true,
        'adapterVersion': 'readaloud-cpu-2',
        'providerId': 'modernbooknlp-joint',
        'providerVersion': modernBookNlpRevision,
        'modelIdentity': modernBookNlpModelIdentity,
        'entities': [
          {
            'entityId': 'window-local-93',
            'mentions': [
              {'startUtf16': 9, 'endUtf16': 12, 'text': 'Ada', 'proper': true},
            ],
          },
        ],
        'quotes': [
          {
            'startUtf16': 0,
            'endUtf16': 8,
            'entityId': 'window-local-93',
            'confidence': null,
          },
        ],
      };
      const original = CharacterDialogueReference(
        attributionId: 'a',
        dialogueSpanId: 'q',
        segmentId: 'segment',
        startWord: 0,
        endWord: 1,
      );
      CharacterAnalysisDelta delta(List<ModernBookNlpTurnBinding> bindings) =>
          modernBookNlpCharacterDelta(
            request: request,
            result: result,
            registry: registry,
            turns: bindings,
          );
      final exact = delta([
        const ModernBookNlpTurnBinding(
          startUtf16: 0,
          endUtf16: 8,
          dialogue: original,
        ),
      ]);
      expect(exact.dialogues.single.castId, ada.castId);
      expect(exact.dialogues.single.dialogueSpanId, original.dialogueSpanId);
      expect(exact.dialogues.single.segmentId, original.segmentId);
      final owner = WorkCharacterStore()
        ..begin(workId: 'w', sourceRevision: 's', analysisRevision: 2);
      owner.select('w', ada.castId, 'chosen-mature-voice');
      expect(owner.apply(exact), isTrue);
      expect(
        owner.character('w', ada.castId)!.selectedVoice.voiceId,
        'chosen-mature-voice',
      );
      expect(owner.apply(exact), isFalse);
      final mismatch = delta([
        const ModernBookNlpTurnBinding(
          startUtf16: 1,
          endUtf16: 8,
          dialogue: original,
        ),
      ]);
      expect(mismatch.dialogues.single.castId, isNull);
      result['sourceRevision'] = 'stale';
      expect(() => delta([]), throwsFormatException);
    },
  );
}
