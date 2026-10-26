import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_voice_assignment.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/instrumented_document_artifact_codec.dart';
import 'package:read_aloud/src/services/prepared_document_snapshot.dart';

void main() {
  const codec = InstrumentedDocumentArtifactCodec();
  final imported = DocumentImportService().importPastedText(
    'Mara said, "Read the record carefully." Then she paused.',
  );
  final document = freezePreparedDocument(imported);
  final id = document.normalizedImportResult.documentId;
  final mara = document.characterCastRegistry.entries.firstWhere(
    (entry) => entry.displayLabel == 'Mara',
  );
  final assignment = CastVoiceAssignment(
    castId: mara.castId,
    effectiveVoiceId: 'af_bella',
    decisionKind: VoiceAssignmentDecisionKind.userOverride,
    automaticVoiceId: 'af_sarah',
    userOverrideVoiceId: 'af_bella',
  );
  final assignmentSet = CastVoiceAssignmentSet(
    documentId: id,
    assignmentVersion: 'assignment-v1',
    assignments: [assignment],
  );
  final reference = ResolvedPreparedVoiceReference(
    assignment: assignment,
    resource: PreparedVoiceBinding(
      voiceId: 'af_bella',
      voiceDigest: 'voice-sha256',
      modelDigest: 'model-sha256',
      engineVersion: 'kokoro-test',
      pronunciationProfileId: 'en-us-core',
      bindingRevision: 3,
      documentId: id,
    ),
    documentRevision: 12,
  );

  test('round trips imported instrumented document and binding data', () {
    final first = codec.encode(
      document: document,
      documentRevision: 12,
      castVoiceAssignments: assignmentSet,
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
    final firstJson = jsonDecode(first) as Map<String, dynamic>;
    final prepared = firstJson['preparedDocument'] as Map<String, dynamic>;
    final annotations =
        prepared['baseSpeechAnnotations'] as Map<String, dynamic>;
    final annotationList = annotations['annotations'] as List<dynamic>;
    expect(annotationList, isNotEmpty);
    for (final raw in annotationList) {
      final annotation = raw as Map<String, dynamic>;
      expect(annotation['startWord'], isA<int>());
      expect(annotation['endWord'], isA<int>());
      expect(annotation['kind'], isA<String>());
      expect(annotation, contains('breakClass'));
      expect(annotation, contains('pronunciationCandidate'));
      expect(annotation, contains('sayAsClass'));
    }
    final attribution =
        prepared['dialogueAttributions'] as Map<String, dynamic>;
    expect(attribution['outcomes'], isNotEmpty);
    expect(attribution['outcomes'], everyElement(contains('resolution')));
    expect(attribution['outcomes'], everyElement(contains('provenance')));
    expect(attribution['outcomes'], everyElement(contains('evidenceSpan')));
    final castRegistry =
        prepared['characterCastRegistry'] as Map<String, dynamic>;
    final maraEntry = (castRegistry['entries'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((entry) => entry['castId'] == mara.castId);
    expect(maraEntry['provenance'], isNotEmpty);
    final identity = maraEntry['identityProfile'] as Map<String, dynamic>;
    expect(identity['conflictFlag'], isA<bool>());
    expect(identity['evidenceSpans'], isA<List<dynamic>>());
    final positionMap = prepared['positionMap'] as Map<String, dynamic>;
    expect(positionMap['entries'], isNotEmpty);
    for (final raw in positionMap['entries'] as List<dynamic>) {
      final entry = raw as Map<String, dynamic>;
      expect(entry['displayBlockId'], isA<String>());
      expect(entry['speechSegmentId'], isA<String>());
      expect(entry, contains('sourceAnchor'));
      expect(entry, contains('recoveryAnchor'));
    }
    final pronunciation =
        prepared['basePronunciationArtifacts'] as Map<String, dynamic>;
    expect(pronunciation['artifacts'], isA<List<dynamic>>());
    expect(pronunciation['pronunciationProfileId'], isNotEmpty);
    final artifactAssignments =
        firstJson['castVoiceAssignments'] as Map<String, dynamic>;
    final assignmentRecord =
        (artifactAssignments['assignments'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(assignmentRecord['decisionKind'], 'userOverride');
    final artifactReferences =
        firstJson['preparedVoiceReferences'] as List<dynamic>;
    final referenceRecord = artifactReferences.single as Map<String, dynamic>;
    expect(referenceRecord['documentRevision'], 12);
    expect(referenceRecord['resource']['bindingRevision'], 3);
    expect(referenceRecord['castId'], mara.castId);
    expect(
      () => (snapshot.data['preparedDocument'] as Map).clear(),
      throwsUnsupportedError,
    );
  });

  test(
    'rejects wrong version, inconsistent identity, and malformed references',
    () {
      final encoded =
          jsonDecode(
                codec.encode(
                  document: document,
                  documentRevision: 12,
                  castVoiceAssignments: assignmentSet,
                  preparedVoiceReferences: [reference],
                ),
              )
              as Map<String, dynamic>;
      final wrongVersion = Map<String, dynamic>.of(encoded)
        ..['formatVersion'] = 'radoc-v1';
      expect(
        () => codec.decode(jsonEncode(wrongVersion)),
        throwsFormatException,
      );
      final wrongIdentity =
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      wrongIdentity['documentId'] = 'other';
      expect(
        () => codec.decode(jsonEncode(wrongIdentity)),
        throwsFormatException,
      );
      final wrongRevision =
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      (wrongRevision['preparedVoiceReferences']
              as List)[0]['documentRevision'] =
          11;
      expect(
        () => codec.decode(jsonEncode(wrongRevision)),
        throwsFormatException,
      );
      final unknownCast =
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      final unknownAssignmentSet =
          unknownCast['castVoiceAssignments'] as Map<String, dynamic>;
      ((unknownAssignmentSet['assignments'] as List).single as Map)['castId'] =
          'missing-cast';
      expect(
        () => codec.decode(jsonEncode(unknownCast)),
        throwsFormatException,
      );
      final incompleteAssignment =
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      final incompleteSet =
          incompleteAssignment['castVoiceAssignments'] as Map<String, dynamic>;
      ((incompleteSet['assignments'] as List).single as Map).remove(
        'decisionKind',
      );
      expect(
        () => codec.decode(jsonEncode(incompleteAssignment)),
        throwsFormatException,
      );
      final incompleteReference =
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      final resource =
          ((incompleteReference['preparedVoiceReferences'] as List).single
                  as Map)['resource']
              as Map;
      resource.remove('voiceDigest');
      expect(
        () => codec.decode(jsonEncode(incompleteReference)),
        throwsFormatException,
      );
      expect(() => codec.decode('{"formatId":'), throwsFormatException);
    },
  );
}
