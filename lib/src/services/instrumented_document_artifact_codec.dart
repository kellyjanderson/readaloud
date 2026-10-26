import 'dart:convert';

import '../models/cast_voice_assignment.dart';
import '../models/prepared_voice_binding.dart';
import '../models/reader_document.dart';
import 'reader_document_serialization_service.dart';

/// Immutable, data-only inspection snapshot decoded from `.radoc-v2`.
/// Values are JSON primitives, lists, and maps; no runtime document is built.
class InstrumentedDocumentArtifactSnapshot {
  InstrumentedDocumentArtifactSnapshot._(this._data);

  final Map<String, Object?> _data;
  Map<String, Object?> get data => _data;
  String get documentId => _data['documentId']! as String;
  int get documentRevision => _data['documentRevision']! as int;

  String encode() => const JsonEncoder.withIndent('  ').convert(_data);
}

/// A separate, data-only artifact format. It deliberately does not offer an
/// import/reopen operation or serialize PDF bytes, native handles, or assets.
class InstrumentedDocumentArtifactCodec {
  const InstrumentedDocumentArtifactCodec();

  static const formatId = 'read-aloud-instrumented-artifact';
  static const formatVersion = 'radoc-v2';
  static const fileExtension = '.radoc-v2';

  String encode({
    required ReaderDocument document,
    required int documentRevision,
    required CastVoiceAssignmentSet castVoiceAssignments,
    List<ResolvedPreparedVoiceReference> preparedVoiceReferences = const [],
  }) {
    if (documentRevision < 0) {
      throw ArgumentError.value(documentRevision, 'documentRevision');
    }
    final legacy =
        jsonDecode(
              const ReaderDocumentSerializationService().serializeToJsonString(
                document,
              ),
            )
            as Map<String, Object?>;
    legacy.remove('pdfDataBase64');
    final documentId = document.normalizedImportResult.documentId;
    if (castVoiceAssignments.documentId != documentId) {
      throw ArgumentError('Assignment set belongs to a different document.');
    }
    final envelope = <String, Object?>{
      'formatId': formatId,
      'formatVersion': formatVersion,
      'documentId': documentId,
      'documentRevision': documentRevision,
      'preparedDocument': legacy,
      'castVoiceAssignments': <String, Object?>{
        'documentId': castVoiceAssignments.documentId,
        'assignmentVersion': castVoiceAssignments.assignmentVersion,
        'assignments': castVoiceAssignments.assignments
            .map(_assignmentToMap)
            .toList(growable: false),
      },
      'preparedVoiceReferences': preparedVoiceReferences
          .map((reference) => reference.toMap())
          .toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Re-encodes the decoded data snapshot without constructing runtime models.
  String reencode(InstrumentedDocumentArtifactSnapshot snapshot) =>
      snapshot.encode();

  InstrumentedDocumentArtifactSnapshot decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Artifact must be a JSON object.');
    }
    final envelope = _freezeMap(decoded);
    if (envelope['formatId'] != formatId ||
        envelope['formatVersion'] != formatVersion) {
      throw const FormatException('Unsupported artifact format or version.');
    }
    final id = _requiredString(envelope, 'documentId');
    final revision = envelope['documentRevision'];
    if (revision is! int || revision < 0) {
      throw const FormatException(
        'documentRevision must be a non-negative integer.',
      );
    }
    final prepared = envelope['preparedDocument'];
    if (prepared is! Map<String, Object?>) {
      throw const FormatException('preparedDocument must be an object.');
    }
    final normalized = prepared['normalizedImportResult'];
    if (normalized is! Map<String, Object?> || normalized['documentId'] != id) {
      throw const FormatException(
        'Artifact and prepared document identities differ.',
      );
    }
    _validateNestedDocumentIds(prepared, id);
    for (final key in [
      'displayDocument',
      'speechDocument',
      'positionMap',
      'baseSpeechAnnotations',
      'dialogueAttributions',
      'characterCastRegistry',
      'documentVoiceAttribution',
      'basePronunciationArtifacts',
    ]) {
      final value = prepared[key];
      if (value is! Map<String, Object?>) {
        throw FormatException('preparedDocument.$key must be an object.');
      }
      final nestedId = value['documentId'];
      if (nestedId != null && nestedId != id) {
        throw FormatException(
          'preparedDocument.$key has an inconsistent documentId.',
        );
      }
    }
    final assignmentSet = envelope['castVoiceAssignments'];
    final references = envelope['preparedVoiceReferences'];
    if (assignmentSet is! Map<String, Object?> || references is! List) {
      throw const FormatException(
        'Assignment and voice-reference lists are required.',
      );
    }
    if (assignmentSet['documentId'] != id ||
        !_isNonEmptyString(assignmentSet['assignmentVersion'])) {
      throw const FormatException(
        'Assignment set identity or version is invalid.',
      );
    }
    final assignments = assignmentSet['assignments'];
    if (assignments is! List) {
      throw const FormatException('Assignments must be a list.');
    }
    final registry = prepared['characterCastRegistry'] as Map<String, Object?>;
    final entries = registry['entries'];
    if (entries is! List) {
      throw const FormatException('Cast registry entries must be a list.');
    }
    final registryCastIds = <String>{};
    for (final entry in entries) {
      if (entry is! Map<String, Object?>) {
        throw const FormatException('Invalid cast registry entry.');
      }
      registryCastIds.add(_requiredString(entry, 'castId'));
    }
    final castIds = <String>{};
    final assignmentsByCastId = <String, Map<String, Object?>>{};
    for (final raw in assignments) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Invalid assignment record.');
      }
      final castId = _requiredString(raw, 'castId');
      if (!registryCastIds.contains(castId)) {
        throw const FormatException(
          'Assignment castId is absent from the cast registry.',
        );
      }
      _requiredString(raw, 'effectiveVoiceId');
      if (!_validDecisionKind(raw['decisionKind'])) {
        throw const FormatException('Invalid assignment decision provenance.');
      }
      for (final field in [
        'automaticVoiceId',
        'storedVoiceId',
        'userOverrideVoiceId',
      ]) {
        if (!raw.containsKey(field) ||
            (raw[field] != null && !_isNonEmptyString(raw[field]))) {
          throw FormatException('Assignment $field is missing or invalid.');
        }
      }
      if (!castIds.add(castId)) {
        throw const FormatException('Duplicate cast assignment.');
      }
      assignmentsByCastId[castId] = raw;
    }
    for (final raw in references) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Invalid voice reference.');
      }
      if (_requiredString(raw, 'documentId') != id ||
          raw['documentRevision'] != revision) {
        throw const FormatException(
          'Voice reference has inconsistent document identity or revision.',
        );
      }
      final castId = _requiredString(raw, 'castId');
      if (!castIds.contains(castId)) {
        throw const FormatException('Voice reference has no cast assignment.');
      }
      for (final field in [
        'decisionKind',
        'automaticVoiceId',
        'storedVoiceId',
        'userOverrideVoiceId',
      ]) {
        if (!raw.containsKey(field) ||
            (field != 'decisionKind' &&
                raw[field] != null &&
                !_isNonEmptyString(raw[field]))) {
          throw FormatException(
            'Voice reference $field is missing or invalid.',
          );
        }
      }
      final assignment = assignmentsByCastId[castId]!;
      if (raw['decisionKind'] != assignment['decisionKind']) {
        throw const FormatException(
          'Voice reference assignment provenance differs.',
        );
      }
      final resource = raw['resource'];
      if (resource is! Map<String, Object?> ||
          resource['documentId'] != id ||
          resource['bindingRevision'] is! int ||
          (resource['bindingRevision'] as int) < 0) {
        throw const FormatException(
          'Invalid prepared voice resource reference.',
        );
      }
      for (final field in [
        'voiceId',
        'voiceDigest',
        'modelDigest',
        'engineVersion',
        'pronunciationProfileId',
      ]) {
        _requiredString(resource, field);
      }
      if (resource['voiceId'] != assignment['effectiveVoiceId']) {
        throw const FormatException(
          'Voice reference does not match its effective assignment.',
        );
      }
    }
    return InstrumentedDocumentArtifactSnapshot._(envelope);
  }

  static Map<String, Object?> _assignmentToMap(
    CastVoiceAssignment assignment,
  ) => <String, Object?>{
    'castId': assignment.castId,
    'effectiveVoiceId': assignment.effectiveVoiceId,
    'decisionKind': assignment.decisionKind.name,
    'automaticVoiceId': assignment.automaticVoiceId,
    'storedVoiceId': assignment.storedVoiceId,
    'userOverrideVoiceId': assignment.userOverrideVoiceId,
  };

  static bool _isNonEmptyString(Object? value) =>
      value is String && value.trim().isNotEmpty;

  static bool _validDecisionKind(Object? value) =>
      VoiceAssignmentDecisionKind.values.any((kind) => kind.name == value);

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key must be a non-empty string.');
    }
    return value;
  }

  static void _validateNestedDocumentIds(Object? value, String documentId) {
    if (value is Map<String, Object?>) {
      final nestedId = value['documentId'];
      if (nestedId != null && nestedId != documentId) {
        throw const FormatException(
          'Nested document identity is inconsistent.',
        );
      }
      for (final child in value.values) {
        _validateNestedDocumentIds(child, documentId);
      }
    } else if (value is List) {
      for (final child in value) {
        _validateNestedDocumentIds(child, documentId);
      }
    }
  }

  static Map<String, Object?> _freezeMap(Map source) {
    if (source.keys.any((key) => key is! String)) {
      throw const FormatException('Artifact object key is not a string.');
    }
    return Map<String, Object?>.unmodifiable({
      for (final entry in source.entries)
        entry.key as String: _freezeValue(entry.value),
    });
  }

  static Object? _freezeValue(Object? value) {
    if (value is Map) return _freezeMap(value);
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_freezeValue));
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw const FormatException('Artifact contains a non-JSON value.');
  }
}
