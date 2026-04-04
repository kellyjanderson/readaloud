import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/display_document.dart';
import 'package:read_aloud/src/models/spoken_selection.dart';
import 'package:read_aloud/src/services/display_document_html_renderer.dart';

void main() {
  test('renders word precision with inline highlight markup', () {
    final html = renderDisplayDocumentToHtml(
      _document(),
      spokenSelection: const SpokenSelection(
        precision: SpokenSelectionPrecision.word,
        confidence: 1,
        displayBlockId: 'b_0',
        displayStart: 6,
        displayEnd: 11,
      ),
    );

    expect(html, contains('class="active-reading-block"'));
    expect(html, contains('<span class="spoken-word">world</span>'));
  });

  test('renders segment precision with segment highlight markup', () {
    final html = renderDisplayDocumentToHtml(
      _document(),
      spokenSelection: const SpokenSelection(
        precision: SpokenSelectionPrecision.segment,
        confidence: 1,
        displayBlockId: 'b_0',
        displayStart: 0,
        displayEnd: 11,
      ),
    );

    expect(html, contains('class="active-reading-block"'));
    expect(
      html,
      contains('<span class="spoken-segment">Hello world</span>'),
    );
  });

  test('renders block precision with block highlight and no inline span', () {
    final html = renderDisplayDocumentToHtml(
      _document(),
      spokenSelection: const SpokenSelection(
        precision: SpokenSelectionPrecision.block,
        confidence: 1,
        displayBlockId: 'b_0',
      ),
    );

    expect(html, contains('class="active-reading-block spoken-block"'));
    expect(html, isNot(contains('spoken-word')));
    expect(html, isNot(contains('spoken-segment')));
  });
}

DisplayDocument _document() {
  return const DisplayDocument(
    documentId: 'doc_1',
    sourceType: 'sample',
    sourceUri: null,
    title: 'Doc',
    normalizationVersion: 'v1',
    metadata: <String, String>{},
    assets: <String, DisplayAsset>{},
    blocks: <DisplayBlock>[
      DisplayBlock(
        blockId: 'b_0',
        kind: DisplayBlockKind.paragraph,
        inlines: <DisplayInline>[
          DisplayInline(
            kind: DisplayInlineKind.text,
            text: 'Hello world',
            attributes: <String, String>{},
          ),
        ],
        attributes: <String, String>{},
        assetId: null,
        parentBlockId: null,
        ordinal: 0,
      ),
    ],
  );
}
