import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_html/flutter_html.dart';

import '../models/reader_document.dart';
import '../services/display_document_html_renderer.dart';
import '../services/english_speech_preprocessor.dart';

final _wordPattern = RegExp(r'\S+');
final _inlineWhitespace = RegExp(r'[ \t]+');
final _extraNewlines = RegExp(r'\n{3,}');

HtmlExtension readerTextPositions(
  ReaderDocument document,
  ValueChanged<int> onSeek,
) => MatcherExtension.inline(
  matcher: (context) =>
      context.attributes.containsKey(readingPositionAttribute),
  builder: (context) => _ReadingPositionSpan(
    document: document,
    blockId: context.attributes[readingPositionAttribute]!,
    onSeek: onSeek,
    style: context.style?.generateTextStyle(),
    children: context.inlineSpanChildren,
  ),
);

Widget buildReaderTextContextMenu(
  BuildContext context,
  SelectableRegionState region,
) {
  final anchors = region.contextMenuAnchors;
  final renderObject = region.context.findRenderObject();
  final seek = renderObject is RenderBox
      ? _seekAtPoint(renderObject, anchors.primaryAnchor)
      : null;
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: anchors,
    buttonItems: [
      ...region.contextMenuButtonItems,
      if (seek != null)
        ContextMenuButtonItem(
          label: 'Jump to this position',
          onPressed: () {
            region.hideToolbar();
            region.clearSelection();
            seek();
          },
        ),
    ],
  );
}

VoidCallback? _seekAtPoint(RenderBox region, Offset globalPoint) {
  final hit = BoxHitTestResult();
  region.hitTest(hit, position: region.globalToLocal(globalPoint));
  for (final entry in hit.path) {
    final paragraph = entry.target;
    if (paragraph is! RenderParagraph) continue;
    final localPoint = paragraph.globalToLocal(globalPoint);
    final offset = paragraph.getPositionForOffset(localPoint).offset;
    final marker = _positionSpanAt(paragraph.text, offset, 0);
    if (marker == null) continue;
    final (span, start) = marker;
    final rendered = span.toPlainText(includeSemanticsLabels: false);
    final words = _wordPattern.allMatches(rendered).toList(growable: false);
    final index = words.indexWhere((word) {
      if (offset < start + word.start || offset > start + word.end) {
        return false;
      }
      return paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: start + word.start,
              extentOffset: start + word.end,
            ),
          )
          .any((box) => box.toRect().contains(localPoint));
    });
    if (index == -1) continue;
    final word = _mappedWordIndex(span.document, span.blockId, words, index);
    if (word != null) return () => span.onSeek(word);
  }
  return null;
}

(_ReadingPositionSpan, int)? _positionSpanAt(
  InlineSpan span,
  int offset,
  int start,
) {
  if (span is _ReadingPositionSpan) return (span, start);
  if (span is! TextSpan) return null;
  var nextStart = start + (span.text?.length ?? 0);
  for (final child in span.children ?? const <InlineSpan>[]) {
    final end =
        nextStart + child.toPlainText(includeSemanticsLabels: false).length;
    if (offset >= nextStart && offset <= end) {
      final hit = _positionSpanAt(child, offset, nextStart);
      if (hit != null) return hit;
    }
    nextStart = end;
  }
  return null;
}

int? _mappedWordIndex(
  ReaderDocument document,
  String blockId,
  List<RegExpMatch> renderedWords,
  int selectedIndex,
) {
  final block = document.displayDocument.blocks
      .where((block) => block.blockId == blockId)
      .firstOrNull;
  if (block == null) return null;
  final text = normalizeEnglishSpeechText(block.plainText)
      .replaceAll(_inlineWhitespace, ' ')
      .replaceAll(_extraNewlines, '\n\n')
      .trim();
  final sourceWords = _wordPattern.allMatches(text).toList(growable: false);
  if (sourceWords.length != renderedWords.length) return null;
  for (var i = 0; i < sourceWords.length; i++) {
    if (sourceWords[i].group(0) !=
        normalizeEnglishSpeechText(renderedWords[i].group(0)!)) {
      return null;
    }
  }
  final target = sourceWords[selectedIndex].start;
  int? mapped;
  for (final entry in document.positionMap.entries) {
    if (entry.displayBlockId != blockId ||
        entry.displayStart < 0 ||
        entry.displayStart > target ||
        entry.displayEnd <= target ||
        entry.displayEnd > text.length) {
      continue;
    }
    final segmentIndex =
        document.speechDocument.segmentIndexById[entry.speechSegmentId];
    if (segmentIndex == null) continue;
    final segment = document.speechDocument.segments[segmentIndex];
    if (text.substring(entry.displayStart, entry.displayEnd) !=
        segment.normalizedText) {
      continue;
    }
    final offset = target - entry.displayStart;
    final word = segment.wordSpans
        .where((span) => span.startUtf16 <= offset && offset < span.endUtf16)
        .firstOrNull;
    if (word == null) continue;
    final index =
        document.startWordIndexForSegment(segment) +
        word.wordIndexWithinSegment;
    if (mapped != null && mapped != index) return null;
    mapped = index;
  }
  return mapped;
}

class _ReadingPositionSpan extends TextSpan {
  const _ReadingPositionSpan({
    required this.document,
    required this.blockId,
    required this.onSeek,
    super.style,
    super.children,
  });

  final ReaderDocument document;
  final String blockId;
  final ValueChanged<int> onSeek;

  @override
  bool operator ==(Object other) =>
      other is _ReadingPositionSpan &&
      identical(other.document, document) &&
      other.blockId == blockId &&
      super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, document, blockId);
}
