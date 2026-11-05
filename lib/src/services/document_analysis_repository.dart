import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'atomic_text_file.dart';
import 'document_analysis_record.dart';
import 'modernbooknlp_provider.dart';

/// Working .radoc evidence store. One admitted writer, immutable key-addressed
/// records, no queue; supervisor owns lifetime. Hash/codec/file work runs off UI.
class DocumentAnalysisRepository {
  DocumentAnalysisRepository(this.rootPath);
  final String rootPath;
  bool _writing = false;
  String _directory(String source) =>
      '$rootPath/${DocumentAnalysisRecord.digest(source)}';
  String pathFor(ModernBookNlpRequest request) =>
      '${_directory(request.sourceRevision)}/${DocumentAnalysisRecord.requestKey(request)}.json';

  Future<DocumentAnalysisRecord?> read(ModernBookNlpRequest request) {
    final path = pathFor(request);
    return Isolate.run(() async {
      if (!await File(path).exists()) return null;
      final record = await _read(path);
      if (record.key != DocumentAnalysisRecord.requestKey(request)) {
        throw const FormatException('Saved analysis identity mismatch');
      }
      return record.reusable ? record : null;
    });
  }

  Future<DocumentAnalysisRecord> save(
    ModernBookNlpRequest request,
    Map<String, dynamic> output, {
    required bool Function() isCurrent,
  }) async {
    if (_writing) throw StateError('Analysis writer already active');
    _writing = true;
    final path = pathFor(request);
    final stage = '$path.$pid.${DateTime.now().microsecondsSinceEpoch}.stage';
    try {
      final record = await Isolate.run(() async {
        final value = DocumentAnalysisRecord.capture(request, output);
        final payload = jsonEncode(value.toJson());
        await Directory(File(path).parent.path).create(recursive: true);
        await atomicWriteText(
          stage,
          jsonEncode({
            'sha256': DocumentAnalysisRecord.digest(payload),
            'payload': payload,
          }),
        );
        return value;
      });
      if (!isCurrent()) throw const ModernBookNlpCancelled();
      // Only the supervisor's current window can admit this short atomic commit.
      await File(stage).rename(path);
      return record;
    } finally {
      try {
        if (await File(stage).exists()) await File(stage).delete();
      } finally {
        _writing = false;
      }
    }
  }

  /// Explicit export only. Never enumerate the book on ordinary window lookup.
  Future<List<DocumentAnalysisRecord>> recordsForSource(String source) {
    final directory = _directory(source);
    return Isolate.run(() async {
      final folder = Directory(directory);
      if (!await folder.exists()) return <DocumentAnalysisRecord>[];
      final records = <DocumentAnalysisRecord>[];
      await for (final entry in folder.list()) {
        if (entry is File && entry.path.endsWith('.json')) {
          final record = await _read(entry.path);
          if (record.sourceRevision != source) {
            throw const FormatException('Mixed analysis sources');
          }
          records.add(record);
        }
      }
      records.sort((a, b) => a.key.compareTo(b.key));
      return records;
    });
  }
}

Future<DocumentAnalysisRecord> _read(String path) async {
  final file = File(path);
  if (await file.length() > 4 * 1024 * 1024) {
    throw const FormatException('Saved analysis exceeds bound');
  }
  final envelope = jsonDecode(await file.readAsString());
  if (envelope is! Map || envelope['payload'] is! String) {
    throw const FormatException('Malformed saved analysis envelope');
  }
  final payload = envelope['payload'] as String;
  if (DocumentAnalysisRecord.digest(payload) != envelope['sha256']) {
    throw const FormatException('Saved analysis checksum failed');
  }
  final value = jsonDecode(payload);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Malformed saved analysis record');
  }
  return DocumentAnalysisRecord.fromJson(value);
}
