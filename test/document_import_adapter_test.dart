import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/document_import_exception.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/document_preparation_supervisor.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  test('valid empty DOCX retains metadata without inventing speech', () async {
    final bytes = _zip({
      'docProps/core.xml': '<core><title>Empty title</title></core>',
      'word/document.xml': '<document><body/></document>',
    });
    final document = await DocumentImportService().importBytes(
      fileName: 'empty.docx',
      bytes: bytes,
    );
    expect(document.title, 'Empty title');
    expect(document.speechDocument.segments, isEmpty);
  });
  test(
    'heuristic mapping fallback retains bounded offsets and recovery evidence',
    () {
      final fragment = DocumentImportService().importTextFragment(
        text:
            'A much longer recovered sentence. Followed by a second sentence.',
        title: 'Recovered',
        sessionId: 'mapping',
        sourceStart: 0,
        unit: const DocumentImportUnit(
          text:
              'A much longer recovered sentence. Followed by a second sentence.',
          html: '<p>Short.</p>',
        ),
      );
      expect(fragment.positionMap.entries, hasLength(2));
      for (final entry in fragment.positionMap.entries) {
        final block = fragment.displayDocument.blocks.firstWhere(
          (b) => b.blockId == entry.displayBlockId,
        );
        expect(entry.displayStart, inInclusiveRange(0, block.plainText.length));
        expect(
          entry.displayEnd,
          inInclusiveRange(entry.displayStart, block.plainText.length),
        );
        expect(entry.confidence, lessThanOrEqualTo(0.55));
        expect(entry.recoveryAnchor!.exact, isNotEmpty);
      }
    },
  );
  test(
    'HTML structure-only input publishes before EOF and cancellation stops acquisition',
    () async {
      final bytes = Uint8List.fromList(
        utf8.encode(List.filled(20000, '<img src="art.png"><hr>').join()),
      );
      var acquired = 0;
      var eof = false;
      final first = await DocumentImportService()
          .streamUnits(
            fileName: 'images.html',
            bytes: bytes,
            onAcquiredBytes: (chunk) => acquired += chunk.length,
            onAcquiredEof: () => eof = true,
          )
          .first;
      expect(first.html, contains('art.png'));
      expect(first.text.trim(), isEmpty);
      expect(
        first.text.length,
        greaterThan(0),
        reason: 'Structural ranges must advance identity coordinates.',
      );
      expect(eof, isFalse);
      expect(acquired, lessThan(bytes.length ~/ 10));
    },
  );

  for (final xml in ['', '<one/><two/>', '<one>']) {
    test(
      'DOCX refuses malformed XML document $xml in both entry paths',
      () async {
        final bytes = _zip({'word/document.xml': xml});
        final service = DocumentImportService();
        final error = isA<DocumentImportException>().having(
          (e) => e.code,
          'code',
          'docx_parse_failed',
        );
        await expectLater(
          service.streamUnits(fileName: 'invalid.docx', bytes: bytes).toList(),
          throwsA(error),
        );
        await expectLater(
          service.importBytes(fileName: 'invalid.docx', bytes: bytes),
          throwsA(error),
        );
      },
    );
  }

  test(
    'worker preserves archive metadata and unique ranges around image-only paragraphs',
    () async {
      final bytes = _zip({
        'docProps/core.xml': '<core><title>Worker title</title></core>',
        'word/document.xml':
            '<w:document xmlns:w="urn:w"><w:body>'
            '<w:p><w:r><w:drawing/></w:r></w:p>'
            '<w:p><w:r><w:t>Readable words.</w:t></w:r></w:p>'
            '</w:body></w:document>',
      });
      final supervisor = DocumentPreparationSupervisor();
      addTearDown(supervisor.shutdown);
      final publications = <DocumentPreparationPublication>[];
      final result = await supervisor.prepareRanges(
        DocumentPreparationRequest(
          ownerId: 'adapters',
          revision: 41,
          kind: DocumentPreparationKind.bytes,
          fileName: 'media.docx',
          bytes: bytes,
        ),
        onPublication: (publication) async => publications.add(publication),
      );
      expect(
        result.outcome,
        DocumentPreparationOutcome.ready,
        reason: result.error,
      );
      expect(publications, hasLength(2));
      expect(publications.map((p) => p.fragment.title).toSet(), {
        'Worker title',
      });
      expect(publications.first.fragment.attachments, hasLength(1));
      expect(
        publications.last.range.sourceStart,
        publications.first.range.sourceEnd,
      );
      final ids = publications
          .expand((p) => p.fragment.displayDocument.blocks)
          .map((b) => b.blockId)
          .toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(
        publications.every((p) => p.request.operationId == 'adapters:41'),
        isTrue,
      );
    },
  );

  test(
    'archive member CRC failure is typed and cannot report complete success',
    () async {
      const xml =
          '<w:document xmlns:w="urn:w"><w:p><w:r><w:t>Available now.</w:t></w:r></w:p></w:document>';
      final source = utf8.encode(xml);
      final archive = Archive()
        ..addFile(
          ArchiveFile.noCompress('word/document.xml', source.length, source),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final target = utf8.encode('Available');
      var changed = false;
      for (var i = 0; i <= bytes.length - target.length; i++) {
        if (List.generate(
          target.length,
          (n) => bytes[i + n] == target[n],
        ).every((value) => value)) {
          bytes[i] = 'X'.codeUnitAt(0);
          changed = true;
          break;
        }
      }
      expect(changed, isTrue);
      final service = DocumentImportService();
      final error = isA<DocumentImportException>().having(
        (e) => e.code,
        'code',
        'docx_parse_failed',
      );
      await expectLater(
        service.streamUnits(fileName: 'crc.docx', bytes: bytes).toList(),
        throwsA(error),
      );
      await expectLater(
        service.importBytes(fileName: 'crc.docx', bytes: bytes),
        throwsA(error),
      );
    },
  );

  for (final format in ['txt', 'md', 'html']) {
    test(
      '$format whole-file collection matches incremental display/speech policy',
      () async {
        final source = format == 'html'
            ? '<html><head><title>Hidden</title></head><body>'
                  '<h2>Heading 🌟</h2><ul><li>First &amp; second.</li><li>Third.</li></ul>'
                  '<p hidden>Not visible.</p><figure><img src="cover.png" alt="Cover">'
                  '<figcaption>Caption.</figcaption></figure><hr><nav>Not spoken.<nav>Nested navigation.</nav>Still not spoken.</nav></body></html>'
            : '# Heading 🌟\n\n- First & second.\n- Third.\n\nWrapped para-\ngraph.\n';
        final service = DocumentImportService();
        final bytes = Uint8List.fromList(utf8.encode(source));
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
          fragments.expand((f) => f.diagnostics).map((d) => d.code),
          whole.diagnostics.map((d) => d.code),
        );
        expect(whole.speakableText, isNot(contains('Not visible')));
        expect(whole.speakableText, isNot(contains('Not spoken')));
        expect(whole.speakableText, isNot(contains('Still not spoken')));
        if (format != 'html') {
          expect(whole.speakableText, contains('paragraph.'));
        }
      },
    );
  }

  test(
    'HTML split tags, entities and UTF8 keep structural-only EOF content',
    () async {
      // Each byte adapter chunk is 8192 bytes. Put a tag and entity across those
      // acquisition boundaries and a surrogate pair across a 4096-code-unit cut.
      final source =
          '<p>${'a' * 4070}🌟${'b' * 4090}&amp; ending.</p>'
          '<img alt="${'x' * 100}" src="cover.png"><hr><nav>Only navigation.</nav>';
      final bytes = Uint8List.fromList(utf8.encode(source));
      final service = DocumentImportService();
      final whole = await service.importBytes(
        fileName: 'split.html',
        bytes: bytes,
      );
      final units = await service
          .streamUnits(fileName: 'split.html', bytes: bytes)
          .toList();
      expect(units.map((u) => u.text).join(' '), contains('🌟'));
      expect(whole.speakableText, contains('& ending.'));
      expect(whole.speakableText, isNot(contains('\uFFFD')));
      expect(whole.displayHtml, contains('cover.png'));
      expect(whole.displayHtml, contains('<hr '));
      expect(
        whole.diagnostics.where((d) => d.code == 'navigation_content_skipped'),
        hasLength(1),
      );
    },
  );

  test(
    'plain source modes share recovery and retain distinct provenance',
    () async {
      const source = '# Heading\n\nA wrapped para-\ngraph.\n\n- A list item.';
      final service = DocumentImportService();
      final pasted = service.importPastedText(source);
      final shared = service.importSharedText(source);
      final file = await service.importBytes(
        fileName: 'source.txt',
        bytes: Uint8List.fromList(utf8.encode(source)),
      );
      expect(pasted.speakableText, shared.speakableText);
      expect(pasted.speakableText, file.speakableText);
      expect({
        pasted.normalizedImportResult.sourceFingerprint,
        shared.normalizedImportResult.sourceFingerprint,
        file.normalizedImportResult.sourceFingerprint,
      }, hasLength(3));
      expect(pasted.title, 'Pasted Text');
      expect(shared.title, 'Shared Text');
      expect(file.title, 'source.txt');
    },
  );

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
