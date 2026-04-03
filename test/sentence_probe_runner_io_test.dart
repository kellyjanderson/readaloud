import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/services/sentence_probe_runner_io.dart';

void main() {
  group('sentenceProbeCasesFromDocument', () {
    test('builds ordered sentence cases from the speech document', () {
      final document = ReaderDocument.sample();

      final cases = sentenceProbeCasesFromDocument(document);

      expect(cases, isNotEmpty);
      expect(cases.first.id, 'sentence_1');
      expect(cases.first.segmentId, 's_0');
      expect(cases.first.ordinal, 0);
      expect(cases.first.text, contains('Short phrases for tracing'));
      expect(cases.last.text, 'for now.');
    });
  });
}
