import 'dart:convert';

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
    List<Map<String, Object?>> castVoiceAssignments = const [],
    List<Map<String, Object?>> preparedVoiceReferences = const [],
  }) {
    if (documentRevision < 0) {
      throw ArgumentError.value(documentRevision, 'documentRevision');
    }
    final legacy = jsonDecode(
      const ReaderDocumentSerializationService().serializeToJsonString(document),
    ) as Map<String, Object?>;
    legacy.remove('pdfDataBase64');
    final documentId = document.normalizedImportResult.documentId;
    final envelope = <String, Object?>{
      'formatId': formatId,
      'formatVersion': formatVersion,
      'documentId': documentId,
      'documentRevision': documentRevision,
      'preparedDocument': legacy,
      'castVoiceAssignments': castVoiceAssignments,
      'preparedVoiceReferences': preparedVoiceReferences,
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Re-encodes the decoded data snapshot without constructing runtime models.
  String reencode(InstrumentedDocumentArtifactSnapshot snapshot) => snapshot.encode();

  InstrumentedDocumentArtifactSnapshot decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('Artifact must be a JSON object.');
    final envelope = _freezeMap(decoded);
    if (envelope['formatId'] != formatId || envelope['formatVersion'] != formatVersion) {
      throw const FormatException('Unsupported artifact format or version.');
    }
    final id = _requiredString(envelope, 'documentId');
    final revision = envelope['documentRevision'];
    if (revision is! int || revision < 0) {
      throw const FormatException('documentRevision must be a non-negative integer.');
    }
    final prepared = envelope['preparedDocument'];
    if (prepared is! Map<String, Object?>) {
      throw const FormatException('preparedDocument must be an object.');
    }
    final normalized = prepared['normalizedImportResult'];
    if (normalized is! Map<String, Object?> || normalized['documentId'] != id) {
      throw const FormatException('Artifact and prepared document identities differ.');
    }
    _validateNestedDocumentIds(prepared, id);
    for (final key in ['displayDocument', 'speechDocument', 'positionMap',
      'baseSpeechAnnotations', 'dialogueAttributions', 'characterCastRegistry',
      'documentVoiceAttribution', 'basePronunciationArtifacts']) {
      final value = prepared[key];
      if (value is! Map<String, Object?>) {
        throw FormatException('preparedDocument.$key must be an object.');
      }
      final nestedId = value['documentId'];
      if (nestedId != null && nestedId != id) {
        throw FormatException('preparedDocument.$key has an inconsistent documentId.');
      }
    }
    final assignments = envelope['castVoiceAssignments'];
    final references = envelope['preparedVoiceReferences'];
    if (assignments is! List || references is! List) {
      throw const FormatException('Assignment and voice-reference lists are required.');
    }
    final castIds = <String>{};
    for (final raw in assignments) {
      if (raw is! Map<String, Object?>) throw const FormatException('Invalid assignment record.');
      final castId = _requiredString(raw, 'castId');
      _requiredString(raw, 'effectiveVoiceId');
      if (!castIds.add(castId)) throw const FormatException('Duplicate cast assignment.');
    }
    for (final raw in references) {
      if (raw is! Map<String, Object?>) throw const FormatException('Invalid voice reference.');
      if (_requiredString(raw, 'documentId') != id || raw['documentRevision'] != revision) {
        throw const FormatException('Voice reference has inconsistent document identity or revision.');
      }
      final castId = _requiredString(raw, 'castId');
      if (!castIds.contains(castId)) throw const FormatException('Voice reference has no cast assignment.');
      final assignment = assignments.cast<Map<String, Object?>>().firstWhere(
        (item) => item['castId'] == castId,
      );
      final resource = raw['resource'];
      if (resource is! Map<String, Object?> || resource['documentId'] != id ||
          resource['bindingRevision'] is! int || (resource['bindingRevision'] as int) < 0) {
        throw const FormatException('Invalid prepared voice resource reference.');
      }
      for (final field in ['voiceId', 'voiceDigest', 'modelDigest', 'engineVersion', 'pronunciationProfileId']) {
        _requiredString(resource, field);
      }
      if (resource['voiceId'] != assignment['effectiveVoiceId']) {
        throw const FormatException('Voice reference does not match its effective assignment.');
      }
    }
    return InstrumentedDocumentArtifactSnapshot._(envelope);
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) throw FormatException('$key must be a non-empty string.');
    return value;
  }

  static void _validateNestedDocumentIds(Object? value, String documentId) {
    if (value is Map<String, Object?>) {
      final nestedId = value['documentId'];
      if (nestedId != null && nestedId != documentId) {
        throw const FormatException('Nested document identity is inconsistent.');
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

  static Map<String, Object?> _freezeMap(Map source) => Map<String, Object?>.unmodifiable({
    for (final entry in source.entries)
      if (entry.key is String) entry.key as String: _freezeValue(entry.value),
  });

  static Object? _freezeValue(Object? value) {
    if (value is Map) return _freezeMap(value);
    if (value is List) return List<Object?>.unmodifiable(value.map(_freezeValue));
    if (value == null || value is String || value is num || value is bool) return value;
    throw const FormatException('Artifact contains a non-JSON value.');
  }
}
