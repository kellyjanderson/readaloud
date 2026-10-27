import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';
import 'package:read_aloud/src/services/reader_document_codec.dart';

void main() {
  group('ReaderDocumentSerializationService', () {
    const serializationService = ReaderDocumentSerializationService();

    test(
      'optional voice overrides round trip and malformed data fails closed',
      () {
        final document = DocumentImportService().importPastedText(
          'John said, "Hello." He smiled.',
        );
        final serialized = serializationService.serializeToJsonString(
          document,
          userVoiceAssignments: {'cast_narrator': 'am_michael'},
        );
        final restored = decodeReaderDocumentWithPreferences(serialized);
        expect(restored.userVoiceAssignments, {'cast_narrator': 'am_michael'});
        expect(
          decodeReaderDocumentWithPreferences(
            serializationService.serializeToJsonString(document),
          ).userVoiceAssignments,
          isEmpty,
        );
        final m = jsonDecode(serialized) as Map<String, dynamic>;
        for (final malformed in [
          null,
          [],
          {'unknown_cast': 'am_michael'},
          {'cast_narrator': ''},
          {'cast_narrator': 42},
        ]) {
          m['userVoiceAssignments'] = malformed;
          expect(
            () => serializationService.deserializeFromJsonString(jsonEncode(m)),
            throwsFormatException,
          );
        }
      },
    );

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
      expect(
        decoded['formatVersion'],
        ReaderDocumentSerializationService.formatVersion,
      );
      expect(
        (decoded['speechDocument'] as Map<String, dynamic>)['segments'],
        isA<List<dynamic>>(),
      );
    });

    test(
      'cancellation after staging keeps the destination and removes temporary output',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'radoc-cancel-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final output = await File(
          '${directory.path}/book.radoc',
        ).writeAsString('prior export');
        final document = DocumentImportService().importPastedText(
          'A complete sentence.',
        );
        var checks = 0;
        await expectLater(
          serializationService.writeToFile(
            document: document,
            outputPath: output.path,
            isCurrent: () => ++checks < 2,
          ),
          throwsStateError,
        );
        expect(await output.readAsString(), 'prior export');
        expect((await directory.list().toList()).map((f) => f.path), [
          output.path,
        ]);
      },
    );
  });
}
