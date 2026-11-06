import '../models/character.dart';
import '../models/document_voice_attribution.dart';

/// Immutable route projection. Only newly built planning contexts see it;
/// captured scene/utterance objects remain untouched. No voice intent is stored.
DocumentVoiceAttributionSet refineCharacterRoutes(
  DocumentVoiceAttributionSet original,
  Iterable<CharacterDialogueReference> evidence,
) {
  final bySpan = <String, List<CharacterDialogueReference>>{};
  for (final e in evidence) {
    if (!e.sourceMatched) continue;
    (bySpan[e.dialogueSpanId] ??= []).add(e);
  }
  return DocumentVoiceAttributionSet(
    documentId: original.documentId,
    attributionVersion: '${original.attributionVersion}+modernbooknlp-v1',
    ranges: [
      for (final range in original.ranges)
        (() {
          final refs = bySpan[range.dialogueSpanId];
          if (refs == null ||
              range.kind == DocumentVoiceAttributionKind.narration) {
            return range;
          }
          final ids = refs.map((r) => r.castId).toSet();
          if (ids.length != 1 ||
              range.segmentIds.any((id) => !refs.any((r) => r.segmentId == id))) {
            return range;
          }
          final id = ids.single;
          return DocumentVoiceAttributionRange(
            rangeId: range.rangeId,
            segmentIds: range.segmentIds,
            startSegmentId: range.startSegmentId,
            endSegmentId: range.endSegmentId,
            startWordIndex: range.startWordIndex,
            endWordIndex: range.endWordIndex,
            castId: id ?? 'cast_narrator',
            kind: id == null
                ? DocumentVoiceAttributionKind.unattributedDialogue
                : DocumentVoiceAttributionKind.attributedDialogue,
            dialogueSpanId: range.dialogueSpanId,
          );
        })(),
    ],
  );
}
