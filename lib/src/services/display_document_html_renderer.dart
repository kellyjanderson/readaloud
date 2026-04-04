import 'dart:convert';

import '../models/display_document.dart';
import '../models/spoken_selection.dart';

String renderDisplayDocumentToHtml(
  DisplayDocument document, {
  SpokenSelection spokenSelection = const SpokenSelection.none(),
}) {
  final orderedBlocks = [...document.blocks]
    ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
  final childrenByParent = <String, List<DisplayBlock>>{};
  for (final block in orderedBlocks) {
    final parentId = block.parentBlockId;
    if (parentId == null) {
      continue;
    }
    childrenByParent.putIfAbsent(parentId, () => <DisplayBlock>[]).add(block);
  }

  final buffer = StringBuffer('<article>');
  final renderedIds = <String>{};

  for (final block in orderedBlocks) {
    if (block.parentBlockId != null) {
      continue;
    }
    _renderBlock(
      buffer: buffer,
      block: block,
      document: document,
      spokenSelection: spokenSelection,
      childrenByParent: childrenByParent,
      renderedIds: renderedIds,
    );
  }

  for (final block in orderedBlocks) {
    if (renderedIds.contains(block.blockId)) {
      continue;
    }
    _renderBlock(
      buffer: buffer,
      block: block,
      document: document,
      spokenSelection: spokenSelection,
      childrenByParent: childrenByParent,
      renderedIds: renderedIds,
    );
  }

  buffer.write('</article>');
  return buffer.toString();
}

void _renderBlock({
  required StringBuffer buffer,
  required DisplayBlock block,
  required DisplayDocument document,
  required SpokenSelection spokenSelection,
  required Map<String, List<DisplayBlock>> childrenByParent,
  required Set<String> renderedIds,
}) {
  if (!renderedIds.add(block.blockId)) {
    return;
  }

  final isActiveBlock =
      spokenSelection.hasSelection &&
      spokenSelection.displayBlockId == block.blockId;
  final highlightClass = _highlightClassForSelection(spokenSelection);
  final highlightStart = isActiveBlock &&
          spokenSelection.precision != SpokenSelectionPrecision.block
      ? spokenSelection.displayStart
      : null;
  final highlightEnd = isActiveBlock &&
          spokenSelection.precision != SpokenSelectionPrecision.block
      ? spokenSelection.displayEnd
      : null;
  final blockClass = switch (spokenSelection.precision) {
    SpokenSelectionPrecision.block when isActiveBlock =>
      'active-reading-block spoken-block',
    SpokenSelectionPrecision.word ||
    SpokenSelectionPrecision.segment when isActiveBlock =>
      'active-reading-block',
    _ => null,
  };
  final blockAttributes = _blockAttributes(
    blockId: block.blockId,
    className: blockClass,
  );

  switch (block.kind) {
    case DisplayBlockKind.heading:
      final level = block.attributes['level'] ?? '1';
      final tag = switch (level) {
        '1' => 'h1',
        '2' => 'h2',
        '3' => 'h3',
        '4' => 'h4',
        '5' => 'h5',
        '6' => 'h6',
        _ => 'h2',
      };
      buffer.write(
        '<$tag$blockAttributes>${_renderInlines(block.inlines, highlightStart: highlightStart, highlightEnd: highlightEnd, highlightClass: highlightClass)}</$tag>',
      );
      return;
    case DisplayBlockKind.paragraph:
      buffer.write(
        '<p$blockAttributes>${_renderInlines(block.inlines, highlightStart: highlightStart, highlightEnd: highlightEnd, highlightClass: highlightClass)}</p>',
      );
      return;
    case DisplayBlockKind.blockquote:
      buffer.write(
        '<blockquote$blockAttributes><p>${_renderInlines(block.inlines, highlightStart: highlightStart, highlightEnd: highlightEnd, highlightClass: highlightClass)}</p></blockquote>',
      );
      return;
    case DisplayBlockKind.codeBlock:
      buffer.write(
        '<pre$blockAttributes><code>${_renderInlines(block.inlines, highlightStart: highlightStart, highlightEnd: highlightEnd, highlightClass: highlightClass)}</code></pre>',
      );
      return;
    case DisplayBlockKind.orderedList:
    case DisplayBlockKind.unorderedList:
      final tag = block.kind == DisplayBlockKind.orderedList ? 'ol' : 'ul';
      buffer.write('<$tag$blockAttributes>');
      final children =
          childrenByParent[block.blockId] ?? const <DisplayBlock>[];
      for (final child in children) {
        _renderBlock(
          buffer: buffer,
          block: child,
          document: document,
          spokenSelection: spokenSelection,
          childrenByParent: childrenByParent,
          renderedIds: renderedIds,
        );
      }
      buffer.write('</$tag>');
      return;
    case DisplayBlockKind.listItem:
      buffer.write(
        '<li$blockAttributes>${_renderInlines(block.inlines, highlightStart: highlightStart, highlightEnd: highlightEnd, highlightClass: highlightClass)}</li>',
      );
      return;
    case DisplayBlockKind.image:
      final asset = block.assetId == null
          ? null
          : document.assets[block.assetId];
      if (asset == null) {
        buffer.write(
          '<div class="embedded-context missing-asset">Missing image asset</div>',
        );
        return;
      }
      final alt = block.attributes['alt'] ?? asset.metadata['alt'] ?? '';
      buffer.write(
        '<img$blockAttributes src="${const HtmlEscape().convert(asset.resolvedUri.toString())}" alt="${const HtmlEscape().convert(alt)}" />',
      );
      return;
    case DisplayBlockKind.audio:
      final asset = block.assetId == null
          ? null
          : document.assets[block.assetId];
      final src = asset?.resolvedUri.toString() ?? '';
      buffer.write(
        '<audio$blockAttributes controls src="${const HtmlEscape().convert(src)}"></audio>',
      );
      return;
    case DisplayBlockKind.video:
      final asset = block.assetId == null
          ? null
          : document.assets[block.assetId];
      final src = asset?.resolvedUri.toString() ?? '';
      final poster =
          block.attributes['poster'] ?? asset?.metadata['poster'] ?? '';
      final posterAttribute = poster.isEmpty
          ? ''
          : ' poster="${const HtmlEscape().convert(poster)}"';
      buffer.write(
        '<video$blockAttributes controls src="${const HtmlEscape().convert(src)}"$posterAttribute></video>',
      );
      return;
    case DisplayBlockKind.table:
      buffer.write(
        '<div${_blockAttributes(blockId: block.blockId, className: _mergeClasses(blockClass, 'table-block'))}>${_renderInlines(block.inlines, highlightStart: highlightStart, highlightEnd: highlightEnd, highlightClass: highlightClass)}</div>',
      );
      return;
    case DisplayBlockKind.pageBreak:
      final pageIndex = block.attributes['pageIndex'];
      final attribute = pageIndex == null
          ? ''
          : ' data-page-index="$pageIndex"';
      buffer.write(
        '<hr${_blockAttributes(blockId: block.blockId, className: _mergeClasses(blockClass, 'page-break'))}$attribute />',
      );
      return;
    case DisplayBlockKind.separator:
      buffer.write('<hr$blockAttributes />');
      return;
    case DisplayBlockKind.unsupported:
      final tag = block.attributes['tag'] ?? 'unknown';
      final content = block.inlines.isEmpty
          ? const HtmlEscape().convert(block.attributes['label'] ?? '')
          : _renderInlines(
              block.inlines,
              highlightStart: highlightStart,
              highlightEnd: highlightEnd,
              highlightClass: highlightClass,
            );
      buffer.write(
        '<div${_blockAttributes(blockId: block.blockId, className: _mergeClasses(blockClass, 'unsupported-block'))} data-source-tag="${const HtmlEscape().convert(tag)}">$content</div>',
      );
      return;
  }
}

String _renderInlines(
  List<DisplayInline> inlines, {
  int? highlightStart,
  int? highlightEnd,
  String? highlightClass,
}) {
  final buffer = StringBuffer();
  var offset = 0;
  for (final inline in inlines) {
    final text = _renderHighlightedText(
      inline.text,
      inlineStart: offset,
      highlightStart: highlightStart,
      highlightEnd: highlightEnd,
      highlightClass: highlightClass,
    );
    switch (inline.kind) {
      case DisplayInlineKind.text:
        buffer.write(text);
        break;
      case DisplayInlineKind.emphasis:
        buffer.write('<em>$text</em>');
        break;
      case DisplayInlineKind.strong:
        buffer.write('<strong>$text</strong>');
        break;
      case DisplayInlineKind.link:
        final href = const HtmlEscape().convert(
          inline.attributes['href'] ?? '',
        );
        buffer.write('<a href="$href">$text</a>');
        break;
      case DisplayInlineKind.inlineCode:
        buffer.write('<code>$text</code>');
        break;
      case DisplayInlineKind.lineBreak:
        buffer.write('<br />');
        break;
      case DisplayInlineKind.superscript:
        buffer.write('<sup>$text</sup>');
        break;
      case DisplayInlineKind.subscript:
        buffer.write('<sub>$text</sub>');
        break;
    }
    offset += inline.text.length;
  }
  return buffer.toString();
}

String _renderHighlightedText(
  String text, {
  required int inlineStart,
  required int? highlightStart,
  required int? highlightEnd,
  required String? highlightClass,
}) {
  final escapedText = const HtmlEscape().convert(text);
  if (highlightStart == null ||
      highlightEnd == null ||
      highlightClass == null ||
      highlightEnd <= inlineStart ||
      highlightStart >= inlineStart + text.length) {
    return escapedText;
  }

  final localStart = (highlightStart - inlineStart).clamp(0, text.length);
  final localEnd = (highlightEnd - inlineStart).clamp(0, text.length);
  if (localStart >= localEnd) {
    return escapedText;
  }

  final before = const HtmlEscape().convert(text.substring(0, localStart));
  final selected = const HtmlEscape().convert(
    text.substring(localStart, localEnd),
  );
  final after = const HtmlEscape().convert(text.substring(localEnd));
  return '$before<span class="$highlightClass">$selected</span>$after';
}

String? _highlightClassForSelection(SpokenSelection spokenSelection) {
  return switch (spokenSelection.precision) {
    SpokenSelectionPrecision.word => 'spoken-word',
    SpokenSelectionPrecision.segment => 'spoken-segment',
    _ => null,
  };
}

String _blockAttributes({required String blockId, String? className}) {
  final blockAttribute =
      ' data-block-id="${const HtmlEscape().convert(blockId)}"';
  if (className == null || className.trim().isEmpty) {
    return blockAttribute;
  }
  return '$blockAttribute class="${const HtmlEscape().convert(className)}"';
}

String _mergeClasses(String? primary, String secondary) {
  if (primary == null || primary.trim().isEmpty) {
    return secondary;
  }
  return '$primary $secondary';
}
