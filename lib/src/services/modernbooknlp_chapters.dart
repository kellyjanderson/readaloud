import 'dart:isolate';

import '../models/chunk_plan.dart';
import '../models/display_document.dart';
import '../models/document_preparation.dart';
import '../models/reader_document.dart';
import '../models/speech_document.dart';
import 'modernbooknlp_window.dart';

/// One forward source cursor. It holds one range and one bounded analysis
/// window. It consumes the same committed ranges as playback and the viewport.
class ModernBookNlpChapters {
  ModernBookNlpChapters(
    this.readRange, {
    this.document,
    int startRange = 1,
    int startSegment = 0,
  }) : _nextRange = startRange,
       _skip = startSegment;

  final Future<DocumentPreparationPublication?> Function(int sequence)
  readRange;
  final ReaderDocument? document;
  final _parts = <_ChapterPart>[];
  List<_ChapterPart> _leading = const [];
  int _nextRange;
  int _skip;
  int _index = 0;
  ReaderDocument? _fragment;
  String? _locator;
  Set<String> _headings = const {};
  bool _chapterStartsHere = true;
  int _chapter = 1;

  static final _chapterHeading = RegExp(
    r'^(?:chapter|part|book)\s+(?:\d+|[ivxlcdm]+|[a-z-]+)(?:\s*[:–—-]\s*[^.!?]+)?$',
    caseSensitive: false,
  );
  static final _endSentence = RegExp(r'''[.!?]["”’']*\s*$''');

  static bool _isChapterHeading(DisplayBlock block) =>
      (block.kind == DisplayBlockKind.heading &&
          block.attributes['level'] == '1') ||
      _chapterHeading.hasMatch(block.plainText.trim());

  /// A seek can jump ahead when the destination's chapter anchor is already
  /// in its available range. Otherwise the forward cursor finds its boundary.
  static int? chapterAnchor(ReaderDocument document, String segmentId) {
    final speech = document.speechDocument;
    final ending = speech.segmentIndexById[segmentId];
    if (ending == null) return null;
    final headings = {
      for (final block in document.displayDocument.blocks)
        if (_isChapterHeading(block)) block.blockId,
    };
    for (var i = ending; i >= 0; i--) {
      final id = speech.segments[i].blockId;
      if (headings.contains(id) &&
          (i == 0 || speech.segments[i - 1].blockId != id)) {
        return i;
      }
    }
    return null;
  }

  Future<_ChapterPart?> _nextPart() async {
    var first = false;
    var newSpineMember = false;
    var continuesParagraph = false;
    while (_fragment == null ||
        _index >= _fragment!.speechDocument.segments.length) {
      if (document != null) {
        if (_nextRange++ > 1) return null;
        _fragment = document;
      } else {
        final publication = await readRange(_nextRange++);
        if (publication == null) return null;
        _fragment = publication.fragment;
        final locator = publication.range.sourceLocator;
        newSpineMember =
            _fragment!.type == ReaderDocumentType.epub &&
            _locator != null &&
            locator != _locator;
        _locator = locator;
        if (publication.range.continuesWord) {
          throw const FormatException(
            'A word crosses the importer limit. Shorten the passage or turn '
            'off chapter analysis to read it.',
          );
        }
        continuesParagraph = publication.range.continuesParagraph;
      }
      _index = _skip;
      _skip = 0;
      first = true;
      _headings = {
        for (final block in _fragment!.displayDocument.blocks)
          if (_isChapterHeading(block)) block.blockId,
      };
    }
    final fragment = _fragment!;
    final segments = fragment.speechDocument.segments;
    final segment = segments[_index++];
    final previous = !first ? segments[_index - 2] : null;
    final startsBlock = previous?.blockId != segment.blockId;
    return _ChapterPart(
      fragment,
      segment,
      chapterStart:
          newSpineMember ||
          (startsBlock && _headings.contains(segment.blockId)),
      paragraphStart: first ? !continuesParagraph : startsBlock,
      sourceRangeStart: first && document == null,
      sentenceStart: first
          ? false
          : startsBlock || previous?.sentenceIndex != segment.sentenceIndex,
    );
  }

  /// A target may be surrounded by complete context from both adjacent
  /// windows. Coverage is published only after the chapter's final target.
  Future<ModernBookNlpChapterWindow?> next() async {
    // Reserve room for the adjacent source halo on each side when necessary.
    const maxInput = 16384;
    const maxHalo = 512;
    var size = _parts.fold<int>(0, (n, part) => n + part.length);
    var quote = '';
    var safeCut = 0;
    var safeCutSize = 0;
    _ChapterPart? previous;
    void inspect(_ChapterPart part, int index, int unitsBefore) {
      if (quote.isEmpty &&
          (part.paragraphStart ||
              part.sentenceStart ||
              (part.document != previous?.document &&
                  _endSentence.hasMatch(
                    previous?.segment.normalizedText ?? '',
                  ))) &&
          unitsBefore <= maxInput - 2 * maxHalo) {
        safeCut = index;
        safeCutSize = unitsBefore;
      }
      quote = _quotationState(part.segment.normalizedText, quote);
      previous = part;
    }

    var scanned = 0;
    for (var i = 0; i < _parts.length; i++) {
      inspect(_parts[i], i, scanned);
      scanned += _parts[i].length;
    }
    var endsChapter = false;
    while (true) {
      final part = await _nextPart();
      if (part == null) {
        endsChapter = true;
        break;
      }
      if (part.chapterStart && _parts.isNotEmpty) {
        _parts.add(part);
        endsChapter = true;
        break;
      }
      inspect(part, _parts.length, size);
      _parts.add(part);
      size += part.length;
      if (size + (_leading.isEmpty ? 0 : maxHalo) <= maxInput) continue;
      if (safeCut == 0) {
        throw const FormatException(
          'A sentence or continued quotation exceeds the analysis limit. '
          'Shorten the passage or turn off chapter analysis to read it.',
        );
      }
      break;
    }

    final count = endsChapter
        ? _parts.length -
              (_parts.lastOrNull?.chapterStart == true &&
                      !identical(_parts.lastOrNull, _parts.firstOrNull)
                  ? 1
                  : 0)
        : safeCut;
    if (count == 0) return null;
    final targets = _parts.sublist(0, count);
    _parts.removeRange(0, count);
    if ([..._leading, ...targets].fold<int>(0, (n, part) => n + part.length) >
        maxInput) {
      throw const FormatException(
        'A sentence or continued quotation exceeds the analysis limit. '
        'Shorten the passage or turn off chapter analysis to read it.',
      );
    }
    final trailing = <_ChapterPart>[];
    if (!endsChapter) {
      var haloSize = 0;
      var nextQuote = '';
      for (final part in _parts) {
        if (trailing.isNotEmpty &&
            nextQuote.isEmpty &&
            (part.sentenceStart || part.paragraphStart)) {
          break;
        }
        haloSize += part.length;
        if (haloSize > maxHalo) {
          trailing.clear();
          break;
        }
        trailing.add(part);
        nextQuote = _quotationState(part.segment.normalizedText, nextQuote);
      }
      if (trailing.length == _parts.length || nextQuote.isNotEmpty) {
        trailing.clear();
      }
    }
    final leading = _leading;
    _leading = const [];
    if (!endsChapter) {
      // Retain the last complete sentence when it fits the overlap budget.
      var first = targets.length - 1;
      while (first > 0 &&
          !targets[first].sentenceStart &&
          !targets[first].paragraphStart) {
        first--;
      }
      final tail = targets.sublist(first);
      if (tail.fold<int>(0, (n, part) => n + part.length) <= maxHalo &&
          tail
              .fold<String>(
                '',
                (open, part) =>
                    _quotationState(part.segment.normalizedText, open),
              )
              .isEmpty) {
        _leading = tail;
      }
    }
    assert(endsChapter || safeCutSize <= maxInput - 2 * maxHalo);
    final chapter = _chapter;
    final startsChapter = _chapterStartsHere;
    _chapterStartsHere = endsChapter;
    if (endsChapter) _chapter++;
    return _buildChapterWindow(
      leading,
      targets,
      trailing,
      chapter,
      startsChapter,
      endsChapter,
    );
  }
}

class ModernBookNlpChapterWindow {
  const ModernBookNlpChapterWindow(
    this.chapter,
    this.startsChapter,
    this.endsChapter,
    this.window,
    this.rangeStarts,
  );

  final int chapter;
  final bool startsChapter, endsChapter;
  final ModernBookNlpWindow window;
  final Set<String> rangeStarts;
}

class _ChapterPart {
  const _ChapterPart(
    this.document,
    this.segment, {
    required this.chapterStart,
    required this.paragraphStart,
    required this.sentenceStart,
    required this.sourceRangeStart,
  });

  final ReaderDocument document;
  final SpeechSegment segment;
  final bool chapterStart, paragraphStart, sentenceStart;
  final bool sourceRangeStart;
  int get length => segment.normalizedText.length + 2;
}

String _quotationState(String text, String open) {
  for (final point in text.runes) {
    switch (point) {
      case 0x22:
        open = open == '"' ? '' : '"';
      case 0x201c:
        open = '”';
      case 0x201d:
        if (open == '”') open = '';
    }
  }
  return open;
}

Future<ModernBookNlpChapterWindow> _buildChapterWindow(
  List<_ChapterPart> leading,
  List<_ChapterPart> targets,
  List<_ChapterPart> trailing,
  int chapter,
  bool startsChapter,
  bool endsChapter,
) => Isolate.run(() {
  final parts = [...leading, ...targets, ...trailing];
  final text = StringBuffer();
  final slices = <ModernBookNlpSourceSlice>[];
  for (final part in parts) {
    if (text.isNotEmpty) text.write(part.paragraphStart ? '\n\n' : ' ');
    final segment = part.segment;
    slices.add(
      ModernBookNlpSourceSlice(
        segment,
        0,
        segment.normalizedText.length,
        text.length,
      ),
    );
    text.write(segment.normalizedText);
  }
  return ModernBookNlpChapterWindow(
    chapter,
    startsChapter,
    endsChapter,
    ModernBookNlpWindow.chapter(
      text.toString(),
      slices,
      {for (final part in targets) part.segment.segmentId},
      {for (final part in parts) part.document},
    ),
    {
      for (final part in targets)
        if (part.sourceRangeStart) part.segment.segmentId,
    },
  );
});

/// Fish boundaries come from the admitted token and quotation coordinates.
/// The importer supplies structural boundaries when a segment has no token.
Future<Map<String, FishSceneBoundary>> projectFishSceneBoundaries(
  ModernBookNlpChapterWindow chapter,
  Map<String, dynamic> result,
) => Isolate.run(() {
  final window = chapter.window;
  final tsv = result['linguisticArtifacts']?['files']?['tokens'] as String?;
  final lines = tsv?.split('\n') ?? const [];
  final offsets = <int>[0];
  for (final rune in window.text.runes) {
    offsets.add(offsets.last + (rune > 0xffff ? 2 : 1));
  }
  final columns = lines.firstOrNull?.split('\t') ?? const [];
  final onset = columns.indexOf('byte_onset');
  final sentence = columns.indexOf('sentence_ID');
  final paragraph = columns.indexOf('paragraph_ID');
  final tokens = <(int, String, String)>[];
  if (onset >= 0 && sentence >= 0 && paragraph >= 0) {
    for (final line in lines.skip(1)) {
      final row = line.split('\t');
      if (row.length != columns.length) continue;
      final start = int.tryParse(row[onset]);
      if (start != null && start >= 0 && start < offsets.length) {
        tokens.add((offsets[start], row[sentence], row[paragraph]));
      }
    }
  }
  final boundaries = <String, FishSceneBoundary>{};
  var token = 0;
  (int, String, String)? previousToken;
  ModernBookNlpSourceSlice? previousSlice;
  for (final slice in window.slices) {
    final start = slice.offset;
    final end = start + slice.end - slice.start;
    while (token < tokens.length && tokens[token].$1 < start) {
      previousToken = tokens[token++];
    }
    final first = token < tokens.length && tokens[token].$1 < end
        ? tokens[token]
        : null;
    final segment = slice.segment;
    if (window.targetSegmentIds.contains(segment.segmentId)) {
      final prior = previousSlice?.segment;
      final newParagraph =
          previousSlice != null &&
          start -
                  previousSlice.offset -
                  previousSlice.end +
                  previousSlice.start >=
              2;
      boundaries[segment.segmentId] = switch ((first, previousToken)) {
        _ when chapter.startsChapter && boundaries.isEmpty =>
          FishSceneBoundary.chapter,
        _ when chapter.rangeStarts.contains(segment.segmentId) =>
          FishSceneBoundary.sourceRange,
        _ when newParagraph => FishSceneBoundary.paragraph,
        (final current?, final last?) when current.$2 == last.$2 =>
          FishSceneBoundary.continuation,
        (final current?, final last?) when current.$3 != last.$3 =>
          FishSceneBoundary.paragraph,
        (null, _)
            when prior?.blockId == segment.blockId &&
                prior?.sentenceIndex == segment.sentenceIndex =>
          FishSceneBoundary.continuation,
        _ => FishSceneBoundary.sentence,
      };
    }
    previousSlice = slice;
    while (token < tokens.length && tokens[token].$1 < end) {
      previousToken = tokens[token++];
    }
  }
  return boundaries;
});
