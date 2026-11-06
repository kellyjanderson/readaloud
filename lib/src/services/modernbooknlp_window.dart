import '../models/character.dart';
import '../models/dialogue_attribution.dart';
import '../models/reader_document.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';
import 'modernbooknlp_character_adapter.dart';

class ModernBookNlpSourceSlice {
  const ModernBookNlpSourceSlice(
    this.segment,
    this.start,
    this.end,
    this.offset,
  );
  final SpeechSegment segment;
  final int start, end, offset;
}

/// Deterministic bounded context at the listening position, also for a portable
/// complete book. A jump does not walk or analyze intervening source windows.
class ModernBookNlpWindow {
  ModernBookNlpWindow._(
    this.text,
    this.slices,
    this.targetSegmentIds,
    this.turns,
    this.protectedSpanIds,
  );
  final String text;
  final List<ModernBookNlpSourceSlice> slices;
  final Set<String> targetSegmentIds;
  final List<ModernBookNlpTurnBinding> turns;
  final Set<String> protectedSpanIds;
  String get identity =>
      slices.map((s) => '${s.segment.segmentId}:${s.start}:${s.end}').join('/');

  bool coversPosition(ReaderDocument document, int wordIndex) {
    final segment = document.segmentForWordIndex(wordIndex);
    if (segment == null || !targetSegmentIds.contains(segment.segmentId)) {
      return false;
    }
    final localWord = wordIndex - document.startWordIndexForSegment(segment);
    final offset = segment.wordSpans.isEmpty
        ? 0
        : segment
              .wordSpans[localWord.clamp(0, segment.wordSpans.length - 1)]
              .startUtf16;
    return slices.any(
      (s) =>
          s.segment.segmentId == segment.segmentId &&
          offset >= s.start &&
          offset < s.end,
    );
  }

  static ModernBookNlpWindow? at(
    ReaderDocument document, {
    required int wordIndex,
    List<SpeechSegment> previous = const [],
  }) {
    final segments = document.speechDocument.segments;
    final target = document.segmentForWordIndex(wordIndex);
    if (target == null) return null;
    final targetIndex =
        document.speechDocument.segmentIndexById[target.segmentId]!;
    // Short documents fit one paragraph-preserving window. Inspection stops at
    // the bound; never concatenate an entire novel to test its length.
    var units = 0, count = 0;
    for (final s in segments.take(128)) {
      units += s.normalizedText.length + (count == 0 ? 0 : 2);
      count++;
      if (units > 12288) break;
    }
    final short = count == segments.length && units <= 12288;
    final first = short ? 0 : (targetIndex ~/ 8) * 8;
    final last = short
        ? segments.length
        : (first + 8).clamp(0, segments.length);
    final selected = <(SpeechSegment, int, int)>[];
    units = 0;
    for (var i = first; i < last; i++) {
      final s = segments[i];
      if (units + s.normalizedText.length + 2 > 12288) {
        // Oversized prose is admitted as a source-aligned subrange. Partial
        // dialogue is deliberately not rebound as a complete quotation.
        if (i <= targetIndex) {
          selected.clear();
          final localWord =
              wordIndex - document.startWordIndexForSegment(target);
          final position = target.wordSpans.isEmpty
              ? 0
              : target
                    .wordSpans[localWord.clamp(0, target.wordSpans.length - 1)]
                    .startUtf16;
          var start = (position ~/ 8192) * 8192;
          var end = (start + 8192).clamp(0, target.normalizedText.length);
          bool low(int n) =>
              n < target.normalizedText.length &&
              target.normalizedText.codeUnitAt(n) >= 0xdc00 &&
              target.normalizedText.codeUnitAt(n) <= 0xdfff;
          if (start > 0 && low(start)) start--;
          if (end < target.normalizedText.length && low(end)) end--;
          selected.add((target, start, end));
        }
        break;
      }
      selected.add((s, 0, s.normalizedText.length));
      units += s.normalizedText.length + 2;
    }
    final targetIds = {for (final s in selected) s.$1.segmentId};
    final context = <(SpeechSegment, int, int)>[];
    var contextUnits = 0;
    // Previous fragments are supplied only for an adjacent forward range.
    final contextStart =
        document.speechDocument.segmentIndexById[selected.first.$1.segmentId]!;
    final preceding = selected.first.$2 > 0
        ? const <SpeechSegment>[]
        : contextStart == 0
        ? previous
        : segments.sublist(
            (contextStart - 32).clamp(0, contextStart),
            contextStart,
          );
    for (final s in preceding.reversed) {
      if (context.length >= 32 ||
          contextUnits + s.normalizedText.length + 2 > 4096) {
        break;
      }
      context.insert(0, (s, 0, s.normalizedText.length));
      contextUnits += s.normalizedText.length + 2;
    }
    final slices = <ModernBookNlpSourceSlice>[];
    final buffer = StringBuffer();
    SpeechSegment? previousSegment;
    for (final s in [...context, ...selected]) {
      if (buffer.isNotEmpty) {
        // Speech segments (including split quotes/tags) are not paragraphs.
        buffer.write(previousSegment?.blockId == s.$1.blockId ? ' ' : '\n\n');
      }
      slices.add(ModernBookNlpSourceSlice(s.$1, s.$2, s.$3, buffer.length));
      buffer.write(s.$1.normalizedText.substring(s.$2, s.$3));
      previousSegment = s.$1;
    }
    if (buffer.isEmpty || buffer.length > 16384) return null;
    final bySegment = {for (final s in slices) s.segment.segmentId: s};
    final bindings = <ModernBookNlpTurnBinding>[];
    // The immutable annotation/attribution sets build indexes during their
    // existing construction/validation, off-isolate on import and restoration.
    // Visit only spans touching this bounded target, never every book dialogue.
    final spans = <String>{
      for (final id in targetIds)
        for (final a in document.baseSpeechAnnotations.forSegment(id))
          if (a.kind == SpeechAnnotationKind.dialogueSpan &&
              a.dialogueSpanId != null)
            a.dialogueSpanId!,
    };
    final protected = <String>{};
    for (final span in spans) {
      final outcome = document.dialogueAttributions.forDialogueSpan(span);
      if (outcome == null) continue;
      if (outcome.provenance ==
          DialogueAttributionProvenance.explicitSourceMetadata) {
        protected.add(span);
      }
      final annotations = document.baseSpeechAnnotations
          .forDialogueSpan(span)
          .where((a) => a.kind == SpeechAnnotationKind.dialogueSpan)
          // A span extending beyond the window stays on its fallback route.
          .take(slices.length + 1)
          .toList();
      if (annotations.isEmpty ||
          annotations.length > slices.length ||
          !annotations.any((a) => targetIds.contains(a.segmentId)) ||
          annotations.any((a) => !bySegment.containsKey(a.segmentId))) {
        continue;
      }
      final refs = <CharacterDialogueReference>[];
      int? start, end;
      var complete = true;
      for (final a in annotations) {
        final slice = bySegment[a.segmentId]!;
        final words = slice.segment.wordSpans;
        if (a.startWord < 0 ||
            a.endWord > words.length ||
            a.endWord <= a.startWord) {
          complete = false;
          break;
        }
        final from = words[a.startWord].startUtf16;
        final to = words[a.endWord - 1].endUtf16;
        if (from < slice.start || to > slice.end) {
          complete = false;
          break;
        }
        final left = slice.offset + from - slice.start;
        final right = slice.offset + to - slice.start;
        start = start == null || left < start ? left : start;
        end = end == null || right > end ? right : end;
        refs.add(
          CharacterDialogueReference(
            attributionId: outcome.attributionId,
            dialogueSpanId: outcome.dialogueSpanId,
            segmentId: a.segmentId,
            startWord: a.startWord,
            endWord: a.endWord,
          ),
        );
      }
      if (!complete) continue;
      for (final ref in refs) {
        bindings.add(
          ModernBookNlpTurnBinding(
            startUtf16: start!,
            endUtf16: end!,
            dialogue: ref,
          ),
        );
      }
    }
    return ModernBookNlpWindow._(
      buffer.toString(),
      List.unmodifiable(slices),
      Set.unmodifiable(targetIds),
      List.unmodifiable(bindings),
      Set.unmodifiable(protected),
    );
  }
}
