import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/character.dart';
import 'package:read_aloud/src/models/document_voice_attribution.dart';
import 'package:read_aloud/src/services/character_analysis_adapter.dart';
import 'package:read_aloud/src/services/character_route_refinement.dart';
import 'package:read_aloud/src/services/document_import_service.dart';

void main() {
  test(
    'VS37 future routing leaves captured routes intact and preserves unmatched fallback',
    () {
      final doc = DocumentImportService().importPastedText(
        '"Ready," Ada said. "Wait," Bruno replied.',
      );
      final delta = const CharacterAnalysisAdapter().refined(
        workId: 'w',
        sourceRevision: 's',
        analysisRevision: 1,
        sequence: 1,
        document: doc,
      );
      final before = doc.documentVoiceAttribution;
      final originalIds = before.ranges.map((r) => r.castId).toList();
      CharacterDialogueReference change(
        CharacterDialogueReference r,
        bool matched,
      ) => CharacterDialogueReference(
        attributionId: r.attributionId,
        dialogueSpanId: r.dialogueSpanId,
        segmentId: r.segmentId,
        startWord: r.startWord,
        endWord: r.endWord,
        castId: null,
        sourceMatched: matched,
      );
      final future = refineCharacterRoutes(before, [
        change(delta.dialogues.first, true),
        change(delta.dialogues.last, false),
      ]);
      expect(before.ranges.map((r) => r.castId).toList(), originalIds);
      final first = future.ranges.singleWhere(
        (r) => r.dialogueSpanId == delta.dialogues.first.dialogueSpanId,
      );
      expect(first.kind, DocumentVoiceAttributionKind.unattributedDialogue);
      final last = future.ranges.singleWhere(
        (r) => r.dialogueSpanId == delta.dialogues.last.dialogueSpanId,
      );
      expect(last.castId, delta.dialogues.last.castId);
      expect(
        future.ranges
            .where((r) => r.kind == DocumentVoiceAttributionKind.narration)
            .length,
        before.ranges
            .where((r) => r.kind == DocumentVoiceAttributionKind.narration)
            .length,
      );
    },
  );
}
