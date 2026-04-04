import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/display_document.dart';
import 'package:read_aloud/src/models/document_import_exception.dart';
import 'package:read_aloud/src/models/import_diagnostic.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/services/document_import_service.dart';

void main() {
  group('DocumentImportService', () {
    test('normalizes pasted text into normalized document structures', () {
      final service = DocumentImportService();
      final document = service.importPastedText('''
This is a wrapped para-
graph line.

Second paragraph here.
''');

      expect(document.displayDocument.blocks, isNotEmpty);
      expect(document.speechDocument.segments, isNotEmpty);
      expect(document.positionMap.entries, isNotEmpty);
      expect(document.baseSpeechAnnotations.annotations, isNotEmpty);
      expect(
        document.dialogueAttributions.documentId,
        document.normalizedImportResult.documentId,
      );
      expect(document.basePronunciationArtifacts.artifacts, isNotEmpty);
      expect(document.speakableText, contains('paragraph'));
      expect(document.speakableText, isNot(contains('para-\ngraph')));
      expect(
        document.displayDocument.blocks.first.kind,
        DisplayBlockKind.paragraph,
      );
      expect(
        identical(
          document.normalizedImportResult.displayDocument,
          document.displayDocument,
        ),
        isTrue,
      );
      expect(
        identical(
          document.normalizedImportResult.speechDocument,
          document.speechDocument,
        ),
        isTrue,
      );
      expect(
        identical(
          document.normalizedImportResult.positionMap,
          document.positionMap,
        ),
        isTrue,
      );
      expect(document.normalizedImportResult.documentId, startsWith('doc_'));
      expect(
        document.normalizedImportResult.sourceFingerprint,
        startsWith('src_'),
      );
      expect(
        document.displayDocument.metadata['sourceFingerprint'],
        document.normalizedImportResult.sourceFingerprint,
      );
      expect(
        document.displayDocument.documentId,
        document.speechDocument.documentId,
      );
      expect(
        document.positionMap.documentId,
        document.displayDocument.documentId,
      );
    });

    test('sample document exposes normalized display and speech content', () {
      final document = ReaderDocument.sample();

      expect(document.displayDocument.title, 'For Probe');
      expect(document.speechDocument.totalWordCount, greaterThan(0));
      expect(document.positionMap.entries, isNotEmpty);
      expect(document.baseSpeechAnnotations.annotations, isNotEmpty);
      expect(
        document.dialogueAttributions.documentId,
        document.normalizedImportResult.documentId,
      );
      expect(document.basePronunciationArtifacts.artifacts, isNotEmpty);
      expect(
        document.basePronunciationArtifacts.artifacts.any(
          (artifact) => artifact.normalizedSurfaceText == 'for',
        ),
        isTrue,
      );
      expect(document.speakableText, contains('I waited for them.'));
      expect(document.normalizedImportResult.bestAvailableTitle, 'For Probe');
    });

    test('imports Love.txt without crashing on dialogue punctuation', () async {
      final service = DocumentImportService();
      final file = File('project/testdocs/Love.txt');
      final document = await service.importBytes(
        fileName: 'Love.txt',
        bytes: await file.readAsBytes(),
      );

      expect(document.title, 'Love.txt');
      expect(document.speechDocument.segments, isNotEmpty);
      expect(document.speakableText, contains('John and Elliot were fighting'));
    });

    test(
      'source fingerprint remains stable for repeated file imports',
      () async {
        final service = DocumentImportService();
        final bytes = Uint8List.fromList(
          utf8.encode('A source document with stable identity.'),
        );

        final first = await service.importBytes(
          fileName: 'stable.txt',
          bytes: bytes,
        );
        final second = await service.importBytes(
          fileName: 'stable.txt',
          bytes: bytes,
        );

        expect(
          first.normalizedImportResult.sourceFingerprint,
          second.normalizedImportResult.sourceFingerprint,
        );
        expect(
          first.normalizedImportResult.documentId,
          second.normalizedImportResult.documentId,
        );
      },
    );

    test(
      'html import preserves lists and skips navigation scaffolding',
      () async {
        final service = DocumentImportService();
        final document = await service.importBytes(
          fileName: 'sample.html',
          bytes: Uint8List.fromList(
            utf8.encode('''
<html>
  <body>
    <nav>Site navigation</nav>
    <h1>Imported Title</h1>
    <ul>
      <li>First item</li>
      <li>Second item</li>
    </ul>
  </body>
</html>
'''),
          ),
        );

        expect(
          document.displayDocument.blocks.any(
            (block) => block.kind == DisplayBlockKind.heading,
          ),
          isTrue,
        );
        expect(
          document.displayDocument.blocks.any(
            (block) => block.kind == DisplayBlockKind.unorderedList,
          ),
          isTrue,
        );
        expect(
          document.displayDocument.blocks.where(
            (block) => block.kind == DisplayBlockKind.listItem,
          ),
          hasLength(2),
        );
        expect(document.speakableText, isNot(contains('Site navigation')));
        expect(
          document.diagnostics.any(
            (diagnostic) => diagnostic.code == 'navigation_content_skipped',
          ),
          isTrue,
        );
      },
    );

    test(
      'html import emits missing asset diagnostics for unresolved media',
      () async {
        final service = DocumentImportService();
        final document = await service.importBytes(
          fileName: 'broken-media.html',
          bytes: Uint8List.fromList(
            utf8.encode('''
<html>
  <body>
    <p>Paragraph</p>
    <img alt="Broken image">
  </body>
</html>
'''),
          ),
        );

        expect(
          document.diagnostics.where(
            (diagnostic) =>
                diagnostic.code == 'missing_asset' &&
                diagnostic.severity == ImportDiagnosticSeverity.warning,
          ),
          isNotEmpty,
        );
        expect(
          document.displayDocument.blocks.any(
            (block) => block.kind == DisplayBlockKind.unsupported,
          ),
          isTrue,
        );
      },
    );

    test(
      'html import preserves captions and explicit separators while removing hidden content',
      () async {
        final service = DocumentImportService();
        final document = await service.importBytes(
          fileName: 'captioned.html',
          bytes: Uint8List.fromList(
            utf8.encode('''
<html>
  <body>
    <figure>
      <img alt="Cover art" src="cover.png">
      <figcaption>Cover illustration caption.</figcaption>
    </figure>
    <p hidden>This should be removed.</p>
    <hr>
  </body>
</html>
'''),
          ),
        );

        expect(
          document.displayDocument.blocks.any(
            (block) =>
                block.kind == DisplayBlockKind.paragraph &&
                block.attributes['role'] == 'caption' &&
                block.plainText == 'Cover illustration caption.',
          ),
          isTrue,
        );
        expect(
          document.displayDocument.blocks.any(
            (block) => block.kind == DisplayBlockKind.separator,
          ),
          isTrue,
        );
        expect(document.speakableText, contains('Cover illustration caption.'));
        expect(
          document.speakableText,
          isNot(contains('This should be removed.')),
        );
      },
    );

    test('plain text recovery preserves explicit headings and list items', () {
      final service = DocumentImportService();
      final document = service.importPastedText('''
# Imported Heading

- First bullet
- Second bullet

Wrapped para-
graph line.
''');

      expect(
        document.displayDocument.blocks.first.kind,
        DisplayBlockKind.heading,
      );
      expect(
        document.displayDocument.blocks.any(
          (block) => block.kind == DisplayBlockKind.unorderedList,
        ),
        isTrue,
      );
      expect(
        document.displayDocument.blocks.where(
          (block) => block.kind == DisplayBlockKind.listItem,
        ),
        hasLength(2),
      );
      expect(document.speakableText, contains('Imported Heading'));
      expect(document.speakableText, contains('First bullet'));
      expect(document.speakableText, contains('paragraph line.'));
      expect(
        document.diagnostics.any(
          (diagnostic) => diagnostic.code == 'fallback_paragraph_grouping',
        ),
        isTrue,
      );
      expect(
        document.baseSpeechAnnotations.annotations.any(
          (annotation) => annotation.kind.name == 'pauseCandidate',
        ),
        isTrue,
      );
    });

    test(
      'speech annotations infer pronunciation candidates for acronyms and numerals',
      () {
        final service = DocumentImportService();
        final document = service.importPastedText('''
NASA launched 3 missions.
''');

        expect(
          document.baseSpeechAnnotations.annotations.any(
            (annotation) =>
                annotation.kind.name == 'pronunciationCandidate' &&
                annotation.pronunciationCandidate?.representationValue ==
                    'letters',
          ),
          isTrue,
        );
        expect(
          document.basePronunciationArtifacts.artifacts.any(
            (artifact) =>
                artifact.normalizedSurfaceText == 'missions' ||
                artifact.normalizedSurfaceText == 'launched',
          ),
          isTrue,
        );
        expect(
          document.baseSpeechAnnotations.annotations.any(
            (annotation) =>
                annotation.kind.name == 'pronunciationCandidate' &&
                annotation.pronunciationCandidate?.representationValue ==
                    'cardinal',
          ),
          isTrue,
        );
      },
    );

    test(
      'normalizes smart apostrophes and hidden break characters in pasted text',
      () {
        final service = DocumentImportService();
        final document = service.importPastedText(
          "Mara’s hand\u00ADed note used a zero\u200Bwidth separator.",
        );

        expect(document.speakableText, contains("Mara's handed note"));
        expect(document.speakableText, contains('zerowidth separator.'));
        expect(document.speakableText, isNot(contains('\u00AD')));
        expect(document.speakableText, isNot(contains('\u200B')));
        expect(
          document.basePronunciationArtifacts.artifacts.any(
            (artifact) => artifact.normalizedSurfaceText == 'handed',
          ),
          isTrue,
        );
      },
    );

    test('preserves quoted exclamations when splitting imported sentences', () {
      final service = DocumentImportService();
      final document = service.importPastedText(
        '“JUST STOP FIGHTING!” Jennifer screamed, pulling on her hair. '
        'To her surprise, they did.',
      );

      expect(document.speakableText, contains('JUST STOP FIGHTING'));
      expect(
        document.speechDocument.segments.any(
          (segment) => segment.normalizedText.contains('JUST STOP FIGHTING'),
        ),
        isTrue,
      );
    });

    test('preserves line-based dialogue turns as separate paragraphs', () {
      final service = DocumentImportService();
      final document = service.importPastedText('''
The room went quiet.
"JUST STOP FIGHTING!" Jennifer screamed.
To her surprise, they did.
''');

      final paragraphBlocks = document.displayDocument.blocks
          .where((block) => block.kind == DisplayBlockKind.paragraph)
          .toList(growable: false);

      expect(paragraphBlocks, hasLength(3));
      expect(paragraphBlocks[0].plainText, 'The room went quiet.');
      expect(
        paragraphBlocks[1].plainText,
        '"JUST STOP FIGHTING!" Jennifer screamed.',
      );
      expect(paragraphBlocks[2].plainText, 'To her surprise, they did.');
      expect(
        document.speakableText,
        'The room went quiet.\n\n"JUST STOP FIGHTING!" Jennifer screamed.\n\nTo her surprise, they did.',
      );
    });

    test(
      'epub import skips navigation documents and preserves spine order',
      () async {
        final service = DocumentImportService();
        final archive = Archive()
          ..addFile(
            ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml" />
  </rootfiles>
</container>
'''),
          )
          ..addFile(
            ArchiveFile.string('OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>EPUB Test</dc:title>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav" />
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml" />
    <item id="chapter2" href="chapter2.xhtml" media-type="application/xhtml+xml" />
  </manifest>
  <spine>
    <itemref idref="nav" />
    <itemref idref="chapter1" />
    <itemref idref="chapter2" />
  </spine>
</package>
'''),
          )
          ..addFile(
            ArchiveFile.string('OEBPS/nav.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <nav><ol><li>Contents</li></ol></nav>
  </body>
</html>
'''),
          )
          ..addFile(
            ArchiveFile.string('OEBPS/chapter1.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>Chapter One</h1><p>First chapter text.</p></body>
</html>
'''),
          )
          ..addFile(
            ArchiveFile.string('OEBPS/chapter2.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><p>Second chapter text.</p></body>
</html>
'''),
          );

        final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
        final document = await service.importBytes(
          fileName: 'book.epub',
          bytes: bytes,
        );

        expect(document.displayDocument.title, 'EPUB Test');
        expect(document.speakableText, isNot(contains('Contents')));
        expect(document.speakableText, contains('Chapter One'));
        expect(
          document.speakableText.indexOf('First chapter text.'),
          lessThan(document.speakableText.indexOf('Second chapter text.')),
        );
        expect(
          document.diagnostics.any(
            (diagnostic) => diagnostic.code == 'navigation_content_skipped',
          ),
          isTrue,
        );
      },
    );

    test(
      'pdf import preserves page-boundary blocks and extraction diagnostics',
      () async {
        final service = DocumentImportService(
          pdfTextExtractor: _FakePdfTextExtractor(
            result: const PdfTextExtractionResult(
              pages: [
                PdfTextExtractionPage(
                  pageIndex: 0,
                  fullText: 'Rosalina first page.\n\nSecond paragraph.',
                ),
                PdfTextExtractionPage(
                  pageIndex: 1,
                  fullText:
                      'short line\nanother short line\nthird short line\nfourth short line\nfifth short line\nsixth short line\nseventh short line\neighth short line\nninth short line\ntenth short line',
                ),
              ],
            ),
          ),
        );

        final document = await service.importBytes(
          fileName: 'Rosalina.pdf',
          bytes: Uint8List.fromList(utf8.encode('%PDF-fake')),
        );

        expect(document.type, ReaderDocumentType.pdf);
        expect(document.presentation, ReaderDocumentPresentation.pdf);
        expect(document.pdfData, isNotNull);
        expect(
          document.displayDocument.blocks.any(
            (block) => block.kind == DisplayBlockKind.pageBreak,
          ),
          isTrue,
        );
        expect(document.sourceDescription, contains('PDF import'));
        expect(document.speakableText, contains('Rosalina first page.'));
        expect(
          document.diagnostics.any(
            (diagnostic) => diagnostic.code == 'fallback_paragraph_grouping',
          ),
          isTrue,
        );
        expect(
          document.diagnostics.any(
            (diagnostic) => diagnostic.code == 'reading_order_suspect',
          ),
          isTrue,
        );
      },
    );

    test(
      'pdf import surfaces missing text-layer diagnostics without failing',
      () async {
        final service = DocumentImportService(
          pdfTextExtractor: _FakePdfTextExtractor(
            result: const PdfTextExtractionResult(
              pages: [PdfTextExtractionPage(pageIndex: 0, fullText: '')],
            ),
          ),
        );

        final document = await service.importBytes(
          fileName: 'image-only.pdf',
          bytes: Uint8List.fromList(utf8.encode('%PDF-fake')),
        );

        expect(document.type, ReaderDocumentType.pdf);
        expect(document.wordCount, 0);
        expect(
          document.diagnostics.any(
            (diagnostic) => diagnostic.code == 'missing_text_layer',
          ),
          isTrue,
        );
      },
    );

    test(
      'docx import preserves inline media as attachment placeholders',
      () async {
        final service = DocumentImportService();
        final archive = Archive()
          ..addFile(
            ArchiveFile.string('docProps/core.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:title>DOCX Test</dc:title>
</cp:coreProperties>
'''),
          )
          ..addFile(
            ArchiveFile.string('word/document.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
      <w:r><w:t>Imported Heading</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:drawing/></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Body paragraph.</w:t></w:r>
    </w:p>
  </w:body>
</w:document>
'''),
          );

        final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
        final document = await service.importBytes(
          fileName: 'media.docx',
          bytes: bytes,
        );

        expect(document.displayDocument.title, 'DOCX Test');
        expect(
          document.displayDocument.blocks.any(
            (block) =>
                block.kind == DisplayBlockKind.unsupported &&
                block.attributes['label'] == 'Inline DOCX media',
          ),
          isTrue,
        );
        expect(document.attachments, isNotEmpty);
        expect(
          document.diagnostics.any(
            (diagnostic) => diagnostic.code == 'lossy_conversion',
          ),
          isTrue,
        );
        expect(document.speakableText, contains('Imported Heading'));
        expect(document.speakableText, contains('Body paragraph.'));
      },
    );

    test(
      'unsupported file types remain explicit unsupported documents',
      () async {
        final service = DocumentImportService();
        final document = await service.importBytes(
          fileName: 'notes.xyz',
          bytes: Uint8List.fromList(utf8.encode('hello')),
        );

        expect(document.type, ReaderDocumentType.unsupported);
        expect(
          document.diagnostics.any(
            (diagnostic) => diagnostic.code == 'unsupported_structure',
          ),
          isTrue,
        );
      },
    );

    test('invalid pdf bytes throw a structured import failure', () async {
      final service = DocumentImportService(
        pdfTextExtractor: _FakePdfTextExtractor(
          error: const FormatException('bad pdf'),
        ),
      );

      await expectLater(
        service.importBytes(
          fileName: 'broken.pdf',
          bytes: Uint8List.fromList(utf8.encode('not a pdf')),
        ),
        throwsA(
          isA<DocumentImportException>().having(
            (error) => error.code,
            'code',
            'pdf_parse_failed',
          ),
        ),
      );
    });

    test(
      'epub missing container metadata throws a structured import failure',
      () async {
        final service = DocumentImportService();
        final archive = Archive()
          ..addFile(
            ArchiveFile.string('OEBPS/content.opf', '<package></package>'),
          );

        await expectLater(
          service.importBytes(
            fileName: 'broken.epub',
            bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
          ),
          throwsA(
            isA<DocumentImportException>().having(
              (error) => error.code,
              'code',
              'epub_missing_container',
            ),
          ),
        );
      },
    );

    test(
      'docx missing word document xml throws a structured import failure',
      () async {
        final service = DocumentImportService();
        final archive = Archive()
          ..addFile(
            ArchiveFile.string('docProps/core.xml', '<coreProperties />'),
          );

        await expectLater(
          service.importBytes(
            fileName: 'broken.docx',
            bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
          ),
          throwsA(
            isA<DocumentImportException>().having(
              (error) => error.code,
              'code',
              'docx_missing_document_xml',
            ),
          ),
        );
      },
    );

    test(
      'rtf import strips metadata noise and preserves paragraph breaks',
      () async {
        final service = DocumentImportService();
        final bytes = Uint8List.fromList(
          utf8.encode(r'''
{\rtf1\ansi
{\fonttbl{\f0 Times New Roman;}}
{\stylesheet{\s0 Normal;}{\s15 Title;}}
\pard\plain\b\fs36 Title\par
\pard\plain First paragraph line.\par
\pard\plain Second paragraph line.\par
}
'''),
        );

        final document = await service.importBytes(
          fileName: 'sample.rtf',
          bytes: bytes,
        );

        expect(document.speakableText, contains('Title'));
        expect(document.speakableText, contains('First paragraph line.'));
        expect(document.speakableText, contains('Second paragraph line.'));
        expect(document.speakableText, isNot(contains('Normal Table')));
        expect(document.speakableText, isNot(contains('Title;')));
        expect(
          document.diagnostics.any(
            (diagnostic) => diagnostic.code == 'lossy_conversion',
          ),
          isTrue,
        );
        expect(
          document.diagnostics.any(
            (diagnostic) => diagnostic.code == 'fallback_paragraph_grouping',
          ),
          isTrue,
        );
      },
    );

    test('real RTF sample strips bookmark and style-table metadata', () async {
      final service = DocumentImportService();
      final bytes = await File('project/testdocs/Vampire_.rtf').readAsBytes();

      final document = await service.importBytes(
        fileName: 'Vampire_.rtf',
        bytes: bytes,
      );

      expect(document.speakableText, contains('Vampire'));
      expect(
        document.speakableText,
        contains('Ah, Virginia, thanks for coming in.'),
      );
      expect(document.speakableText, isNot(contains('bkmkstart')));
      expect(document.speakableText, isNot(contains('bkmkend')));
      expect(document.speakableText, isNot(contains('7ulr2rfn1c3u')));
      expect(document.speakableText, isNot(contains('Times New Roman')));
      expect(document.speakableText, isNot(contains('Default Paragraph Font')));
    });
  });
}

class _FakePdfTextExtractor implements PdfTextExtractor {
  const _FakePdfTextExtractor({this.result, this.error});

  final PdfTextExtractionResult? result;
  final Object? error;

  @override
  Future<PdfTextExtractionResult> extract({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result ?? const PdfTextExtractionResult(pages: []);
  }
}
