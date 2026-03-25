import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

enum ReaderDocumentType { sample, plainText, html, epub, pdf, unsupported }

enum ReaderAttachmentType { image, audio, video, other }

enum ReaderDocumentPresentation { html, pdf }

class ReaderAttachment {
  const ReaderAttachment({
    required this.label,
    required this.type,
    this.source,
  });

  final String label;
  final ReaderAttachmentType type;
  final String? source;
}

class WordSpan {
  const WordSpan({required this.start, required this.end});

  final int start;
  final int end;
}

class ReaderDocument {
  ReaderDocument({
    required this.title,
    required this.type,
    required this.displayHtml,
    required this.speakableText,
    this.presentation = ReaderDocumentPresentation.html,
    this.pdfData,
    this.sourceDescription,
    this.attachments = const <ReaderAttachment>[],
  }) : assert(
         presentation != ReaderDocumentPresentation.pdf || pdfData != null,
         'PDF presentation requires pdfData.',
       ),
       wordSpans = _buildWordSpans(speakableText);

  final String title;
  final ReaderDocumentType type;
  final String displayHtml;
  final String speakableText;
  final ReaderDocumentPresentation presentation;
  final Uint8List? pdfData;
  final String? sourceDescription;
  final List<ReaderAttachment> attachments;
  final List<WordSpan> wordSpans;

  int get wordCount => wordSpans.length;

  int charOffsetForWord(int wordIndex) {
    if (wordSpans.isEmpty) return 0;
    final clamped = wordIndex.clamp(0, wordSpans.length - 1);
    return wordSpans[clamped].start;
  }

  int wordIndexForOffset(int offset) {
    if (wordSpans.isEmpty) return 0;
    var low = 0;
    var high = wordSpans.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final span = wordSpans[mid];
      if (offset < span.start) {
        high = mid - 1;
      } else if (offset > span.end) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return math.max(0, math.min(low, wordSpans.length - 1));
  }

  static ReaderDocument sample() {
    const body = '''
<article>
  <h1>Read Aloud</h1>
  <p>
    This is the first build shell for Read Aloud. It is structured around a rich document surface
    instead of a plain text widget, so the app can grow into EPUB, PDF, and mixed-media documents
    without starting over.
  </p>
  <p>
    The reading view is HTML-based for now. That gives us styled text, headings, lists, images, and
    custom placeholders for embedded media while the importer and playback layers mature.
  </p>
  <img alt="A decorative shelf of books." src="data:image/svg+xml;utf8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='960' height='280' viewBox='0 0 960 280'%3E%3Crect width='960' height='280' rx='32' fill='%23E9D8A6'/%3E%3Crect x='72' y='58' width='76' height='156' rx='10' fill='%23005F73'/%3E%3Crect x='166' y='42' width='92' height='172' rx='10' fill='%23AE2012'/%3E%3Crect x='276' y='76' width='68' height='138' rx='10' fill='%23CA6702'/%3E%3Crect x='362' y='52' width='84' height='162' rx='10' fill='%239B2226'/%3E%3Crect x='464' y='90' width='64' height='124' rx='10' fill='%230A9396'/%3E%3Crect x='546' y='38' width='98' height='176' rx='10' fill='%23BB3E03'/%3E%3Crect x='662' y='62' width='78' height='152' rx='10' fill='%2300564D'/%3E%3Crect x='758' y='80' width='74' height='134' rx='10' fill='%23B56576'/%3E%3Crect x='850' y='48' width='56' height='166' rx='10' fill='%236A994E'/%3E%3Crect x='52' y='214' width='856' height='18' rx='9' fill='%231F2933' fill-opacity='0.15'/%3E%3C/svg%3E" />
  <p>
    The playback model tracks observed timing as words are spoken. That timing estimate is then used
    to approximate thirty-second jumps through the text instead of relying on a blind fixed offset.
  </p>
  <h2>Embedded Context</h2>
  <p>
    Audio, video, and other embedded content are modeled as first-class content, even before the app
    starts doing anything intelligent with them.
  </p>
  <audio controls src="sample-audio.mp3"></audio>
  <video controls src="sample-video.mp4" poster="sample-poster.png"></video>
</article>
''';

    const speakable = '''
Read Aloud is the first build shell for a cross-platform document reader. The reading view is
structured for rich content instead of plain text. The playback model tracks observed timing while
text is spoken and uses that timing to approximate thirty-second jumps. Audio, video, and other
embedded content are treated as first-class content so the app can grow without a major rewrite.
''';

    return ReaderDocument(
      title: 'Sample Document',
      type: ReaderDocumentType.sample,
      displayHtml: body,
      speakableText: speakable,
      sourceDescription: 'Bundled project sample',
      attachments: const [
        ReaderAttachment(
          label: 'Sample inline illustration',
          type: ReaderAttachmentType.image,
        ),
        ReaderAttachment(
          label: 'Embedded audio placeholder',
          type: ReaderAttachmentType.audio,
        ),
        ReaderAttachment(
          label: 'Embedded video placeholder',
          type: ReaderAttachmentType.video,
        ),
      ],
    );
  }
}

List<WordSpan> _buildWordSpans(String text) {
  final matches = RegExp(r'\S+').allMatches(text);
  return matches
      .map((match) => WordSpan(start: match.start, end: match.end))
      .toList(growable: false);
}

String plainTextToHtml(String text) {
  final paragraphs = text
      .trim()
      .split(RegExp(r'\n\s*\n'))
      .map((block) => block.trim())
      .where((block) => block.isNotEmpty)
      .map(
        (block) =>
            '<p>${const HtmlEscape().convert(block).replaceAll('\n', '<br />')}</p>',
      )
      .join('\n');

  return '<article>$paragraphs</article>';
}
