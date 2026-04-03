import 'dart:convert';

import '../models/display_document.dart';

String renderDisplayDocumentToHtml(DisplayDocument document) {
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
  required Map<String, List<DisplayBlock>> childrenByParent,
  required Set<String> renderedIds,
}) {
  if (!renderedIds.add(block.blockId)) {
    return;
  }

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
      buffer.write('<$tag>${_renderInlines(block.inlines)}</$tag>');
      return;
    case DisplayBlockKind.paragraph:
      buffer.write('<p>${_renderInlines(block.inlines)}</p>');
      return;
    case DisplayBlockKind.blockquote:
      buffer.write(
        '<blockquote><p>${_renderInlines(block.inlines)}</p></blockquote>',
      );
      return;
    case DisplayBlockKind.codeBlock:
      buffer.write('<pre><code>${_renderInlines(block.inlines)}</code></pre>');
      return;
    case DisplayBlockKind.orderedList:
    case DisplayBlockKind.unorderedList:
      final tag = block.kind == DisplayBlockKind.orderedList ? 'ol' : 'ul';
      buffer.write('<$tag>');
      final children =
          childrenByParent[block.blockId] ?? const <DisplayBlock>[];
      for (final child in children) {
        _renderBlock(
          buffer: buffer,
          block: child,
          document: document,
          childrenByParent: childrenByParent,
          renderedIds: renderedIds,
        );
      }
      buffer.write('</$tag>');
      return;
    case DisplayBlockKind.listItem:
      buffer.write('<li>${_renderInlines(block.inlines)}</li>');
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
        '<img src="${const HtmlEscape().convert(asset.resolvedUri.toString())}" alt="${const HtmlEscape().convert(alt)}" />',
      );
      return;
    case DisplayBlockKind.audio:
      final asset = block.assetId == null
          ? null
          : document.assets[block.assetId];
      final src = asset?.resolvedUri.toString() ?? '';
      buffer.write(
        '<audio controls src="${const HtmlEscape().convert(src)}"></audio>',
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
        '<video controls src="${const HtmlEscape().convert(src)}"$posterAttribute></video>',
      );
      return;
    case DisplayBlockKind.table:
      buffer.write(
        '<div class="table-block">${_renderInlines(block.inlines)}</div>',
      );
      return;
    case DisplayBlockKind.pageBreak:
      final pageIndex = block.attributes['pageIndex'];
      final attribute = pageIndex == null
          ? ''
          : ' data-page-index="$pageIndex"';
      buffer.write('<hr class="page-break"$attribute />');
      return;
    case DisplayBlockKind.separator:
      buffer.write('<hr />');
      return;
    case DisplayBlockKind.unsupported:
      final tag = block.attributes['tag'] ?? 'unknown';
      final content = block.inlines.isEmpty
          ? const HtmlEscape().convert(block.attributes['label'] ?? '')
          : _renderInlines(block.inlines);
      buffer.write(
        '<div class="unsupported-block" data-source-tag="${const HtmlEscape().convert(tag)}">$content</div>',
      );
      return;
  }
}

String _renderInlines(List<DisplayInline> inlines) {
  final buffer = StringBuffer();
  for (final inline in inlines) {
    final text = const HtmlEscape().convert(inline.text);
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
  }
  return buffer.toString();
}
