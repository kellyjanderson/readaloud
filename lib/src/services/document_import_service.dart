import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../models/reader_document.dart';

class DocumentImportService {
  Future<ReaderDocument> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final extension = _extensionOf(fileName);
    switch (extension) {
      case 'txt':
      case 'text':
      case 'md':
        return _importPlainText(fileName, bytes);
      case 'html':
      case 'htm':
        return _importHtml(fileName, bytes);
      case 'epub':
        return _importEpub(fileName, bytes);
      case 'pdf':
        return _importPdfPlaceholder(fileName);
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

  ReaderDocument _importPdfPlaceholder(String fileName) {
    const html = '''
<article>
  <h1>PDF Import Is Not Wired Yet</h1>
  <p>
    The app shell accepts PDF files so the importer pipeline is in place, but the PDF text extraction
    path is not implemented in this first pass. The next build should replace this placeholder with a
    real PDF adapter that can extract speakable text and preserve a useful reading surface.
  </p>
</article>
''';
    const speakable = '''
This PDF importer is not implemented yet. The file was accepted into the pipeline, but text
extraction and rich display still need to be added.
''';
    return ReaderDocument(
      title: fileName,
      type: ReaderDocumentType.pdf,
      displayHtml: html,
      speakableText: speakable,
      sourceDescription: 'PDF placeholder import',
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
