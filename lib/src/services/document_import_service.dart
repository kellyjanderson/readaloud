import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../models/display_document.dart';
import '../models/document_import_exception.dart';
import '../models/import_diagnostic.dart';
import '../models/normalized_import_result.dart';
import '../models/position_map.dart';
import '../models/reader_document.dart';
import '../models/speech_document.dart';
import 'base_speech_annotation_inference_service.dart';
import 'document_time_pronunciation_planner_service.dart';
import 'english_pronunciation_profile_selector.dart';
import 'english_suffix_allomorph_module.dart';
import 'english_speech_preprocessor.dart';
import 'pronunciation_resource_layering_service.dart';

abstract class PdfTextExtractor {
  Future<PdfTextExtractionResult> extract({
    required String fileName,
    required Uint8List bytes,
  });
}

class PdfTextExtractionResult {
  const PdfTextExtractionResult({required this.pages});

  final List<PdfTextExtractionPage> pages;
}

class PdfTextExtractionPage {
  const PdfTextExtractionPage({
    required this.pageIndex,
    required this.fullText,
  });

  final int pageIndex;
  final String fullText;
}

class PdfrxPdfTextExtractor implements PdfTextExtractor {
  const PdfrxPdfTextExtractor();

  @override
  Future<PdfTextExtractionResult> extract({
    required String fileName,
    required Uint8List bytes,
  }) async {
    PdfDocument? document;

    try {
      document = await PdfDocument.openData(bytes, sourceName: fileName);
      final pages = <PdfTextExtractionPage>[];
      for (
        var pageIndex = 0;
        pageIndex < document.pages.length;
        pageIndex += 1
      ) {
        final page = document.pages[pageIndex];
        final pageText = await page.loadStructuredText();
        pages.add(
          PdfTextExtractionPage(
            pageIndex: pageIndex,
            fullText: pageText.fullText,
          ),
        );
      }
      return PdfTextExtractionResult(pages: pages);
    } finally {
      await document?.dispose();
    }
  }
}

class DocumentImportService {
  DocumentImportService({
    BaseSpeechAnnotationInferenceService? annotationInferenceService,
    DocumentTimePronunciationPlannerService? pronunciationPlannerService,
    EnglishPronunciationProfileSelector? pronunciationProfileSelector,
    PronunciationResourceLayeringService? pronunciationResourceLayeringService,
    PdfTextExtractor? pdfTextExtractor,
  }) : _annotationInferenceService =
           annotationInferenceService ??
           const BaseSpeechAnnotationInferenceService(),
       _pronunciationPlannerService =
           pronunciationPlannerService ??
           const DocumentTimePronunciationPlannerService(),
       _pronunciationProfileSelector =
           pronunciationProfileSelector ??
           const EnglishPronunciationProfileSelector(),
       _pronunciationResourceLayeringService =
           pronunciationResourceLayeringService ??
           const PronunciationResourceLayeringService(),
       _pdfTextExtractor = pdfTextExtractor ?? const PdfrxPdfTextExtractor();

  static const _normalizationVersion = 'read-aloud-normalization-v1';
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

  final BaseSpeechAnnotationInferenceService _annotationInferenceService;
  final DocumentTimePronunciationPlannerService _pronunciationPlannerService;
  final EnglishPronunciationProfileSelector _pronunciationProfileSelector;
  final PronunciationResourceLayeringService
  _pronunciationResourceLayeringService;
  final PdfTextExtractor _pdfTextExtractor;

  Future<ReaderDocument> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final sourceDescriptor = _sourceDescriptorForBytes(
      fileName: fileName,
      bytes: bytes,
    );
    final extension = _extensionOf(fileName);
    switch (extension) {
      case 'txt':
      case 'text':
      case 'md':
      case 'markdown':
        return _importPlainText(fileName, bytes, sourceDescriptor);
      case 'html':
      case 'htm':
        return _importHtml(fileName, bytes, sourceDescriptor);
      case 'epub':
        return _importEpub(fileName, bytes, sourceDescriptor);
      case 'pdf':
        return _importPdf(fileName, bytes, sourceDescriptor);
      case 'docx':
        return _importDocx(fileName, bytes, sourceDescriptor);
      case 'rtf':
        return _importRtf(fileName, bytes, sourceDescriptor);
      default:
        return _unsupportedDocument(fileName, sourceDescriptor);
    }
  }

  ReaderDocument importPastedText(String text) {
    final sourceDescriptor = _sourceDescriptorForText(
      title: 'Pasted Text',
      text: text,
      mode: 'pasted-text',
    );
    final recovered = _recoverPlainTextStructure(text);
    return _buildReaderDocument(
      title: 'Pasted Text',
      type: ReaderDocumentType.plainText,
      displayHtml: recovered.displayHtml,
      speakableText: recovered.speakableText,
      sourceDescriptor: sourceDescriptor,
      sourceDescription: 'Pasted into Read Aloud',
      diagnostics: const [
        ImportDiagnostic(
          severity: ImportDiagnosticSeverity.info,
          code: 'fallback_paragraph_grouping',
          message:
              'Pasted text paragraph grouping used lightweight line-wrap recovery heuristics.',
        ),
      ],
    );
  }

  ReaderDocument importSharedText(String text) {
    final sourceDescriptor = _sourceDescriptorForText(
      title: 'Shared Text',
      text: text,
      mode: 'shared-text',
    );
    final recovered = _recoverPlainTextStructure(text);
    return _buildReaderDocument(
      title: 'Shared Text',
      type: ReaderDocumentType.plainText,
      displayHtml: recovered.displayHtml,
      speakableText: recovered.speakableText,
      sourceDescriptor: sourceDescriptor,
      sourceDescription: 'Shared into Read Aloud',
      diagnostics: const [
        ImportDiagnostic(
          severity: ImportDiagnosticSeverity.info,
          code: 'fallback_paragraph_grouping',
          message:
              'Shared text paragraph grouping used lightweight line-wrap recovery heuristics.',
        ),
      ],
    );
  }

  ReaderDocument _importPlainText(
    String fileName,
    Uint8List bytes,
    _ImportSourceDescriptor sourceDescriptor,
  ) {
    final recovered = _recoverPlainTextStructure(
      utf8.decode(bytes, allowMalformed: true),
    );
    return _buildReaderDocument(
      title: fileName,
      type: ReaderDocumentType.plainText,
      displayHtml: recovered.displayHtml,
      speakableText: recovered.speakableText,
      sourceDescriptor: sourceDescriptor,
      sourceDescription: 'Plain text import',
      diagnostics: const [
        ImportDiagnostic(
          severity: ImportDiagnosticSeverity.info,
          code: 'fallback_paragraph_grouping',
          message:
              'Plain text paragraph grouping used lightweight line-wrap recovery heuristics.',
        ),
      ],
    );
  }

  ReaderDocument _importHtml(
    String fileName,
    Uint8List bytes,
    _ImportSourceDescriptor sourceDescriptor,
  ) {
    final rawHtml = utf8.decode(bytes, allowMalformed: true);
    final document = html_parser.parse(rawHtml);
    final diagnostics = <ImportDiagnostic>[];
    final body = document.body;
    if (body != null) {
      _pruneHtmlForNormalization(body, diagnostics: diagnostics);
    }
    final bodyHtml = body?.innerHtml ?? rawHtml;
    final speakableText = _normalizeReadableText(body?.text.trim() ?? '');
    return _buildReaderDocument(
      title: fileName,
      type: ReaderDocumentType.html,
      displayHtml: '<article>$bodyHtml</article>',
      speakableText: speakableText,
      sourceDescriptor: sourceDescriptor,
      sourceDescription: 'HTML import',
      diagnostics: diagnostics,
    );
  }

  Future<ReaderDocument> _importPdf(
    String fileName,
    Uint8List bytes,
    _ImportSourceDescriptor sourceDescriptor,
  ) async {
    final diagnostics = <ImportDiagnostic>[];

    try {
      final extraction = await _pdfTextExtractor.extract(
        fileName: fileName,
        bytes: bytes,
      );
      final speakablePages = <String>[];
      final normalizedPageBlocks = <String>[];

      for (final page in extraction.pages) {
        if (_looksLikeSuspiciousReadingOrder(page.fullText)) {
          diagnostics.add(
            ImportDiagnostic(
              severity: ImportDiagnosticSeverity.warning,
              code: 'reading_order_suspect',
              message:
                  'Extracted PDF line order may not reflect the intended reading order.',
              sourceLocator: 'page:${page.pageIndex}',
            ),
          );
        }
        final normalized = _normalizeReadableText(page.fullText);
        normalizedPageBlocks.add(
          '<div data-read-aloud-kind="page-break" data-page-index="${page.pageIndex}"></div>',
        );
        if (normalized.isNotEmpty) {
          speakablePages.add(normalized);
          for (final paragraph in normalized.split(RegExp(r'\n\s*\n'))) {
            final cleaned = paragraph.trim();
            if (cleaned.isEmpty) {
              continue;
            }
            normalizedPageBlocks.add(
              '<p data-page-index="${page.pageIndex}">${const HtmlEscape().convert(cleaned)}</p>',
            );
          }
        }
      }

      final pageCount = extraction.pages.length;
      final speakableText = speakablePages.join('\n\n').trim();
      final extractionNote = speakableText.isEmpty
          ? 'No extractable text was found for text-to-speech yet.'
          : 'Readable text was extracted for playback.';
      if (speakableText.isEmpty) {
        diagnostics.add(
          const ImportDiagnostic(
            severity: ImportDiagnosticSeverity.warning,
            code: 'missing_text_layer',
            message: 'The PDF did not expose extractable text for playback.',
          ),
        );
      } else {
        diagnostics.add(
          const ImportDiagnostic(
            severity: ImportDiagnosticSeverity.info,
            code: 'fallback_paragraph_grouping',
            message:
                'PDF paragraph recovery used lightweight extracted-text heuristics.',
          ),
        );
      }

      return _buildReaderDocument(
        title: fileName,
        type: ReaderDocumentType.pdf,
        displayHtml:
            '''
<article>
  <h1>${const HtmlEscape().convert(fileName)}</h1>
  <p>$extractionNote</p>
  ${normalizedPageBlocks.join('\n  ')}
</article>
''',
        speakableText: speakableText,
        sourceDescriptor: sourceDescriptor,
        diagnostics: diagnostics,
        presentation: ReaderDocumentPresentation.pdf,
        pdfData: bytes,
        sourceDescription:
            'PDF import, $pageCount page${pageCount == 1 ? '' : 's'}',
      );
    } on DocumentImportException {
      rethrow;
    } catch (error) {
      throw DocumentImportException(
        code: 'pdf_parse_failed',
        message: 'Read Aloud could not parse this PDF into a valid document.',
        fileName: fileName,
        cause: error,
      );
    }
  }

  ReaderDocument _importDocx(
    String fileName,
    Uint8List bytes,
    _ImportSourceDescriptor sourceDescriptor,
  ) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final entries = <String, ArchiveFile>{};
      for (final entry in archive.files) {
        entries[_normalizeArchivePath(entry.name)] = entry;
      }

      final documentEntry = entries['word/document.xml'];
      if (documentEntry == null) {
        throw DocumentImportException(
          code: 'docx_missing_document_xml',
          message:
              'Read Aloud could not import this DOCX because word/document.xml is missing.',
          fileName: fileName,
        );
      }

      final documentXml = XmlDocument.parse(
        utf8.decode(_entryBytes(documentEntry), allowMalformed: true),
      );
      final blocks = <String>[];
      final speakableText = StringBuffer();
      final attachments = <ReaderAttachment>[];
      final diagnostics = <ImportDiagnostic>[];

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
          diagnostics.add(
            const ImportDiagnostic(
              severity: ImportDiagnosticSeverity.info,
              code: 'lossy_conversion',
              message:
                  'DOCX inline media is preserved as an attachment placeholder in v1.',
            ),
          );
          blocks.add(
            '<div data-read-aloud-kind="attachment-placeholder" '
            'data-attachment-type="image" '
            'data-label="Inline DOCX media"></div>',
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

      return _buildReaderDocument(
        title: title,
        type: ReaderDocumentType.html,
        displayHtml: displayHtml,
        speakableText: speakableText.toString().trim(),
        sourceDescriptor: sourceDescriptor,
        sourceDescription: 'DOCX import',
        attachments: attachments,
        diagnostics: diagnostics,
      );
    } on DocumentImportException {
      rethrow;
    } catch (error) {
      throw DocumentImportException(
        code: 'docx_parse_failed',
        message: 'Read Aloud could not parse this DOCX into a valid document.',
        fileName: fileName,
        cause: error,
      );
    }
  }

  ReaderDocument _importRtf(
    String fileName,
    Uint8List bytes,
    _ImportSourceDescriptor sourceDescriptor,
  ) {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final recovered = _recoverPlainTextStructure(_decodeRtf(raw));
    return _buildReaderDocument(
      title: fileName,
      type: ReaderDocumentType.plainText,
      displayHtml: recovered.displayHtml,
      speakableText: recovered.speakableText,
      sourceDescriptor: sourceDescriptor,
      sourceDescription: 'RTF import',
      diagnostics: const [
        ImportDiagnostic(
          severity: ImportDiagnosticSeverity.warning,
          code: 'lossy_conversion',
          message: 'RTF formatting is flattened during v1 import.',
        ),
        ImportDiagnostic(
          severity: ImportDiagnosticSeverity.info,
          code: 'fallback_paragraph_grouping',
          message:
              'Flattened RTF paragraph grouping used lightweight line-wrap recovery heuristics.',
        ),
      ],
    );
  }

  ReaderDocument _unsupportedDocument(
    String fileName,
    _ImportSourceDescriptor sourceDescriptor,
  ) {
    return _buildReaderDocument(
      title: fileName,
      type: ReaderDocumentType.unsupported,
      displayHtml: '''
<article>
  <h1>Unsupported Format</h1>
  <p>Read Aloud does not know how to import this document yet.</p>
</article>
''',
      speakableText: 'This document format is not supported yet.',
      sourceDescriptor: sourceDescriptor,
      sourceDescription: 'Unsupported file type',
      diagnostics: const [
        ImportDiagnostic(
          severity: ImportDiagnosticSeverity.warning,
          code: 'unsupported_structure',
          message: 'The document format is not supported yet.',
        ),
      ],
    );
  }

  ReaderDocument _importEpub(
    String fileName,
    Uint8List bytes,
    _ImportSourceDescriptor sourceDescriptor,
  ) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final entries = <String, ArchiveFile>{};
      for (final entry in archive.files) {
        entries[_normalizeArchivePath(entry.name)] = entry;
      }

      final containerEntry = entries['META-INF/container.xml'];
      if (containerEntry == null) {
        throw DocumentImportException(
          code: 'epub_missing_container',
          message:
              'Read Aloud could not import this EPUB because META-INF/container.xml is missing.',
          fileName: fileName,
        );
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
        throw DocumentImportException(
          code: 'epub_missing_package_path',
          message:
              'Read Aloud could not import this EPUB because the package document path is missing.',
          fileName: fileName,
        );
      }

      final packageEntry = entries[_normalizeArchivePath(packagePath)];
      if (packageEntry == null) {
        throw DocumentImportException(
          code: 'epub_missing_package_document',
          message:
              'Read Aloud could not import this EPUB because the package document is missing.',
          fileName: fileName,
        );
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
          properties: item.getAttribute('properties') ?? '',
        );
      }

      final sections = <String>[];
      final speakableText = StringBuffer();
      final attachments = <ReaderAttachment>[];
      final diagnostics = <ImportDiagnostic>[];
      final metadataTitle = packageXml.descendants
          .whereType<XmlElement>()
          .firstWhere(
            (element) => element.name.local == 'title',
            orElse: () => XmlElement(XmlName('title')),
          )
          .innerText
          .trim();

      for (final itemref
          in packageXml.descendants.whereType<XmlElement>().where(
            (e) => e.name.local == 'itemref',
          )) {
        final idref = itemref.getAttribute('idref');
        final asset = idref == null ? null : manifest[idref];
        if (asset == null) continue;
        if (asset.isNavigationDocument) {
          diagnostics.add(
            ImportDiagnostic(
              severity: ImportDiagnosticSeverity.info,
              code: 'navigation_content_skipped',
              message:
                  'An EPUB navigation document was excluded from body content.',
              sourceLocator: asset.href,
            ),
          );
          continue;
        }
        final chapterEntry = entries[asset.href];
        if (chapterEntry == null) continue;

        final chapterHtml = utf8.decode(
          _entryBytes(chapterEntry),
          allowMalformed: true,
        );
        final parsed = html_parser.parse(chapterHtml);
        final body = parsed.body;
        if (body == null) continue;
        _pruneHtmlForNormalization(body, diagnostics: diagnostics);

        for (final image in body.querySelectorAll('img')) {
          final src = image.attributes['src'];
          if (src == null ||
              src.isEmpty ||
              src.startsWith('data:') ||
              src.startsWith('http')) {
            if (src == null || src.isEmpty) {
              diagnostics.add(
                const ImportDiagnostic(
                  severity: ImportDiagnosticSeverity.warning,
                  code: 'missing_asset',
                  message: 'An EPUB image reference was missing a source.',
                ),
              );
            }
            continue;
          }
          final resolved = _resolveArchivePath(asset.href, src);
          final imageEntry = entries[resolved];
          if (imageEntry == null) {
            diagnostics.add(
              ImportDiagnostic(
                severity: ImportDiagnosticSeverity.warning,
                code: 'missing_asset',
                message: 'An EPUB image resource could not be resolved.',
                sourceLocator: resolved,
              ),
            );
            continue;
          }
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

      return _buildReaderDocument(
        title: metadataTitle.isEmpty ? fileName : metadataTitle,
        type: ReaderDocumentType.epub,
        displayHtml: '<article>${sections.join('\n')}</article>',
        speakableText: speakableText.toString().trim(),
        sourceDescriptor: sourceDescriptor,
        sourceDescription: 'EPUB import',
        attachments: attachments,
        diagnostics: diagnostics,
      );
    } on DocumentImportException {
      rethrow;
    } catch (error) {
      throw DocumentImportException(
        code: 'epub_parse_failed',
        message: 'Read Aloud could not parse this EPUB into a valid document.',
        fileName: fileName,
        cause: error,
      );
    }
  }

  Uint8List _entryBytes(ArchiveFile file) {
    return file.readBytes() ?? Uint8List(0);
  }

  ReaderDocument _buildReaderDocument({
    required String title,
    required ReaderDocumentType type,
    required String displayHtml,
    required String speakableText,
    required _ImportSourceDescriptor sourceDescriptor,
    ReaderDocumentPresentation presentation = ReaderDocumentPresentation.html,
    Uint8List? pdfData,
    String? sourceDescription,
    List<ReaderAttachment> attachments = const <ReaderAttachment>[],
    List<ImportDiagnostic> diagnostics = const <ImportDiagnostic>[],
  }) {
    final normalized = _NormalizedDocumentFactory(
      title: title,
      type: type,
      sourceUri: sourceDescriptor.sourceUri,
      sourceFingerprint: sourceDescriptor.sourceFingerprint,
      displayHtml: displayHtml,
      speakableText: speakableText,
      diagnostics: diagnostics,
      normalizationVersion: _normalizationVersion,
    ).build();
    final baseSpeechAnnotations = _annotationInferenceService.infer(
      speechDocument: normalized.speechDocument,
      displayDocument: normalized.displayDocument,
    );
    final selectedProfile = _pronunciationProfileSelector.select(
      const EnglishPronunciationProfileSelectionInput(engineId: 'kokoro'),
    );
    final mergedPronunciationResources = _pronunciationResourceLayeringService
        .merge(PronunciationResourceLayeringInput(profile: selectedProfile));
    final basePronunciationArtifacts = _pronunciationPlannerService.plan(
      DocumentTimePronunciationPlannerInput(
        speechDocument: normalized.speechDocument,
        baseAnnotations: baseSpeechAnnotations,
        positionMap: normalized.positionMap,
        normalizationVersion: _normalizationVersion,
        selectedProfile: selectedProfile,
        mergedPronunciationResources: mergedPronunciationResources,
        enabledDocumentTimeRuleModules: const <EnglishSuffixAllomorphModule>[
          EnglishSuffixAllomorphModule(),
        ],
        diagnostics: normalized.diagnostics,
      ),
    );

    return ReaderDocument.fromNormalized(
      title: title,
      type: type,
      normalizedImportResult: normalized,
      baseSpeechAnnotations: baseSpeechAnnotations,
      basePronunciationArtifacts: basePronunciationArtifacts,
      presentation: presentation,
      pdfData: pdfData,
      sourceDescription: sourceDescription,
      attachments: attachments,
    );
  }
}

class _EpubAsset {
  const _EpubAsset({
    required this.href,
    required this.mediaType,
    required this.properties,
  });

  final String href;
  final String mediaType;
  final String properties;

  bool get isNavigationDocument => properties
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty)
      .contains('nav');
}

class _ImportSourceDescriptor {
  const _ImportSourceDescriptor({
    required this.sourceFingerprint,
    this.sourceUri,
  });

  final String sourceFingerprint;
  final Uri? sourceUri;
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

_ImportSourceDescriptor _sourceDescriptorForBytes({
  required String fileName,
  required Uint8List bytes,
}) {
  final builder = BytesBuilder(copy: false)
    ..add(utf8.encode(fileName))
    ..addByte(0)
    ..add(bytes);
  final sourceFingerprint =
      'src_${crypto.sha256.convert(builder.toBytes()).toString().substring(0, 24)}';
  return _ImportSourceDescriptor(
    sourceFingerprint: sourceFingerprint,
    sourceUri: null,
  );
}

_ImportSourceDescriptor _sourceDescriptorForText({
  required String title,
  required String text,
  required String mode,
}) {
  final normalizedText = normalizeEnglishSpeechText(text).trim();
  final sourceFingerprint =
      'src_${_stableHash('$mode:$title:$normalizedText').substring(0, 24)}';
  return _ImportSourceDescriptor(
    sourceFingerprint: sourceFingerprint,
    sourceUri: null,
  );
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
  final output = StringBuffer();
  final groups = <_RtfGroupState>[_RtfGroupState.root()];
  var unicodeFallbackLength = 1;

  for (var index = 0; index < raw.length; index += 1) {
    final group = groups.last;
    final char = raw[index];

    if (char == '{') {
      groups.add(_RtfGroupState.childOf(group));
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
            output.write(_decodeRtfHexByte(value));
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

      if (!_isAsciiLetter(next)) {
        group.markContentSeen();
        if (!group.ignorable) {
          final symbolText = _rtfControlSymbolText(next);
          if (symbolText != null) {
            output.write(symbolText);
          }
        }
        index += 1;
        continue;
      }

      var cursor = index + 1;
      while (cursor < raw.length && _isAsciiLetter(raw[cursor])) {
        cursor += 1;
      }
      final word = raw.substring(index + 1, cursor);

      final parameterStart = cursor;
      if (cursor < raw.length &&
          (raw[cursor] == '-' || _isAsciiDigit(raw[cursor]))) {
        cursor += 1;
        while (cursor < raw.length && _isAsciiDigit(raw[cursor])) {
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
              _rtfIgnoredDestinationWords.contains(word));
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
              _skipRtfUnicodeFallback(raw, cursor, unicodeFallbackLength) - 1;
        case 'par':
        case 'pard':
        case 'page':
        case 'sect':
          _appendRtfParagraphBreak(output);
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
  return _normalizeRtfDecodedText(output.toString());
}

String _normalizeRtfDecodedText(String text) {
  final punctuationNormalized = normalizeEnglishSpeechText(text)
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
      );

  return _normalizeReadableText(punctuationNormalized);
}

void _appendRtfParagraphBreak(StringBuffer output) {
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

bool _isAsciiDigit(String value) {
  return value.codeUnitAt(0) >= 0x30 && value.codeUnitAt(0) <= 0x39;
}

bool _isAsciiLetter(String value) {
  final codeUnit = value.codeUnitAt(0);
  return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);
}

int _skipRtfUnicodeFallback(String raw, int index, int count) {
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

String _decodeRtfHexByte(int value) {
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

String? _rtfControlSymbolText(String symbol) {
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

const Set<String> _rtfIgnoredDestinationWords = {
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

final class _RtfGroupState {
  _RtfGroupState.root() : ignorable = false;

  _RtfGroupState.childOf(_RtfGroupState parent) : ignorable = parent.ignorable;

  bool ignorable;
  bool atGroupStart = true;
  bool pendingStarDestination = false;

  void markContentSeen() {
    atGroupStart = false;
    pendingStarDestination = false;
  }
}

String _normalizeImportedText(String text) {
  return normalizeEnglishSpeechText(text)
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _normalizeReadableText(String text) {
  final normalized = _normalizeImportedText(text);
  if (normalized.isEmpty) {
    return '';
  }

  final paragraphMatches = RegExp(
    r'(?:^|\n\s*\n)(.*?)(?=(?:\n\s*\n)|$)',
    dotAll: true,
    multiLine: true,
  ).allMatches(normalized);

  final paragraphs = <String>[];
  for (final match in paragraphMatches) {
    final block = match.group(1)?.trim() ?? '';
    if (block.isEmpty) {
      continue;
    }
    paragraphs.add(_recoverWrappedParagraph(block));
  }
  if (paragraphs.isEmpty) {
    return _recoverWrappedParagraph(normalized);
  }
  return paragraphs.join('\n\n');
}

String _recoverWrappedParagraph(String block) {
  final lines = block
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) {
    return '';
  }

  final buffer = StringBuffer(lines.first);
  for (var index = 1; index < lines.length; index += 1) {
    final previous = buffer.toString();
    final next = lines[index];
    if (_looksLikeHyphenatedWrap(previous, next)) {
      final current = buffer.toString();
      buffer
        ..clear()
        ..write(current.substring(0, current.length - 1))
        ..write(next);
      continue;
    }
    buffer.write(' ');
    buffer.write(next);
  }
  return buffer.toString();
}

bool _looksLikeHyphenatedWrap(String previous, String next) {
  if (!previous.endsWith('-') || next.isEmpty) {
    return false;
  }
  final previousBody = previous.substring(0, previous.length - 1);
  final lastChar = previousBody.isEmpty
      ? ''
      : previousBody[previousBody.length - 1];
  final firstChar = next[0];
  final isLetterPair =
      RegExp(r'[A-Za-z]').hasMatch(lastChar) &&
      RegExp(r'[a-z]').hasMatch(firstChar);
  return isLetterPair;
}

class _NormalizedDocumentFactory {
  _NormalizedDocumentFactory({
    required this.title,
    required this.type,
    required this.sourceUri,
    required this.sourceFingerprint,
    required this.displayHtml,
    required this.speakableText,
    required this.diagnostics,
    required this.normalizationVersion,
  });

  final String title;
  final ReaderDocumentType type;
  final Uri? sourceUri;
  final String sourceFingerprint;
  final String displayHtml;
  final String speakableText;
  final List<ImportDiagnostic> diagnostics;
  final String normalizationVersion;

  NormalizedImportResult build() {
    final workingDiagnostics = List<ImportDiagnostic>.from(diagnostics);
    final documentId = 'doc_${_stableHash(sourceFingerprint).substring(0, 16)}';
    final parsed = html_parser.parse(displayHtml);
    final displayBuilder = _DisplayDocumentBuilder(
      documentId: documentId,
      sourceType: type.name,
      title: title,
      normalizationVersion: normalizationVersion,
      diagnostics: workingDiagnostics,
    );
    final root = parsed.body ?? parsed.documentElement;
    if (root != null) {
      for (final node in root.nodes) {
        displayBuilder.addNode(node);
      }
    }
    if (displayBuilder.blocks.isEmpty && title.isNotEmpty) {
      displayBuilder.addTextBlock(
        kind: DisplayBlockKind.heading,
        text: title,
        attributes: const {'level': '1'},
      );
    }
    if (displayBuilder.blocks.isEmpty && speakableText.trim().isNotEmpty) {
      for (final paragraph in speakableText.trim().split(RegExp(r'\n\s*\n'))) {
        displayBuilder.addTextBlock(
          kind: DisplayBlockKind.paragraph,
          text: paragraph.trim(),
        );
      }
    }

    final speechSegments = <SpeechSegment>[];
    final positionEntries = <PositionMapEntry>[];
    final textBlocks = displayBuilder.blocks
        .where((block) => block.plainText.trim().isNotEmpty)
        .toList(growable: false);
    final paragraphs = speakableText.trim().isEmpty
        ? <String>[]
        : speakableText.trim().split(RegExp(r'\n\s*\n'));

    var segmentOrdinal = 0;
    var paragraphIndex = 0;
    final nextDisplaySearchOffset = <String, int>{};
    for (final paragraph in paragraphs) {
      final normalizedParagraph = paragraph.trim();
      if (normalizedParagraph.isEmpty) {
        continue;
      }
      final block = textBlocks.isEmpty
          ? null
          : textBlocks[paragraphIndex.clamp(0, textBlocks.length - 1)];
      final sentences = _splitSentences(normalizedParagraph);
      for (
        var sentenceIndex = 0;
        sentenceIndex < sentences.length;
        sentenceIndex += 1
      ) {
        final sentence = sentences[sentenceIndex];
        if (sentence.isEmpty) {
          continue;
        }
        final segmentId = 's_$segmentOrdinal';
        final words = RegExp(
          r'\S+',
        ).allMatches(sentence).toList(growable: false);
        final displayBlockId = block?.blockId ?? 'b_$paragraphIndex';
        final matchStart = nextDisplaySearchOffset[displayBlockId] ?? 0;
        final displayStart = block == null
            ? 0
            : _matchOffset(block.plainText, sentence, matchStart);
        final displayEnd = displayStart + sentence.length;
        nextDisplaySearchOffset[displayBlockId] = math.max(
          matchStart,
          displayEnd,
        );

        speechSegments.add(
          SpeechSegment(
            segmentId: segmentId,
            blockId: displayBlockId,
            ordinal: segmentOrdinal,
            paragraphIndex: paragraphIndex,
            sentenceIndex: sentenceIndex,
            normalizedText: sentence,
            wordCount: words.length,
            sourceRange: null,
            displayAnchor: DisplayAnchor(
              blockId: displayBlockId,
              startInlineOffset: math.max(0, displayStart),
              endInlineOffset: math.max(0, displayEnd),
            ),
            wordSpans: [
              for (var wordIndex = 0; wordIndex < words.length; wordIndex += 1)
                SpeechWordSpan(
                  wordIndexWithinSegment: wordIndex,
                  startUtf16: words[wordIndex].start,
                  endUtf16: words[wordIndex].end,
                  text: words[wordIndex].group(0)!,
                ),
            ],
          ),
        );

        positionEntries.add(
          PositionMapEntry(
            entryId: 'pm_$segmentOrdinal',
            displayBlockId: displayBlockId,
            speechSegmentId: segmentId,
            displayStart: math.max(0, displayStart),
            displayEnd: math.max(0, displayEnd),
            speechStartWord: 0,
            speechEndWord: words.length,
            confidence: block == null
                ? 0.45
                : _confidenceForMatch(block.plainText, sentence),
            recoveryAnchor: RecoveryAnchor(
              exact: sentence,
              prefix: _prefixFor(sentence),
              suffix: _suffixFor(sentence),
            ),
            sourceAnchor: _sourceAnchorForBlock(type, block),
          ),
        );
        if (block == null ||
            !_normalizeImportedText(block.plainText).contains(sentence)) {
          workingDiagnostics.add(
            ImportDiagnostic(
              severity: ImportDiagnosticSeverity.warning,
              code: 'low_mapping_confidence',
              message:
                  'A speech segment could not be aligned confidently to its display block.',
              relatedBlockId: displayBlockId,
              sourceLocator: segmentId,
            ),
          );
        }
        segmentOrdinal += 1;
      }
      paragraphIndex += 1;
    }

    final displayDocument = DisplayDocument(
      documentId: documentId,
      sourceType: type.name,
      sourceUri: sourceUri,
      title: title,
      blocks: displayBuilder.blocks,
      assets: displayBuilder.assets,
      metadata: <String, String>{'sourceFingerprint': sourceFingerprint},
      normalizationVersion: normalizationVersion,
    );
    final speechDocument = SpeechDocument(
      documentId: documentId,
      sourceType: type.name,
      languageTag: 'en-US',
      segments: speechSegments,
      segmentIndexById: {
        for (var index = 0; index < speechSegments.length; index += 1)
          speechSegments[index].segmentId: index,
      },
      totalWordCount: speechSegments.fold<int>(
        0,
        (sum, segment) => sum + segment.wordCount,
      ),
      normalizationVersion: normalizationVersion,
    );
    final positionMap = PositionMap(
      documentId: documentId,
      mappingVersion: normalizationVersion,
      entries: positionEntries,
    );
    return NormalizedImportResult(
      documentId: documentId,
      sourceType: type.name,
      bestAvailableTitle: title,
      sourceUri: sourceUri,
      sourceFingerprint: sourceFingerprint,
      normalizationVersion: normalizationVersion,
      mappingVersion: normalizationVersion,
      displayDocument: displayDocument,
      speechDocument: speechDocument,
      positionMap: positionMap,
      diagnostics: workingDiagnostics,
    );
  }
}

class _DisplayDocumentBuilder {
  _DisplayDocumentBuilder({
    required this.documentId,
    required this.sourceType,
    required this.title,
    required this.normalizationVersion,
    required this.diagnostics,
  });

  final String documentId;
  final String sourceType;
  final String title;
  final String normalizationVersion;
  final List<ImportDiagnostic> diagnostics;

  final List<DisplayBlock> blocks = <DisplayBlock>[];
  final Map<String, DisplayAsset> assets = <String, DisplayAsset>{};

  int _blockOrdinal = 0;
  int _assetOrdinal = 0;

  void addNode(html_dom.Node node, {String? parentBlockId}) {
    if (node is html_dom.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) {
        addTextBlock(
          kind: DisplayBlockKind.paragraph,
          text: text,
          parentBlockId: parentBlockId,
        );
      }
      return;
    }

    if (node is! html_dom.Element) {
      return;
    }

    final tag = node.localName?.toLowerCase();
    if (tag == null) {
      return;
    }

    if (_isHiddenNode(node)) {
      return;
    }

    switch (tag) {
      case 'script':
      case 'style':
        return;
      case 'nav':
        diagnostics.add(
          const ImportDiagnostic(
            severity: ImportDiagnosticSeverity.info,
            code: 'navigation_content_skipped',
            message: 'Navigation scaffolding was excluded from body content.',
          ),
        );
        return;
      case 'article':
      case 'section':
      case 'div':
      case 'main':
      case 'body':
        if (node.attributes['data-read-aloud-kind'] ==
            'attachment-placeholder') {
          addStructuralBlock(
            kind: DisplayBlockKind.unsupported,
            attributes: {
              'tag': node.attributes['data-attachment-type'] ?? 'attachment',
              if ((node.attributes['data-label'] ?? '').isNotEmpty)
                'label': node.attributes['data-label']!,
            },
            parentBlockId: parentBlockId,
          );
          return;
        }
        if (node.attributes['data-read-aloud-kind'] == 'page-break') {
          addStructuralBlock(
            kind: DisplayBlockKind.pageBreak,
            attributes: {
              if ((node.attributes['data-page-index'] ?? '').isNotEmpty)
                'pageIndex': node.attributes['data-page-index']!,
            },
            parentBlockId: parentBlockId,
          );
          return;
        }
        for (final child in node.nodes) {
          addNode(child, parentBlockId: parentBlockId);
        }
        return;
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        addTextBlock(
          kind: DisplayBlockKind.heading,
          text: _normalizeImportedText(node.text),
          attributes: {'level': tag.substring(1)},
          parentBlockId: parentBlockId,
        );
        return;
      case 'p':
        addTextBlock(
          kind: DisplayBlockKind.paragraph,
          text: _normalizeImportedText(node.text),
          attributes: {
            if ((node.attributes['data-page-index'] ?? '').isNotEmpty)
              'pageIndex': node.attributes['data-page-index']!,
          },
          parentBlockId: parentBlockId,
        );
        return;
      case 'blockquote':
        addTextBlock(
          kind: DisplayBlockKind.blockquote,
          text: _normalizeImportedText(node.text),
          parentBlockId: parentBlockId,
        );
        return;
      case 'figure':
        for (final child in node.nodes) {
          addNode(child, parentBlockId: parentBlockId);
        }
        return;
      case 'figcaption':
      case 'caption':
        addTextBlock(
          kind: DisplayBlockKind.paragraph,
          text: _normalizeImportedText(node.text),
          attributes: const {'role': 'caption'},
          parentBlockId: parentBlockId,
        );
        return;
      case 'pre':
      case 'code':
        addTextBlock(
          kind: DisplayBlockKind.codeBlock,
          text: node.text.trim(),
          parentBlockId: parentBlockId,
        );
        return;
      case 'ul':
      case 'ol':
        final listBlockId = addStructuralBlock(
          kind: tag == 'ol'
              ? DisplayBlockKind.orderedList
              : DisplayBlockKind.unorderedList,
        );
        for (final child in node.children.where(
          (child) => child.localName?.toLowerCase() == 'li',
        )) {
          addNode(child, parentBlockId: listBlockId);
        }
        return;
      case 'li':
        addTextBlock(
          kind: DisplayBlockKind.listItem,
          text: _normalizeImportedText(node.text),
          parentBlockId: parentBlockId,
        );
        return;
      case 'table':
        addTextBlock(
          kind: DisplayBlockKind.table,
          text: _normalizeImportedText(node.text),
          parentBlockId: parentBlockId,
        );
        return;
      case 'hr':
        addStructuralBlock(kind: DisplayBlockKind.separator);
        return;
      case 'img':
        addAssetBlock(
          kind: DisplayBlockKind.image,
          assetKind: DisplayAssetKind.image,
          sourceTag: tag,
          resolvedUri: node.attributes['src'],
          mimeType: _guessMimeType(node.attributes['src'] ?? ''),
          metadata: {
            if ((node.attributes['alt'] ?? '').trim().isNotEmpty)
              'alt': node.attributes['alt']!,
          },
          parentBlockId: parentBlockId,
        );
        return;
      case 'audio':
        addAssetBlock(
          kind: DisplayBlockKind.audio,
          assetKind: DisplayAssetKind.audio,
          sourceTag: tag,
          resolvedUri: node.attributes['src'],
          mimeType: null,
          metadata: const <String, String>{},
          parentBlockId: parentBlockId,
        );
        return;
      case 'video':
        addAssetBlock(
          kind: DisplayBlockKind.video,
          assetKind: DisplayAssetKind.video,
          sourceTag: tag,
          resolvedUri: node.attributes['src'],
          mimeType: null,
          metadata: {
            if ((node.attributes['poster'] ?? '').trim().isNotEmpty)
              'poster': node.attributes['poster']!,
          },
          parentBlockId: parentBlockId,
        );
        return;
      default:
        final text = _normalizeImportedText(node.text);
        if (text.isNotEmpty) {
          addTextBlock(
            kind: DisplayBlockKind.unsupported,
            text: text,
            attributes: {'tag': tag},
            parentBlockId: parentBlockId,
          );
          diagnostics.add(
            ImportDiagnostic(
              severity: ImportDiagnosticSeverity.warning,
              code: 'unsupported_structure',
              message:
                  'A visible source structure was preserved as an unsupported block.',
              sourceLocator: tag,
            ),
          );
        }
    }
  }

  void addTextBlock({
    required DisplayBlockKind kind,
    required String text,
    Map<String, String> attributes = const <String, String>{},
    String? parentBlockId,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }
    blocks.add(
      DisplayBlock(
        blockId: 'b_${_blockOrdinal++}',
        kind: kind,
        inlines: [
          DisplayInline(
            kind: DisplayInlineKind.text,
            text: normalized,
            attributes: const <String, String>{},
          ),
        ],
        attributes: attributes,
        assetId: null,
        parentBlockId: parentBlockId,
        ordinal: blocks.length,
      ),
    );
  }

  String addStructuralBlock({
    required DisplayBlockKind kind,
    Map<String, String> attributes = const <String, String>{},
    String? parentBlockId,
  }) {
    final blockId = 'b_${_blockOrdinal++}';
    blocks.add(
      DisplayBlock(
        blockId: blockId,
        kind: kind,
        inlines: const [],
        attributes: attributes,
        assetId: null,
        parentBlockId: parentBlockId,
        ordinal: blocks.length,
      ),
    );
    return blockId;
  }

  void addAssetBlock({
    required DisplayBlockKind kind,
    required DisplayAssetKind assetKind,
    required String sourceTag,
    required String? resolvedUri,
    required String? mimeType,
    required Map<String, String> metadata,
    String? parentBlockId,
  }) {
    final uriText = (resolvedUri ?? '').trim();
    if (uriText.isEmpty) {
      final blockId = addStructuralBlock(
        kind: DisplayBlockKind.unsupported,
        attributes: {'tag': sourceTag},
        parentBlockId: parentBlockId,
      );
      diagnostics.add(
        ImportDiagnostic(
          severity: ImportDiagnosticSeverity.warning,
          code: 'missing_asset',
          message: 'A referenced media asset could not be resolved.',
          sourceLocator: sourceTag,
          relatedBlockId: blockId,
        ),
      );
      return;
    }
    final assetId = 'a_${_assetOrdinal++}';
    assets[assetId] = DisplayAsset(
      assetId: assetId,
      kind: assetKind,
      resolvedUri: Uri.parse(uriText),
      mimeType: mimeType,
      metadata: metadata,
    );
    blocks.add(
      DisplayBlock(
        blockId: 'b_${_blockOrdinal++}',
        kind: kind,
        inlines: const [],
        attributes: metadata,
        assetId: assetId,
        parentBlockId: parentBlockId,
        ordinal: blocks.length,
      ),
    );
  }
}

bool _isHiddenNode(html_dom.Element node) {
  if (node.attributes.containsKey('hidden')) {
    return true;
  }
  final style = node.attributes['style']?.toLowerCase() ?? '';
  return style.contains('display:none') || style.contains('visibility:hidden');
}

void _pruneHtmlForNormalization(
  html_dom.Element root, {
  required List<ImportDiagnostic> diagnostics,
}) {
  final removable = <html_dom.Element>[
    ...root.querySelectorAll('script'),
    ...root.querySelectorAll('style'),
  ];
  for (final element in removable) {
    element.remove();
  }

  final navigationNodes = root.querySelectorAll('nav');
  if (navigationNodes.isNotEmpty) {
    diagnostics.add(
      const ImportDiagnostic(
        severity: ImportDiagnosticSeverity.info,
        code: 'navigation_content_skipped',
        message: 'Navigation scaffolding was excluded from body content.',
      ),
    );
    for (final node in navigationNodes) {
      node.remove();
    }
  }

  final hiddenNodes = root
      .querySelectorAll('[hidden]')
      .where((element) => element.parent != null)
      .toList(growable: false);
  for (final node in hiddenNodes) {
    node.remove();
  }

  final styledNodes = root.querySelectorAll('[style]');
  for (final node in styledNodes) {
    if (_isHiddenNode(node)) {
      node.remove();
    }
  }
}

SourceAnchor? _sourceAnchorForBlock(
  ReaderDocumentType type,
  DisplayBlock? block,
) {
  if (block == null) {
    return null;
  }
  if (type == ReaderDocumentType.pdf) {
    final pageIndex = int.tryParse(block.attributes['pageIndex'] ?? '');
    if (pageIndex != null) {
      return PdfSourceAnchor(
        pageIndex: pageIndex,
        sourceBlockId: block.blockId,
      );
    }
  }
  return null;
}

class _RecoveredTextDocument {
  const _RecoveredTextDocument({
    required this.displayHtml,
    required this.speakableText,
  });

  final String displayHtml;
  final String speakableText;
}

enum _RecoveredTextBlockKind { heading, paragraph, orderedList, unorderedList }

class _RecoveredTextBlock {
  const _RecoveredTextBlock.heading({
    required this.text,
    required this.headingLevel,
  }) : kind = _RecoveredTextBlockKind.heading,
       items = const <String>[];

  const _RecoveredTextBlock.paragraph({required this.text})
    : kind = _RecoveredTextBlockKind.paragraph,
      headingLevel = null,
      items = const <String>[];

  const _RecoveredTextBlock.list({required this.kind, required this.items})
    : text = '',
      headingLevel = null;

  final _RecoveredTextBlockKind kind;
  final String text;
  final int? headingLevel;
  final List<String> items;
}

_RecoveredTextDocument _recoverPlainTextStructure(String text) {
  final normalized = normalizeEnglishSpeechText(text);
  final lines = normalized.split('\n');
  final blocks = <_RecoveredTextBlock>[];
  final paragraphLines = <String>[];
  List<String>? listItems;
  _RecoveredTextBlockKind? listKind;

  void flushParagraph() {
    if (paragraphLines.isEmpty) {
      return;
    }
    final paragraph = _recoverWrappedParagraph(paragraphLines.join('\n'));
    if (paragraph.isNotEmpty) {
      blocks.add(_RecoveredTextBlock.paragraph(text: paragraph));
    }
    paragraphLines.clear();
  }

  void flushList() {
    final items = listItems;
    final kind = listKind;
    if (items == null || kind == null || items.isEmpty) {
      listItems = null;
      listKind = null;
      return;
    }
    final recoveredItems = items
        .map((item) => _recoverWrappedParagraph(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (recoveredItems.isNotEmpty) {
      blocks.add(_RecoveredTextBlock.list(kind: kind, items: recoveredItems));
    }
    listItems = null;
    listKind = null;
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      flushParagraph();
      flushList();
      continue;
    }

    final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
    if (headingMatch != null) {
      flushParagraph();
      flushList();
      blocks.add(
        _RecoveredTextBlock.heading(
          text: headingMatch.group(2)!.trim(),
          headingLevel: headingMatch.group(1)!.length,
        ),
      );
      continue;
    }

    final unorderedMatch = RegExp(r'^[-*+]\s+(.+)$').firstMatch(line);
    if (unorderedMatch != null) {
      flushParagraph();
      if (listKind != _RecoveredTextBlockKind.unorderedList) {
        flushList();
        listKind = _RecoveredTextBlockKind.unorderedList;
        listItems = <String>[];
      }
      listItems!.add(unorderedMatch.group(1)!.trim());
      continue;
    }

    final orderedMatch = RegExp(r'^\d+[.)]\s+(.+)$').firstMatch(line);
    if (orderedMatch != null) {
      flushParagraph();
      if (listKind != _RecoveredTextBlockKind.orderedList) {
        flushList();
        listKind = _RecoveredTextBlockKind.orderedList;
        listItems = <String>[];
      }
      listItems!.add(orderedMatch.group(1)!.trim());
      continue;
    }

    if (listItems != null) {
      flushList();
    }
    if (paragraphLines.isNotEmpty &&
        _shouldStartNewParagraphFromLineBreak(
          previousLine: paragraphLines.last,
          currentLine: line,
        )) {
      flushParagraph();
    }
    paragraphLines.add(line);
  }

  flushParagraph();
  flushList();

  final htmlBuffer = StringBuffer('<article>');
  final speakableParts = <String>[];
  for (final block in blocks) {
    switch (block.kind) {
      case _RecoveredTextBlockKind.heading:
        final level = block.headingLevel!.clamp(1, 6);
        htmlBuffer.write(
          '<h$level>${const HtmlEscape().convert(block.text)}</h$level>',
        );
        speakableParts.add(block.text);
        break;
      case _RecoveredTextBlockKind.paragraph:
        htmlBuffer.write('<p>${const HtmlEscape().convert(block.text)}</p>');
        speakableParts.add(block.text);
        break;
      case _RecoveredTextBlockKind.orderedList:
        htmlBuffer.write('<ol>');
        for (final item in block.items) {
          htmlBuffer.write('<li>${const HtmlEscape().convert(item)}</li>');
          speakableParts.add(item);
        }
        htmlBuffer.write('</ol>');
        break;
      case _RecoveredTextBlockKind.unorderedList:
        htmlBuffer.write('<ul>');
        for (final item in block.items) {
          htmlBuffer.write('<li>${const HtmlEscape().convert(item)}</li>');
          speakableParts.add(item);
        }
        htmlBuffer.write('</ul>');
        break;
    }
  }
  htmlBuffer.write('</article>');

  return _RecoveredTextDocument(
    displayHtml: htmlBuffer.toString(),
    speakableText: speakableParts.join('\n\n').trim(),
  );
}

bool _shouldStartNewParagraphFromLineBreak({
  required String previousLine,
  required String currentLine,
}) {
  if (previousLine.isEmpty || currentLine.isEmpty) {
    return false;
  }
  if (_looksLikeHyphenatedWrap(previousLine, currentLine)) {
    return false;
  }
  if (!_endsWithTerminalPunctuation(previousLine)) {
    return false;
  }

  final normalizedCurrent = currentLine.trimLeft();
  if (normalizedCurrent.isEmpty) {
    return false;
  }

  final startsLikeContinuation = RegExp(
    r'''^[,;:)\]}]|^[a-z]''',
  ).hasMatch(normalizedCurrent);
  if (startsLikeContinuation) {
    return false;
  }

  return true;
}

bool _looksLikeSuspiciousReadingOrder(String rawText) {
  final lines = rawText
      .replaceAll('\r', '')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.length < 10) {
    return false;
  }

  final shortLines = lines.where((line) => line.length <= 44).length;
  final unpunctuatedLines = lines
      .where((line) => !_endsWithTerminalPunctuation(line))
      .length;
  final lowerCaseStarts = lines
      .skip(1)
      .where((line) => RegExp(r'^[a-z]').hasMatch(line))
      .length;

  return shortLines / lines.length >= 0.65 &&
      unpunctuatedLines / lines.length >= 0.6 &&
      lowerCaseStarts / (lines.length - 1) >= 0.5;
}

bool _endsWithTerminalPunctuation(String line) {
  if (line.isEmpty) {
    return false;
  }
  const terminalCharacters = '.!?:;,"\')]}';
  return terminalCharacters.contains(line[line.length - 1]);
}

List<String> _splitSentences(String paragraph) {
  final normalized = paragraph.trim();
  if (normalized.isEmpty) {
    return const <String>[];
  }
  final matches =
      RegExp(r'''[^.!?]+(?:[.!?]+(?:["'”’)\]}]+)?(?=\s|$)|$)''', dotAll: true)
          .allMatches(normalized)
          .map((match) => match.group(0)!.trim())
          .where((sentence) => sentence.isNotEmpty)
          .toList(growable: false);
  return matches.isEmpty ? <String>[normalized] : matches;
}

int _matchOffset(String blockText, String sentence, int startAt) {
  final normalizedBlock = _normalizeImportedText(blockText);
  final index = normalizedBlock.indexOf(sentence, startAt);
  return index >= 0 ? index : 0;
}

double _confidenceForMatch(String blockText, String sentence) {
  final normalizedBlock = _normalizeImportedText(blockText);
  return normalizedBlock.contains(sentence) ? 0.95 : 0.55;
}

String? _prefixFor(String sentence) {
  if (sentence.length <= 24) {
    return null;
  }
  return sentence.substring(0, 24);
}

String? _suffixFor(String sentence) {
  if (sentence.length <= 24) {
    return null;
  }
  return sentence.substring(sentence.length - 24);
}

String _stableHash(String input) {
  return crypto.sha256.convert(utf8.encode(input)).toString();
}
