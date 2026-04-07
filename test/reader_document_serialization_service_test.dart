import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';

void main() {
  group('ReaderDocumentSerializationService', () {
    const serializationService = ReaderDocumentSerializationService();

    test('serializes imported reader documents to human-readable radoc json', () {
      final importService = DocumentImportService();
      final document = importService.importPastedText(
        '"JUST STOP FIGHTING!" Jennifer screamed, pulling on her hair.\n\n'
        '"John, why did you have to budge in front of me this morning?" Elliot said '
        '"I dunno. I thought taking someone\'s position in line is how we operate now," '
        'John replied sarcastically.',
      );

      final serialized = serializationService.serializeToJsonString(document);
      final decoded = jsonDecode(serialized) as Map<String, dynamic>;

      expect(serialized, contains('\n  "formatId"'));
      expect(decoded['formatId'], ReaderDocumentSerializationService.formatId);
      expect(
        decoded['formatVersion'],
        ReaderDocumentSerializationService.formatVersion,
      );
      expect(decoded['title'], 'Pasted Text');
      expect(decoded['documentType'], 'plainText');

      final characterCastRegistry =
          decoded['characterCastRegistry'] as Map<String, dynamic>;
      final castEntries = characterCastRegistry['entries'] as List<dynamic>;
      expect(
        castEntries.any(
          (entry) =>
              (entry as Map<String, dynamic>)['displayLabel'] == 'Jennifer',
        ),
        isTrue,
      );
      final jenniferEntry = castEntries.cast<Map<String, dynamic>>().firstWhere(
        (entry) => entry['displayLabel'] == 'Jennifer',
      );
      expect(jenniferEntry['identityProfile'], isA<Map<String, dynamic>>());
      final identityProfile =
          jenniferEntry['identityProfile'] as Map<String, dynamic>;
      expect(identityProfile['genderIdentityLabel'], isA<String>());
      expect(identityProfile['pronounProfile'], isA<Map<String, dynamic>>());
      expect(identityProfile['evidenceSpans'], isA<List<dynamic>>());

      final voiceAttribution =
          decoded['documentVoiceAttribution'] as Map<String, dynamic>;
      final ranges = voiceAttribution['ranges'] as List<dynamic>;
      expect(
        ranges.any(
          (entry) =>
              (entry as Map<String, dynamic>)['castId'] ==
                  'cast_character_jennifer' &&
              entry['kind'] == 'attributedDialogue',
        ),
        isTrue,
      );
    });

    test('writes serialized documents with the project file extension', () async {
      final importService = DocumentImportService();
      final document = importService.importPastedText(
        'John said, "Are you ok?" She waited.',
      );
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-radoc-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final outputPath =
          '${tempDir.path}/sample${ReaderDocumentSerializationService.fileExtension}';
      final file = await serializationService.writeToFile(
        document: document,
        outputPath: outputPath,
      );

      expect(file.path, endsWith('.radoc'));
      expect(await file.exists(), isTrue);

      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(decoded['formatVersion'], 'radoc-v1');
      expect(
        (decoded['speechDocument'] as Map<String, dynamic>)['segments'],
        isA<List<dynamic>>(),
      );
    });
  });
}
