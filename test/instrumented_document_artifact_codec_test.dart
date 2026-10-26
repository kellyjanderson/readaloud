import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/instrumented_document_artifact_codec.dart';

void main() {
  const codec = InstrumentedDocumentArtifactCodec();
  final document = DocumentImportService().importPastedText(
    'Mara said, "Read the record carefully." Then she paused.',
  );
  final id = document.normalizedImportResult.documentId;
  final assignment = <String, Object?>{
    'castId': 'cast_character_mara',
    'effectiveVoiceId': 'af_bella',
    'decisionKind': 'userOverride',
    'automaticVoiceId': 'af_sarah',
    'storedVoiceId': null,
    'userOverrideVoiceId': 'af_bella',
    'provenance': {'source': 'user', 'revision': 4},
  };
  final reference = <String, Object?>{
    'documentId': id,
    'documentRevision': 12,
    'castId': 'cast_character_mara',
    'resource': {
      'voiceId': 'af_bella',
      'voiceDigest': 'voice-sha256',
      'modelDigest': 'model-sha256',
      'engineVersion': 'kokoro-test',
      'pronunciationProfileId': 'en-us-core',
      'bindingRevision': 3,
      'documentId': id,
    },
  };

  test('round trips imported instrumented document and binding data', () {
    final first = codec.encode(
      document: document,
      documentRevision: 12,
      castVoiceAssignments: [assignment],
      preparedVoiceReferences: [reference],
    );
    final snapshot = codec.decode(first);
    final second = codec.reencode(snapshot);
    expect(jsonDecode(second), jsonDecode(first));
    expect(snapshot.documentId, id);
    expect(first, contains('sourceFingerprint'));
    expect(first, contains('positionMap'));
    expect(first, contains('baseSpeechAnnotations'));
    expect(first, contains('basePronunciationArtifacts'));
    expect(first, isNot(contains('pdfDataBase64')));
    expect(() => (snapshot.data['preparedDocument'] as Map).clear(), throwsUnsupportedError);
  });

  test('rejects wrong version, inconsistent identity, and malformed references', () {
    final encoded = jsonDecode(codec.encode(document: document, documentRevision: 12,
      castVoiceAssignments: [assignment], preparedVoiceReferences: [reference])) as Map<String, dynamic>;
    final wrongVersion = Map<String, dynamic>.of(encoded)..['formatVersion'] = 'radoc-v1';
    expect(() => codec.decode(jsonEncode(wrongVersion)), throwsFormatException);
    final wrongIdentity = jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
    wrongIdentity['documentId'] = 'other';
    expect(() => codec.decode(jsonEncode(wrongIdentity)), throwsFormatException);
    final wrongRevision = jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
    (wrongRevision['preparedVoiceReferences'] as List)[0]['documentRevision'] = 11;
    expect(() => codec.decode(jsonEncode(wrongRevision)), throwsFormatException);
    expect(() => codec.decode('{"formatId":'), throwsFormatException);
  });
}
