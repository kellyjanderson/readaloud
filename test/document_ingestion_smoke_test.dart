import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:xml/xml.dart';

void main() {
  final smokeFiles =
      Directory('project/testdocs')
          .listSync()
          .whereType<File>()
          .where((file) {
            final extension = p.extension(file.path).toLowerCase();
            return const {'.txt', '.rtf', '.epub', '.pdf'}.contains(extension);
          })
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));

  group('Document ingestion smoke', () {
    test('has test documents to validate', () {
      expect(smokeFiles, isNotEmpty);
    });

    for (final file in smokeFiles) {
      final name = p.basename(file.path);
      final extension = p.extension(file.path).toLowerCase();
      final skipReason = switch (extension) {
        '.pdf' =>
          'PDF source-token smoke coverage needs an integration-style pdfrx harness.',
        _ => false,
      };
      test('preserves source tokens for $name', () async {
        final bytes = await file.readAsBytes();
        final importer = DocumentImportService();
        final document = await importer.importBytes(
          fileName: name,
          bytes: bytes,
        );

        final sourceText = await _extractReadableSourceText(
          file: file,
          bytes: bytes,
        );
        final sourceTokens = _canonicalTokens(sourceText);
        final importedTokens = _canonicalTokens(
          _flattenSpeechDocument(document),
        );

        expect(
          sourceTokens,
          isNotEmpty,
          reason: 'No readable source tokens for $name',
        );
        expect(
          importedTokens,
          isNotEmpty,
          reason: 'Importer produced no speech tokens for $name',
        );

        final mismatch = _findDroppedToken(
          sourceTokens: sourceTokens,
          importedTokens: importedTokens,
        );

        expect(mismatch, isNull, reason: mismatch?.describe(name));
      }, skip: skipReason);
    }
  });
}

String _flattenSpeechDocument(ReaderDocument document) {
  return document.speechDocument.segments
      .map((segment) => segment.normalizedText)
      .join(' ');
}

Future<String> _extractReadableSourceText({
  required File file,
  required Uint8List bytes,
}) async {
  switch (p.extension(file.path).toLowerCase()) {
    case '.txt':
      return utf8.decode(bytes, allowMalformed: true);
    case '.rtf':
      return _decodeRtfForSmoke(utf8.decode(bytes, allowMalformed: true));
    case '.epub':
      return _extractEpubText(bytes);
    case '.pdf':
      return _extractPdfText(fileName: p.basename(file.path), bytes: bytes);
  }

  throw UnsupportedError('No smoke extractor for ${file.path}');
}

Future<String> _extractPdfText({
  required String fileName,
  required Uint8List bytes,
}) async {
  PdfDocument? document;

  try {
    document = await PdfDocument.openData(bytes, sourceName: fileName);
    final pages = <String>[];
    for (final page in document.pages) {
      final pageText = await page.loadStructuredText();
      final normalized = _normalizeForSmoke(pageText.fullText);
      if (normalized.isNotEmpty) {
        pages.add(normalized);
      }
    }
    return pages.join('\n\n');
  } finally {
    await document?.dispose();
  }
}

String _extractEpubText(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final entries = <String, ArchiveFile>{
    for (final entry in archive.files) _normalizeArchivePath(entry.name): entry,
  };

  final containerEntry = entries['META-INF/container.xml'];
  if (containerEntry == null) {
    throw StateError('EPUB missing META-INF/container.xml');
  }

  final containerXml = XmlDocument.parse(
    utf8.decode(
      containerEntry.readBytes() ?? Uint8List(0),
      allowMalformed: true,
    ),
  );
  final rootfile = containerXml.descendants.whereType<XmlElement>().firstWhere(
    (element) => element.name.local == 'rootfile',
    orElse: () => XmlElement(XmlName('rootfile')),
  );
  final packagePath = rootfile.getAttribute('full-path');
  if (packagePath == null || packagePath.isEmpty) {
    throw StateError('EPUB missing package path');
  }

  final packageEntry = entries[_normalizeArchivePath(packagePath)];
  if (packageEntry == null) {
    throw StateError('EPUB missing package document');
  }

  final packageXml = XmlDocument.parse(
    utf8.decode(packageEntry.readBytes() ?? Uint8List(0), allowMalformed: true),
  );
  final manifest = <String, String>{};
  for (final item in packageXml.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == 'item',
  )) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id == null || href == null) {
      continue;
    }
    manifest[id] = _resolveArchivePath(packagePath, href);
  }

  final sections = <String>[];
  for (final itemref in packageXml.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == 'itemref',
  )) {
    final idref = itemref.getAttribute('idref');
    final chapterPath = idref == null ? null : manifest[idref];
    if (chapterPath == null) {
      continue;
    }
    final chapterEntry = entries[chapterPath];
    if (chapterEntry == null) {
      continue;
    }

    final chapterHtml = utf8.decode(
      chapterEntry.readBytes() ?? Uint8List(0),
      allowMalformed: true,
    );
    final parsed = html_parser.parse(chapterHtml);
    final body = parsed.body;
    if (body == null) {
      continue;
    }
    _pruneHtmlForSmoke(body);
    final bodyText = _normalizeForSmoke(body.text);
    if (bodyText.isNotEmpty) {
      sections.add(bodyText);
    }
  }

  return sections.join('\n\n');
}

void _pruneHtmlForSmoke(html_dom.Element root) {
  for (final element in [
    ...root.querySelectorAll('script'),
    ...root.querySelectorAll('style'),
  ]) {
    element.remove();
  }
  for (final element in root.querySelectorAll('nav')) {
    element.remove();
  }
  for (final element in root.querySelectorAll('[hidden]')) {
    element.remove();
  }
  for (final element in root.querySelectorAll('[style]')) {
    final style = (element.attributes['style'] ?? '').toLowerCase();
    if (style.contains('display:none') || style.contains('visibility:hidden')) {
      element.remove();
    }
  }
}

String _normalizeArchivePath(String input) {
  return p.posix.normalize(input).replaceAll('\\', '/');
}

String _resolveArchivePath(String basePath, String relativePath) {
  final baseDir = p.posix.dirname(_normalizeArchivePath(basePath));
  return _normalizeArchivePath(p.posix.join(baseDir, relativePath));
}

String _decodeRtfForSmoke(String raw) {
  final output = StringBuffer();
  final groups = <_SmokeRtfGroupState>[_SmokeRtfGroupState.root()];
  var unicodeFallbackLength = 1;

  for (var index = 0; index < raw.length; index += 1) {
    final group = groups.last;
    final char = raw[index];

    if (char == '{') {
      groups.add(_SmokeRtfGroupState.childOf(group));
      continue;
    }
    if (char == '}') {
      if (groups.length > 1) {
        groups.removeLast();
      }
      continue;
    }

    if (char == '\\') {
      if (index + 1 >= raw.length) {
        break;
      }

      final next = raw[index + 1];
      if (next == '\\' || next == '{' || next == '}') {
        group.markContentSeen();
        if (!group.ignorable) {
          output.write(next);
        }
        index += 1;
        continue;
      }

      if (next == '\'') {
        final hexEnd = index + 4;
        if (hexEnd <= raw.length) {
          final hex = raw.substring(index + 2, index + 4);
          final value = int.tryParse(hex, radix: 16);
          group.markContentSeen();
          if (!group.ignorable && value != null) {
            output.write(_decodeRtfHexByteForSmoke(value));
          }
          index += 3;
          continue;
        }
      }

      if (next == '*') {
        group.pendingStarDestination = true;
        index += 1;
        continue;
      }

      if (!_isAsciiLetterForSmoke(next)) {
        group.markContentSeen();
        if (!group.ignorable) {
          final symbolText = _rtfControlSymbolTextForSmoke(next);
          if (symbolText != null) {
            output.write(symbolText);
          }
        }
        index += 1;
        continue;
      }

      var cursor = index + 1;
      while (cursor < raw.length && _isAsciiLetterForSmoke(raw[cursor])) {
        cursor += 1;
      }
      final word = raw.substring(index + 1, cursor);

      final parameterStart = cursor;
      if (cursor < raw.length &&
          (raw[cursor] == '-' || _isAsciiDigitForSmoke(raw[cursor]))) {
        cursor += 1;
        while (cursor < raw.length && _isAsciiDigitForSmoke(raw[cursor])) {
          cursor += 1;
        }
      }
      final parameter = parameterStart == cursor
          ? null
          : int.tryParse(raw.substring(parameterStart, cursor));

      if (cursor < raw.length && raw[cursor] == ' ') {
        cursor += 1;
      }

      final marksIgnorable =
          group.atGroupStart &&
          (group.pendingStarDestination ||
              _rtfIgnoredDestinationWordsForSmoke.contains(word));
      if (marksIgnorable) {
        group.ignorable = true;
      }
      group.markContentSeen();
      index = cursor - 1;

      if (group.ignorable) {
        continue;
      }

      switch (word) {
        case 'uc':
          unicodeFallbackLength = parameter ?? unicodeFallbackLength;
        case 'u':
          if (parameter == null) {
            continue;
          }
          final normalized = parameter < 0 ? parameter + 65536 : parameter;
          output.write(String.fromCharCode(normalized));
          index =
              _skipRtfUnicodeFallbackForSmoke(
                raw,
                cursor,
                unicodeFallbackLength,
              ) -
              1;
        case 'par':
        case 'pard':
        case 'page':
        case 'sect':
          _appendRtfParagraphBreakForSmoke(output);
        case 'line':
          output.write('\n');
        case 'tab':
          output.write('\t');
        case 'emdash':
          output.write('—');
        case 'endash':
          output.write('–');
        case 'lquote':
        case 'rquote':
          output.write("'");
        case 'ldblquote':
        case 'rdblquote':
          output.write('"');
        case 'bullet':
          output.write('•');
        case 'cell':
          output.write('\t');
        case 'row':
        case 'nestrow':
          output.write('\n');
      }
      continue;
    }

    if (char == '\r' || char == '\n') {
      if (!group.ignorable && !group.atGroupStart) {
        output.write(' ');
      }
      continue;
    }

    if ((char == ' ' || char == '\t') && group.atGroupStart) {
      continue;
    }

    group.markContentSeen();
    if (!group.ignorable) {
      output.write(char);
    }
  }

  return _normalizeDecodedRtfForSmoke(output.toString());
}

String _normalizeDecodedRtfForSmoke(String text) {
  return _normalizeForSmoke(
    text
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAllMapped(RegExp(r'\s+([,.;:!?])'), (match) => match.group(1)!)
        .replaceAllMapped(RegExp(r'([(\["])[ \t]+'), (match) => match.group(1)!)
        .replaceAllMapped(RegExp(r'[ \t]+([)\]])'), (match) => match.group(1)!)
        .replaceAllMapped(
          RegExp(r"""([,.;:!?]["']?)([A-Za-z])"""),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r"([A-Za-z])\s*['’]\s*([A-Za-z])"),
          (match) => "${match.group(1)}'${match.group(2)}",
        )
        .replaceAllMapped(
          RegExp(r'([A-Za-z])\s*-\s*([A-Za-z])'),
          (match) => '${match.group(1)}-${match.group(2)}',
        ),
  );
}

void _appendRtfParagraphBreakForSmoke(StringBuffer output) {
  if (output.isEmpty) {
    return;
  }

  final current = output.toString();
  if (current.endsWith('\n\n')) {
    return;
  }
  if (current.endsWith('\n')) {
    output.write('\n');
    return;
  }
  output.write('\n\n');
}

bool _isAsciiDigitForSmoke(String value) {
  return value.codeUnitAt(0) >= 0x30 && value.codeUnitAt(0) <= 0x39;
}

bool _isAsciiLetterForSmoke(String value) {
  final codeUnit = value.codeUnitAt(0);
  return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);
}

int _skipRtfUnicodeFallbackForSmoke(String raw, int index, int count) {
  var cursor = index;
  var remaining = count;
  while (cursor < raw.length && remaining > 0) {
    final char = raw[cursor];
    if (char == '{' || char == '}' || char == '\\') {
      break;
    }
    cursor += 1;
    if (char != '\r' && char != '\n') {
      remaining -= 1;
    }
  }
  return cursor;
}

String _decodeRtfHexByteForSmoke(int value) {
  switch (value) {
    case 0x80:
      return '€';
    case 0x82:
      return '‚';
    case 0x83:
      return 'ƒ';
    case 0x84:
      return '„';
    case 0x85:
      return '…';
    case 0x86:
      return '†';
    case 0x87:
      return '‡';
    case 0x88:
      return 'ˆ';
    case 0x89:
      return '‰';
    case 0x8A:
      return 'Š';
    case 0x8B:
      return '‹';
    case 0x8C:
      return 'Œ';
    case 0x91:
      return '‘';
    case 0x92:
      return '’';
    case 0x93:
      return '“';
    case 0x94:
      return '”';
    case 0x95:
      return '•';
    case 0x96:
      return '–';
    case 0x97:
      return '—';
    case 0x98:
      return '˜';
    case 0x99:
      return '™';
    case 0x9A:
      return 'š';
    case 0x9B:
      return '›';
    case 0x9C:
      return 'œ';
    case 0x9F:
      return 'Ÿ';
  }

  return latin1.decode([value]);
}

String? _rtfControlSymbolTextForSmoke(String symbol) {
  switch (symbol) {
    case '~':
      return ' ';
    case '_':
      return '-';
    case '-':
      return '';
  }
  return null;
}

const Set<String> _rtfIgnoredDestinationWordsForSmoke = {
  'annotation',
  'atnauthor',
  'atndate',
  'atnid',
  'atnparent',
  'atnref',
  'atrfend',
  'atrfstart',
  'bkmkend',
  'bkmkstart',
  'colortbl',
  'datastore',
  'fontemb',
  'fontfile',
  'fonttbl',
  'generator',
  'info',
  'listlevel',
  'listname',
  'listoverride',
  'listoverridetable',
  'listtable',
  'mmathPr',
  'object',
  'objclass',
  'objdata',
  'objname',
  'objtime',
  'pict',
  'private',
  'rsidtbl',
  'stylesheet',
  'themedata',
  'wgrffmtfilter',
  'xmlattrname',
  'xmlattrvalue',
  'xmlclose',
  'xmlname',
  'xmlnstbl',
  'xmlopen',
};

final class _SmokeRtfGroupState {
  _SmokeRtfGroupState.root() : ignorable = false;

  _SmokeRtfGroupState.childOf(_SmokeRtfGroupState parent)
    : ignorable = parent.ignorable;

  bool ignorable;
  bool atGroupStart = true;
  bool pendingStarDestination = false;

  void markContentSeen() {
    atGroupStart = false;
    pendingStarDestination = false;
  }
}

List<String> _canonicalTokens(String text) {
  final normalized = _normalizeForSmoke(text).toLowerCase();
  return RegExp(r"[a-z0-9]+(?:'[a-z0-9]+)?")
      .allMatches(normalized)
      .map((match) => match.group(0)!)
      .toList(growable: false);
}

String _normalizeForSmoke(String text) {
  return text
      .replaceAll('\r', '')
      .replaceAll(RegExp(r'[\u2018\u2019\u201B\u2032]'), "'")
      .replaceAll(RegExp(r'[\u201C\u201D\u2033]'), '"')
      .replaceAll('\u00AD', '')
      .replaceAll(RegExp(r'[\u200B\u200C\u200D\uFEFF]'), '')
      .replaceAllMapped(RegExp(r'(?<=[A-Za-z])-\s*\n\s*(?=[a-z])'), (_) => '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

_DroppedTokenMismatch? _findDroppedToken({
  required List<String> sourceTokens,
  required List<String> importedTokens,
}) {
  var importedIndex = 0;
  for (
    var sourceIndex = 0;
    sourceIndex < sourceTokens.length;
    sourceIndex += 1
  ) {
    final expected = sourceTokens[sourceIndex];
    final searchStart = importedIndex;
    while (importedIndex < importedTokens.length &&
        importedTokens[importedIndex] != expected) {
      importedIndex += 1;
    }
    if (importedIndex >= importedTokens.length) {
      return _DroppedTokenMismatch(
        missingToken: expected,
        sourceIndex: sourceIndex,
        importedSearchStart: searchStart,
        sourceContext: _tokenWindow(sourceTokens, sourceIndex),
        importedContext: _tokenWindow(importedTokens, searchStart),
      );
    }
    importedIndex += 1;
  }
  return null;
}

List<String> _tokenWindow(List<String> tokens, int center) {
  if (tokens.isEmpty) {
    return const <String>[];
  }
  final start = (center - 6).clamp(0, tokens.length);
  final end = (center + 7).clamp(0, tokens.length);
  return tokens.sublist(start, end);
}

class _DroppedTokenMismatch {
  const _DroppedTokenMismatch({
    required this.missingToken,
    required this.sourceIndex,
    required this.importedSearchStart,
    required this.sourceContext,
    required this.importedContext,
  });

  final String missingToken;
  final int sourceIndex;
  final int importedSearchStart;
  final List<String> sourceContext;
  final List<String> importedContext;

  String describe(String fileName) {
    return 'Dropped token "$missingToken" while importing $fileName.\n'
        'source index: $sourceIndex\n'
        'import search start: $importedSearchStart\n'
        'source context: ${sourceContext.join(' ')}\n'
        'imported context: ${importedContext.join(' ')}';
  }
}
