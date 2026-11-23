import '../models/character.dart';
import '../models/document_voice_attribution.dart';
import '../models/speech_document.dart';

/// Immutable route projection. Only newly built planning contexts see it;
/// captured scene/utterance objects remain untouched. No voice intent is stored.
/// Supply the speech document for consumers that support word-level routes.
DocumentVoiceAttributionSet refineCharacterRoutes(
  DocumentVoiceAttributionSet original,
  Iterable<CharacterDialogueReference> evidence, {
  SpeechDocument? speechDocument,
  Set<String> protectedSpanIds = const {},
  Set<String> checkedSegmentIds = const {},
}) {
  final bySpan = <String, List<CharacterDialogueReference>>{};
  final completeBindings = <String, Set<String>>{};
  final quotes = <String, List<CharacterDialogueReference>>{};
  for (final e in evidence) {
    if (protectedSpanIds.contains(e.dialogueSpanId)) continue;
    if (e.quoteAuthority) {
      if (e.sourceMatched) (quotes[e.dialogueSpanId] ??= []).add(e);
      continue;
    }
    (completeBindings[e.dialogueSpanId] ??= {}).add(e.segmentId);
    if (!e.sourceMatched) continue;
    (bySpan[e.dialogueSpanId] ??= []).add(e);
  }
  final base = speechDocument != null
      ? [
          for (final range in original.ranges)
            if (range.kind == DocumentVoiceAttributionKind.attributedDialogue &&
                !protectedSpanIds.contains(range.dialogueSpanId) &&
                range.segmentIds.every(checkedSegmentIds.contains))
              DocumentVoiceAttributionRange(
                rangeId: range.rangeId,
                segmentIds: range.segmentIds,
                startSegmentId: range.startSegmentId,
                endSegmentId: range.endSegmentId,
                startWordIndex: range.startWordIndex,
                endWordIndex: range.endWordIndex,
                castId: 'cast_narrator',
                kind: DocumentVoiceAttributionKind.narration,
              )
            else
              range,
        ]
      : [
          for (final range in original.ranges)
            (() {
              final refs = bySpan[range.dialogueSpanId];
              if (refs == null ||
                  range.kind == DocumentVoiceAttributionKind.narration) {
                return range;
              }
              final ids = refs.map((r) => r.castId).toSet();
              if (ids.length != 1 ||
                  range.segmentIds.any(
                    (id) => !refs.any((r) => r.segmentId == id),
                  )) {
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
        ];
  final authoritative =
      speechDocument == null ||
          speechDocument.documentId != original.documentId ||
          quotes.isEmpty
      ? null
      : _overlayQuotes(
          base,
          speechDocument,
          quotes,
          protectedSpanIds,
          completeBindings,
        );
  return DocumentVoiceAttributionSet(
    documentId: original.documentId,
    attributionVersion:
        original.attributionVersion +
        (authoritative == null
            ? '+modernbooknlp-v1'
            : '+modernbooknlp-quote-v2'),
    ranges: authoritative ?? base,
  );
}

List<DocumentVoiceAttributionRange>? _overlayQuotes(
  List<DocumentVoiceAttributionRange> base,
  SpeechDocument document,
  Map<String, List<CharacterDialogueReference>> evidence,
  Set<String> protectedSpanIds,
  Map<String, Set<String>> completeBindings,
) {
  final offsets = [0];
  for (final segment in document.segments) {
    offsets.add(offsets.last + segment.wordCount);
  }
  var covered = 0;
  final protected = <DocumentVoiceAttributionRange>[];
  for (final range in base) {
    if (range.startWordIndex != covered) return null;
    covered = range.endWordIndex;
    if (protectedSpanIds.contains(range.dialogueSpanId)) protected.add(range);
  }
  if (covered != offsets.last) return null;

  final candidates = <DocumentVoiceAttributionRange>[];
  for (final entry in evidence.entries) {
    final parts = <(int, int, int)>{};
    var valid = true;
    for (final ref in entry.value) {
      final index = document.segmentIndexById[ref.segmentId];
      if (index == null ||
          ref.startWord < 0 ||
          ref.endWord <= ref.startWord ||
          ref.endWord > document.segments[index].wordCount) {
        valid = false;
        break;
      }
      parts.add((
        index,
        offsets[index] + ref.startWord,
        offsets[index] + ref.endWord,
      ));
    }
    if (!valid || parts.isEmpty) continue;
    final sorted = parts.toList()..sort((a, b) => a.$2.compareTo(b.$2));
    var cursor = sorted.first.$2;
    for (final part in sorted) {
      if (part.$2 != cursor) {
        valid = false;
        break;
      }
      cursor = part.$3;
    }
    if (!valid) continue;
    final ids = entry.value.map((ref) => ref.castId).toSet();
    final cast = ids.length == 1 ? ids.single : null;
    final segmentIds = <String>{
      for (final part in sorted) document.segments[part.$1].segmentId,
    }.toList();
    candidates.add(
      DocumentVoiceAttributionRange(
        rangeId: 'attr_${entry.key}',
        segmentIds: segmentIds,
        startSegmentId: segmentIds.first,
        endSegmentId: segmentIds.last,
        startWordIndex: sorted.first.$2,
        endWordIndex: cursor,
        castId: cast ?? 'cast_narrator',
        kind: cast == null
            ? DocumentVoiceAttributionKind.unattributedDialogue
            : DocumentVoiceAttributionKind.attributedDialogue,
        dialogueSpanId: entry.key,
      ),
    );
  }
  candidates.sort((a, b) => a.startWordIndex.compareTo(b.startWordIndex));
  final quotes = <DocumentVoiceAttributionRange>[];
  var maxPriorEnd = 0;
  var protectionIndex = 0;
  for (var i = 0; i < candidates.length; i++) {
    final quote = candidates[i];
    final start = quote.startWordIndex, end = quote.endWordIndex;
    final conflict =
        start < maxPriorEnd ||
        (i + 1 < candidates.length && candidates[i + 1].startWordIndex < end);
    if (end > maxPriorEnd) maxPriorEnd = end;
    if (conflict) continue;
    while (protectionIndex < protected.length &&
        protected[protectionIndex].endWordIndex <= start) {
      protectionIndex++;
    }
    if (protectionIndex < protected.length &&
        protected[protectionIndex].startWordIndex < end) {
      continue;
    }
    quotes.add(quote);
  }
  if (quotes.isEmpty) return null;

  // A complete old heuristic turn can lose words that the new quote places
  // outside speech. Incomplete window-edge turns keep their uncovered fallback.
  var quoteIndex = 0;
  covered = 0;
  final ranges = <DocumentVoiceAttributionRange>[];
  for (final range in base) {
    final start = range.startWordIndex, end = range.endWordIndex;
    if (start == end) continue;
    var cursor = start < covered ? covered : start;
    final touched =
        cursor > start ||
        (quoteIndex < quotes.length && quotes[quoteIndex].startWordIndex < end);
    if (!touched) {
      ranges.add(range);
      continue;
    }
    final binding = completeBindings[range.dialogueSpanId];
    final trimDialogue =
        binding != null && range.segmentIds.every(binding.contains);
    while (quoteIndex < quotes.length &&
        quotes[quoteIndex].startWordIndex < end) {
      final quote = quotes[quoteIndex++];
      if (cursor < quote.startWordIndex) {
        ranges.add(
          _clip(
            range,
            cursor,
            quote.startWordIndex,
            document,
            offsets,
            trimDialogue,
          ),
        );
      }
      ranges.add(quote);
      covered = cursor = quote.endWordIndex;
    }
    if (cursor < end) {
      ranges.add(_clip(range, cursor, end, document, offsets, trimDialogue));
    }
  }
  return ranges;
}

DocumentVoiceAttributionRange _clip(
  DocumentVoiceAttributionRange range,
  int start,
  int end,
  SpeechDocument document,
  List<int> offsets,
  bool trimDialogue,
) {
  int segmentAt(int word) {
    var low = 0, high = document.segments.length;
    while (low + 1 < high) {
      final mid = (low + high) ~/ 2;
      if (offsets[mid] <= word) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  final segmentIds = [
    for (var i = segmentAt(start); i <= segmentAt(end - 1); i++)
      document.segments[i].segmentId,
  ];
  return DocumentVoiceAttributionRange(
    rangeId: '${range.rangeId}_words_${start}_$end',
    segmentIds: segmentIds,
    startSegmentId: segmentIds.first,
    endSegmentId: segmentIds.last,
    startWordIndex: start,
    endWordIndex: end,
    castId: trimDialogue ? 'cast_narrator' : range.castId,
    kind: trimDialogue ? DocumentVoiceAttributionKind.narration : range.kind,
    dialogueSpanId: trimDialogue ? null : range.dialogueSpanId,
  );
}
