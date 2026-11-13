import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/document_import_exception.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/services/document_import_service.dart';

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  for (final file in files.entries) {
    archive.addFile(ArchiveFile.string(file.key, file.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, String> _epub({String? chapter, String extraSpine = ''}) => {
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
  'OPS/book.opf':
      '<package xmlns:dc="urn:dc"><metadata><dc:title>Étoile 🌟</dc:title></metadata>'
      '<manifest><item id="nav" href="nav.xhtml" properties="nav"/>'
      '<item id="one" href="one.xhtml"/><item id="absent" href="absent.xhtml"/></manifest>'
      '<spine><itemref idref="nav"/><itemref idref="one"/>$extraSpine</spine></package>',
  'OPS/one.xhtml':
      chapter ??
      '<h1>Étoile 🌟</h1><p>First &amp; second.</p><img src="art.svg" alt="Art"/>',
  'OPS/art.svg': '<svg xmlns="http://www.w3.org/2000/svg"/>',
};

void main() {
  for (final format in ['docx', 'epub']) {
    test(
      '$format collector and worker units preserve metadata, structure and mapping',
      () async {
        final bytes = format == 'docx'
            ? _zip({
                'docProps/core.xml':
                    '<core xmlns:dc="urn:dc"><dc:title>Étoile 🌟</dc:title></core>',
                'word/document.xml':
                    '<w:document xmlns:w="urn:w"><w:body>'
                    '<w:p><w:pPr><w:pStyle w:val="Heading4"/></w:pPr><w:r><w:t>Étoile 🌟</w:t></w:r></w:p>'
                    '<w:p><w:r><w:t>First &amp; second.</w:t><w:drawing/></w:r></w:p>'
                    '</w:body></w:document>',
              })
            : _zip(_epub());
        final service = DocumentImportService();
        final units = await service
            .streamUnits(fileName: 'book.$format', bytes: bytes)
            .toList();
        final whole = await service.importBytes(
          fileName: 'book.$format',
          bytes: bytes,
        );
        final fragments = <ReaderDocument>[];
        var offset = 0;
        for (final unit in units) {
          fragments.add(
            service.importTextFragment(
              text: unit.text,
              title: 'book.$format',
              sessionId: format,
              sourceStart: offset,
              unit: unit,
            ),
          );
          offset += unit.text.length;
        }
        expect(whole.title, 'Étoile 🌟');
        expect(fragments.map((f) => f.title).toSet(), {'Étoile 🌟'});
        expect(units.every((u) => u.locator != null), isTrue);
        expect(
          fragments
              .expand((f) => f.displayDocument.blocks)
              .map((b) => (b.kind, b.plainText)),
          whole.displayDocument.blocks.map((b) => (b.kind, b.plainText)),
        );
        expect(
          fragments
              .expand((f) => f.speechDocument.segments)
              .map((s) => s.normalizedText),
          whole.speechDocument.segments.map((s) => s.normalizedText),
        );
        expect(
          fragments
              .expand((f) => f.attachments)
              .map((a) => (a.label, a.source)),
          whole.attachments.map((a) => (a.label, a.source)),
        );
        expect(
          fragments.expand((f) => f.diagnostics).map((d) => d.code),
          whole.diagnostics.map((d) => d.code),
        );
        for (final fragment in fragments) {
          for (final entry in fragment.positionMap.entries) {
            final block = fragment.displayDocument.blocks.firstWhere(
              (b) => b.blockId == entry.displayBlockId,
            );
            final segment = fragment.speechDocument.segments.firstWhere(
              (s) => s.segmentId == entry.speechSegmentId,
            );
            expect(
              block.plainText.substring(entry.displayStart, entry.displayEnd),
              segment.normalizedText,
            );
          }
        }
        expect(whole.attachments, hasLength(1));
      },
    );
  }

  test(
    'EPUB missing spine member is a visible degraded success in both APIs',
    () async {
      final bytes = _zip(_epub(extraSpine: '<itemref idref="absent"/>'));
      final service = DocumentImportService();
      final units = await service
          .streamUnits(fileName: 'book.epub', bytes: bytes)
          .toList();
      final whole = await service.importBytes(
        fileName: 'book.epub',
        bytes: bytes,
      );
      expect(whole.speakableText, contains('First & second.'));
      expect(
        whole.diagnostics
            .where((d) => d.code == 'missing_asset')
            .map((d) => d.sourceLocator),
        contains('OPS/absent.xhtml'),
      );
      expect(
        units
            .expand((u) => u.diagnostics)
            .where((d) => d.code == 'missing_asset')
            .map((d) => d.sourceLocator),
        contains('OPS/absent.xhtml'),
      );
    },
  );

  for (final format in ['docx', 'epub']) {
    test(
      '$format required-member failure is typed for whole and streaming APIs',
      () async {
        final bytes = _zip({'unrelated': 'nothing'});
        final service = DocumentImportService();
        final code = format == 'docx'
            ? 'docx_missing_document_xml'
            : 'epub_missing_container';
        final error = isA<DocumentImportException>().having(
          (e) => e.code,
          'code',
          code,
        );
        await expectLater(
          service.streamUnits(fileName: 'bad.$format', bytes: bytes).toList(),
          throwsA(error),
        );
        await expectLater(
          service.importBytes(fileName: 'bad.$format', bytes: bytes),
          throwsA(error),
        );
      },
    );
  }

  test(
    'DOCX publishes bounded paragraphs before malformed tail is reached',
    () async {
      final body = List.filled(
        2000,
        '<w:p><w:r><w:t>Available 🌟 now.</w:t></w:r></w:p>',
      ).join();
      final bytes = _zip({
        'word/document.xml': '<w:document xmlns:w="urn:w"><w:body>$body</bad>',
      });
      final service = DocumentImportService();
      final first = await service
          .streamUnits(fileName: 'late.docx', bytes: bytes)
          .first;
      expect(first.text, 'Available 🌟 now.');
      await expectLater(
        service.importBytes(fileName: 'late.docx', bytes: bytes),
        throwsA(
          isA<DocumentImportException>().having(
            (e) => e.code,
            'code',
            'docx_parse_failed',
          ),
        ),
      );
    },
  );

  test('DOCX giant text event keeps Unicode intact and units bounded', () async {
    final text = List.filled(20000, '🌟').join();
    final bytes = _zip({
      'word/document.xml':
          '<w:document xmlns:w="urn:w"><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:document>',
    });
    final units = await DocumentImportService()
        .streamUnits(fileName: 'long.docx', bytes: bytes)
        .toList();
    expect(units.map((u) => u.text).join(), text);
    expect(units.every((u) => u.text.length <= 8192), isTrue);
    expect(
      units.every((u) => utf8.decode(utf8.encode(u.text)) == u.text),
      isTrue,
    );
  });
}
