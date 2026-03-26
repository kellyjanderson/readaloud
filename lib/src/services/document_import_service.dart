import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../models/reader_document.dart';

class DocumentImportService {
  static const supportedExtensions = <String>[
    'txt',
    'text',
    'md',
    'markdown',
    'html',
    'htm',
    'epub',
    'pdf',
    'docx',
    'rtf',
  ];

  Future<ReaderDocument> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final extension = _extensionOf(fileName);
    switch (extension) {
      case 'txt':
      case 'text':
      case 'md':
      case 'markdown':
        return _importPlainText(fileName, bytes);
      case 'html':
      case 'htm':
        return _importHtml(fileName, bytes);
      case 'epub':
        return _importEpub(fileName, bytes);
      case 'pdf':
        return _importPdf(fileName, bytes);
      case 'docx':
        return _importDocx(fileName, bytes);
      case 'rtf':
        return _importRtf(fileName, bytes);
      default:
        return _unsupportedDocument(fileName);
    }
  }

  ReaderDocument importPastedText(String text) {
    final normalized = text.trim();
    return ReaderDocument(
      title: 'Pasted Text',
      type: ReaderDocumentType.plainText,
      displayHtml: plainTextToHtml(normalized),
      speakableText: normalized,
      sourceDescription: 'Pasted into Read Aloud',
    );
  }

  ReaderDocument importSharedText(String text) {
    final normalized = text.trim();
    return ReaderDocument(
      title: 'Shared Text',
      type: ReaderDocumentType.plainText,
      displayHtml: plainTextToHtml(normalized),
      speakableText: normalized,
      sourceDescription: 'Shared into Read Aloud',
    );
  }

  ReaderDocument _importPlainText(String fileName, Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return ReaderDocument(
      title: fileName,
      type: ReaderDocumentType.plainText,
      displayHtml: plainTextToHtml(text),
      speakableText: text,
      sourceDescription: 'Plain text import',
    );
  }

  ReaderDocument _importHtml(String fileName, Uint8List bytes) {
    final rawHtml = utf8.decode(bytes, allowMalformed: true);
    final document = html_parser.parse(rawHtml);
    final bodyHtml = document.body?.innerHtml ?? rawHtml;
    final speakableText = document.body?.text.trim() ?? '';
    return ReaderDocument(
      title: fileName,
      type: ReaderDocumentType.html,
      displayHtml: '<article>$bodyHtml</article>',
      speakableText: speakableText,
      sourceDescription: 'HTML import',
    );
  }

  Future<ReaderDocument> _importPdf(String fileName, Uint8List bytes) async {
    PdfDocument? document;

    try {
      document = await PdfDocument.openData(bytes, sourceName: fileName);
      final speakablePages = <String>[];

      for (final page in document.pages) {
        final pageText = await page.loadStructuredText();
        final normalized = pageText.fullText.trim();
        if (normalized.isNotEmpty) {
          speakablePages.add(normalized);
        }
      }

      final pageCount = document.pages.length;
      final speakableText = speakablePages.join('\n\n').trim();
      final extractionNote = speakableText.isEmpty
          ? 'No extractable text was found for text-to-speech yet.'
          : 'Readable text was extracted for playback.';

      return ReaderDocument(
        title: fileName,
        type: ReaderDocumentType.pdf,
        displayHtml:
            '''
<article>
  <h1>${const HtmlEscape().convert(fileName)}</h1>
  <p>$extractionNote</p>
</article>
''',
        speakableText: speakableText,
        presentation: ReaderDocumentPresentation.pdf,
        pdfData: bytes,
        sourceDescription:
            'PDF import, $pageCount page${pageCount == 1 ? '' : 's'}',
      );
    } catch (error) {
      return ReaderDocument(
        title: fileName,
        type: ReaderDocumentType.pdf,
        displayHtml:
            '''
<article>
  <h1>PDF Import Failed</h1>
  <p>${const HtmlEscape().convert(error.toString())}</p>
</article>
''',
        speakableText: '',
        sourceDescription: 'PDF import failed',
      );
    } finally {
      await document?.dispose();
    }
  }

  ReaderDocument _importDocx(String fileName, Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entries = <String, ArchiveFile>{};
    for (final entry in archive.files) {
      entries[_normalizeArchivePath(entry.name)] = entry;
    }

    final documentEntry = entries['word/document.xml'];
    if (documentEntry == null) {
      return _unsupportedDocument(fileName);
    }

    final documentXml = XmlDocument.parse(
      utf8.decode(_entryBytes(documentEntry), allowMalformed: true),
    );
    final blocks = <String>[];
    final speakableText = StringBuffer();
    final attachments = <ReaderAttachment>[];

    for (final paragraph
        in documentXml.descendants.whereType<XmlElement>().where(
          (element) => element.name.local == 'p',
        )) {
      final paragraphContent = _extractDocxParagraph(paragraph);
      if (paragraphContent == null) {
        continue;
      }

      if (paragraphContent.hasImage) {
        attachments.add(
          const ReaderAttachment(
            label: 'Inline DOCX media',
            type: ReaderAttachmentType.image,
          ),
        );
      }

      if (paragraphContent.speakableText.isEmpty) {
        continue;
      }

      blocks.add(
        '<${paragraphContent.htmlTag}>${paragraphContent.htmlText}</${paragraphContent.htmlTag}>',
      );

      if (speakableText.isNotEmpty) {
        speakableText.writeln();
        speakableText.writeln();
      }
      speakableText.write(paragraphContent.speakableText);
    }

    final title = _docxTitle(entries) ?? fileName;
    final displayHtml = blocks.isEmpty
        ? '''
<article>
  <h1>${const HtmlEscape().convert(title)}</h1>
  <p>No readable text was extracted from this DOCX document yet.</p>
</article>
'''
        : '<article>${blocks.join('\n')}</article>';

    return ReaderDocument(
      title: title,
      type: ReaderDocumentType.html,
      displayHtml: displayHtml,
      speakableText: speakableText.toString().trim(),
      sourceDescription: 'DOCX import',
      attachments: attachments,
    );
  }

  ReaderDocument _importRtf(String fileName, Uint8List bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final text = _decodeRtf(raw).trim();
    return ReaderDocument(
      title: fileName,
      type: ReaderDocumentType.plainText,
      displayHtml: plainTextToHtml(text),
      speakableText: text,
      sourceDescription: 'RTF import',
    );
  }

  ReaderDocument _unsupportedDocument(String fileName) {
    return ReaderDocument(
      title: fileName,
      type: ReaderDocumentType.unsupported,
      displayHtml: '''
<article>
  <h1>Unsupported Format</h1>
  <p>Read Aloud does not know how to import this document yet.</p>
</article>
''',
      speakableText: 'This document format is not supported yet.',
      sourceDescription: 'Unsupported file type',
    );
  }

  ReaderDocument _importEpub(String fileName, Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entries = <String, ArchiveFile>{};
    for (final entry in archive.files) {
      entries[_normalizeArchivePath(entry.name)] = entry;
    }

    final containerEntry = entries['META-INF/container.xml'];
    if (containerEntry == null) {
      return _unsupportedDocument(fileName);
    }

    final containerXml = XmlDocument.parse(
      utf8.decode(_entryBytes(containerEntry), allowMalformed: true),
    );
    final rootfile = containerXml.descendants
        .whereType<XmlElement>()
        .firstWhere(
          (element) => element.name.local == 'rootfile',
          orElse: () => XmlElement(XmlName('rootfile')),
        );
    final packagePath = rootfile.getAttribute('full-path');
    if (packagePath == null || packagePath.isEmpty) {
      return _unsupportedDocument(fileName);
    }

    final packageEntry = entries[_normalizeArchivePath(packagePath)];
    if (packageEntry == null) {
      return _unsupportedDocument(fileName);
    }

    final packageXml = XmlDocument.parse(
      utf8.decode(_entryBytes(packageEntry), allowMalformed: true),
    );
    final manifest = <String, _EpubAsset>{};
    for (final item in packageXml.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'item',
    )) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = _EpubAsset(
        href: _resolveArchivePath(packagePath, href),
        mediaType: item.getAttribute('media-type') ?? '',
      );
    }

    final sections = <String>[];
    final speakableText = StringBuffer();
    final attachments = <ReaderAttachment>[];
    final metadataTitle = packageXml.descendants
        .whereType<XmlElement>()
        .firstWhere(
          (element) => element.name.local == 'title',
          orElse: () => XmlElement(XmlName('title')),
        )
        .innerText
        .trim();

    for (final itemref in packageXml.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'itemref',
    )) {
      final idref = itemref.getAttribute('idref');
      final asset = idref == null ? null : manifest[idref];
      if (asset == null) continue;
      final chapterEntry = entries[asset.href];
      if (chapterEntry == null) continue;

      final chapterHtml = utf8.decode(
        _entryBytes(chapterEntry),
        allowMalformed: true,
      );
      final parsed = html_parser.parse(chapterHtml);
      final body = parsed.body;
      if (body == null) continue;

      for (final image in body.querySelectorAll('img')) {
        final src = image.attributes['src'];
        if (src == null ||
            src.isEmpty ||
            src.startsWith('data:') ||
            src.startsWith('http')) {
          continue;
        }
        final resolved = _resolveArchivePath(asset.href, src);
        final imageEntry = entries[resolved];
        if (imageEntry == null) continue;
        final imageBytes = _entryBytes(imageEntry);
        final mimeType = _guessMimeType(resolved);
        image.attributes['src'] =
            'data:$mimeType;base64,${base64Encode(imageBytes)}';
        attachments.add(
          ReaderAttachment(
            label: image.attributes['alt'] ?? resolved.split('/').last,
            type: ReaderAttachmentType.image,
            source: resolved,
          ),
        );
      }

      sections.add('<section>${body.innerHtml}</section>');
      final bodyText = body.text.trim();
      if (bodyText.isNotEmpty) {
        if (speakableText.isNotEmpty) {
          speakableText.writeln();
          speakableText.writeln();
        }
        speakableText.write(bodyText);
      }
    }

    return ReaderDocument(
      title: metadataTitle.isEmpty ? fileName : metadataTitle,
      type: ReaderDocumentType.epub,
      displayHtml: '<article>${sections.join('\n')}</article>',
      speakableText: speakableText.toString().trim(),
      sourceDescription: 'EPUB import',
      attachments: attachments,
    );
  }

  Uint8List _entryBytes(ArchiveFile file) {
    return file.content;
  }
}

class _EpubAsset {
  const _EpubAsset({required this.href, required this.mediaType});

  final String href;
  final String mediaType;
}

class _DocxParagraphContent {
  const _DocxParagraphContent({
    required this.htmlTag,
    required this.htmlText,
    required this.speakableText,
    required this.hasImage,
  });

  final String htmlTag;
  final String htmlText;
  final String speakableText;
  final bool hasImage;
}

String _extensionOf(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1) return '';
  return fileName.substring(dotIndex + 1).toLowerCase();
}

String _normalizeArchivePath(String path) {
  return path.replaceAll('\\', '/');
}

String _resolveArchivePath(String basePath, String relativePath) {
  final normalizedBase = _normalizeArchivePath(basePath);
  final baseDirectory = normalizedBase.contains('/')
      ? normalizedBase.substring(0, normalizedBase.lastIndexOf('/') + 1)
      : '';
  return Uri.parse(baseDirectory).resolve(relativePath).path;
}

String _guessMimeType(String path) {
  switch (_extensionOf(path)) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'svg':
      return 'image/svg+xml';
    case 'webp':
      return 'image/webp';
    default:
      return 'application/octet-stream';
  }
}

String? _docxTitle(Map<String, ArchiveFile> entries) {
  final coreEntry = entries['docProps/core.xml'];
  if (coreEntry == null) {
    return null;
  }

  try {
    final coreXml = XmlDocument.parse(
      utf8.decode(coreEntry.content, allowMalformed: true),
    );
    final title = coreXml.descendants
        .whereType<XmlElement>()
        .firstWhere(
          (element) => element.name.local == 'title',
          orElse: () => XmlElement(XmlName('title')),
        )
        .innerText
        .trim();
    return title.isEmpty ? null : title;
  } catch (_) {
    return null;
  }
}

_DocxParagraphContent? _extractDocxParagraph(XmlElement paragraph) {
  final styleElement = paragraph.descendants.whereType<XmlElement>().firstWhere(
    (element) => element.name.local == 'pStyle',
    orElse: () => XmlElement(XmlName('pStyle')),
  );
  final styleValue = styleElement.attributes
      .firstWhere(
        (attribute) => attribute.name.local == 'val',
        orElse: () => XmlAttribute(XmlName('val'), ''),
      )
      .value;
  final htmlTag = switch (styleValue) {
    'Heading1' => 'h1',
    'Heading2' => 'h2',
    'Heading3' => 'h3',
    _ => 'p',
  };

  final htmlBuffer = StringBuffer();
  final speakableBuffer = StringBuffer();
  var hasImage = false;

  for (final node in paragraph.descendants) {
    if (node is! XmlElement) {
      continue;
    }

    switch (node.name.local) {
      case 't':
        final text = node.innerText;
        if (text.isEmpty) {
          break;
        }
        htmlBuffer.write(const HtmlEscape().convert(text));
        speakableBuffer.write(text);
        break;
      case 'tab':
        htmlBuffer.write(' ');
        speakableBuffer.write(' ');
        break;
      case 'br':
      case 'cr':
        htmlBuffer.write('<br />');
        speakableBuffer.write('\n');
        break;
      case 'drawing':
      case 'pict':
        hasImage = true;
        break;
      default:
        break;
    }
  }

  final speakableText = _normalizeImportedText(speakableBuffer.toString());
  final htmlText = htmlBuffer.toString().trim();
  if (speakableText.isEmpty && htmlText.isEmpty && !hasImage) {
    return null;
  }

  return _DocxParagraphContent(
    htmlTag: htmlTag,
    htmlText: htmlText.isEmpty ? '&nbsp;' : htmlText,
    speakableText: speakableText,
    hasImage: hasImage,
  );
}

String _decodeRtf(String raw) {
  var text = raw;
  text = text.replaceAllMapped(RegExp(r"\\'([0-9a-fA-F]{2})"), (match) {
    final value = int.parse(match.group(1)!, radix: 16);
    return latin1.decode([value]);
  });
  text = text.replaceAllMapped(RegExp(r'\\u(-?\d+)\??'), (match) {
    final value = int.tryParse(match.group(1)!);
    if (value == null) {
      return '';
    }
    final normalized = value < 0 ? value + 65536 : value;
    return String.fromCharCode(normalized);
  });
  text = text.replaceAll(r'\par', '\n\n');
  text = text.replaceAll(r'\line', '\n');
  text = text.replaceAll(r'\tab', '\t');
  text = text.replaceAll(RegExp(r'\\[a-zA-Z]+\d* ?'), '');
  text = text.replaceAll(RegExp(r'[{}]'), '');
  return _normalizeImportedText(text);
}

String _normalizeImportedText(String text) {
  return text
      .replaceAll('\r', '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
