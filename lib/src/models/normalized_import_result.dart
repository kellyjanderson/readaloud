import 'display_document.dart';
import 'import_diagnostic.dart';
import 'position_map.dart';
import 'speech_document.dart';

class NormalizedImportResult {
  NormalizedImportResult({
    required this.documentId,
    required this.sourceType,
    required this.bestAvailableTitle,
    required this.sourceUri,
    required this.sourceFingerprint,
    required this.normalizationVersion,
    required this.mappingVersion,
    required this.displayDocument,
    required this.speechDocument,
    required this.positionMap,
    this.diagnostics = const <ImportDiagnostic>[],
  }) : assert(displayDocument.documentId == documentId),
       assert(speechDocument.documentId == documentId),
       assert(positionMap.documentId == documentId),
       assert(displayDocument.sourceType == sourceType),
       assert(speechDocument.sourceType == sourceType),
       assert(displayDocument.title == bestAvailableTitle),
       assert(displayDocument.sourceUri == sourceUri),
       assert(displayDocument.normalizationVersion == normalizationVersion),
       assert(speechDocument.normalizationVersion == normalizationVersion),
       assert(positionMap.mappingVersion == mappingVersion);

  final String documentId;
  final String sourceType;
  final String bestAvailableTitle;
  final Uri? sourceUri;
  final String sourceFingerprint;
  final String normalizationVersion;
  final String mappingVersion;
  final DisplayDocument displayDocument;
  final SpeechDocument speechDocument;
  final PositionMap positionMap;
  final List<ImportDiagnostic> diagnostics;
}
