import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;

import '../models/character_cast_registry.dart';
import '../models/dialogue_attribution.dart';
import '../models/document_preparation.dart';
import '../models/display_document.dart';
import '../models/document_voice_attribution.dart';
import '../models/position_map.dart';
import '../models/pronunciation_artifact.dart';
import '../models/reader_document.dart';
import '../models/speech_document.dart';
import 'reader_document_codec.dart';

class ReaderDocumentSerializationService {
  const ReaderDocumentSerializationService();

  static const formatId = 'read-aloud-document';
  static const formatVersion = 'radoc-v2';

  ReaderDocument deserializeFromJsonString(String source) =>
      decodeReaderDocument(source);
  static const fileExtension = '.radoc';

  String serializeToJsonString(
    ReaderDocument document, {
    Map<String, String> userVoiceAssignments = const {},
  }) {
    const encoder = JsonEncoder.withIndent('  ');
    final envelope = _toEnvelope(document);
    if (userVoiceAssignments.isNotEmpty) {
      envelope['userVoiceAssignments'] = validateReaderDocumentVoiceAssignments(
        userVoiceAssignments,
        document,
      );
    }
    return encoder.convert(envelope);
  }

  Future<File> writeToFile({
    required ReaderDocument document,
    required String outputPath,
    bool Function()? isCurrent,
    Map<String, String> userVoiceAssignments = const {},
    String? sourcePath,
  }) async {
    await requirePreservedDocumentExportPath(
      outputPath,
      sourcePath: sourcePath,
    );
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    final temporary = File(
      '$outputPath.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      final serialized = await _serializeDocumentOnWorker(
        document,
        Map.unmodifiable(userVoiceAssignments),
      );
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Document export cancelled');
      }
      await temporary.writeAsString(serialized, flush: true);
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Document export cancelled');
      }
      return await temporary.rename(outputPath);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// Explicit export work only. Call on a worker: merging derived graphs must
  /// never accumulate or re-analyse a growing book on the opening isolate.
  ReaderDocument combinePreparedRanges(
    List<DocumentPreparationPublication> ranges, {
    required String documentId,
  }) {
    if (ranges.isEmpty || !ranges.last.isLast) {
      throw const FormatException('A complete checkpoint is required');
    }
    final first = ranges.first.fragment;
    final output = _toEnvelope(first);
    final maps = ranges.map((p) => _toEnvelope(p.fragment)).toList();
    var sourceEnd = 0;
    var wordEnd = 0;
    var segmentEnd = 0;
    var blockEnd = 0;
    var paragraphEnd = 0;
    final cast = <String, Map<String, Object?>>{};
    final redirects = <String, String>{};
    Map<String, Object?> graph(Map<String, Object?> m, String name) =>
        m[name] as Map<String, Object?>;
    List<Map<String, Object?>> rows(
      Map<String, Object?> m,
      String g,
      String k,
    ) => (graph(m, g)[k] as List).cast<Map<String, Object?>>();
    const lists = {
      'displayDocument': 'blocks',
      'speechDocument': 'segments',
      'positionMap': 'entries',
      'baseSpeechAnnotations': 'annotations',
      'dialogueAttributions': 'outcomes',
      'documentVoiceAttribution': 'ranges',
      'basePronunciationArtifacts': 'artifacts',
      'normalizedImportResult': 'diagnostics',
    };
    for (var index = 0; index < ranges.length; index++) {
      final publication = ranges[index];
      final r = publication.range;
      if (publication.sequence != index + 1 ||
          publication.request.effectiveSourceRevision !=
              ranges.first.request.effectiveSourceRevision ||
          r.sourceStart != sourceEnd ||
          r.wordStart != wordEnd ||
          r.segmentStart != segmentEnd ||
          r.sourceEnd < r.sourceStart ||
          r.wordEnd - r.wordStart != publication.fragment.wordCount ||
          r.segmentEnd - r.segmentStart !=
              publication.fragment.speechDocument.segments.length ||
          !publication.isPreparationReady) {
        throw const FormatException('Incomplete or unordered export coverage');
      }
      final m = maps[index];
      // These producer-local counters reset for each fragment. Their references
      // are contained within that fragment, unlike stable segment/cast IDs.
      for (final annotation in rows(
        m,
        'baseSpeechAnnotations',
        'annotations',
      )) {
        annotation['annotationId'] =
            'range${publication.sequence}:${annotation['annotationId']}';
      }
      for (final artifact in rows(
        m,
        'basePronunciationArtifacts',
        'artifacts',
      )) {
        artifact['artifactId'] =
            'range${publication.sequence}:${artifact['artifactId']}';
        for (final representation
            in (artifact['representations'] as List)
                .cast<Map<String, Object?>>()) {
          representation['representationId'] =
              'range${publication.sequence}:${representation['representationId']}';
        }
      }
      if (publication.fragment.speechDocument.normalizationVersion !=
              first.speechDocument.normalizationVersion ||
          publication.fragment.positionMap.mappingVersion !=
              first.positionMap.mappingVersion) {
        throw const FormatException('Incompatible export dependencies');
      }
      final blocks = rows(m, 'displayDocument', 'blocks');
      for (var i = 0; i < blocks.length; i++) {
        blocks[i]['ordinal'] = blockEnd + i;
      }
      blockEnd += blocks.length;
      final segments = rows(m, 'speechDocument', 'segments');
      var paragraphs = 0;
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        segment['ordinal'] = segmentEnd + i;
        final localParagraph = segment['paragraphIndex'] as int;
        if (localParagraph + 1 > paragraphs) paragraphs = localParagraph + 1;
        segment['paragraphIndex'] = paragraphEnd + localParagraph;
      }
      paragraphEnd += paragraphs;
      for (final range in rows(m, 'documentVoiceAttribution', 'ranges')) {
        range['startWordIndex'] = (range['startWordIndex'] as int) + wordEnd;
        range['endWordIndex'] = (range['endWordIndex'] as int) + wordEnd;
      }
      for (final entry in rows(m, 'characterCastRegistry', 'entries')) {
        cast[entry['castId'] as String] = entry;
      }
      redirects.addAll(
        (graph(m, 'characterCastRegistry')['castIdRedirects'] as Map)
            .cast<String, String>(),
      );
      sourceEnd = r.sourceEnd;
      wordEnd = r.wordEnd;
      segmentEnd = r.segmentEnd;
    }
    for (final item in lists.entries) {
      graph(output, item.key)[item.value] = [
        for (final m in maps) ...rows(m, item.key, item.value),
      ];
    }
    graph(output, 'displayDocument')['assets'] = {
      for (final m in maps)
        ...(graph(m, 'displayDocument')['assets'] as Map<String, Object?>),
    };
    final segments = rows(output, 'speechDocument', 'segments');
    graph(output, 'speechDocument')['totalWordCount'] = wordEnd;
    graph(output, 'speechDocument')['segmentIndexById'] = {
      for (var i = 0; i < segments.length; i++) segments[i]['segmentId']!: i,
    };
    String canonicalCast(String id) {
      final seen = <String>{};
      while (redirects.containsKey(id)) {
        if (!seen.add(id)) throw const FormatException('Cyclic cast redirect');
        id = redirects[id]!;
      }
      return id;
    }

    for (final range in rows(output, 'documentVoiceAttribution', 'ranges')) {
      range['castId'] = canonicalCast(range['castId'] as String);
    }
    graph(output, 'characterCastRegistry')['entries'] = [
      for (final entry in cast.entries)
        if (canonicalCast(entry.key) == entry.key) entry.value,
    ];
    graph(output, 'characterCastRegistry')['castIdRedirects'] = redirects;
    for (final name in [...lists.keys, 'characterCastRegistry']) {
      graph(output, name)['documentId'] = documentId;
    }
    graph(output, 'normalizedImportResult')['sourceFingerprint'] =
        'prepared-snapshot:${ranges.first.request.effectiveSourceRevision}';
    output['speakableText'] = ranges
        .map((p) => p.fragment.speakableText)
        .join('\n\n');
    output['displayHtml'] = ranges
        .map((p) => p.fragment.displayHtml)
        .join('\n');
    output['sourceDescription'] =
        'Complete prepared document ($sourceEnd source units)';
    output['attachments'] = [
      for (final m in maps) ...(m['attachments'] as List),
    ];
    // Decode validates graph identity, unique speech IDs and exact word coverage
    // without invoking an importer, attribution or annotation inference.
    return decodeReaderDocument(jsonEncode(output));
  }

  Map<String, Object?> _toEnvelope(ReaderDocument document) {
    return <String, Object?>{
      'formatId': formatId,
      'formatVersion': formatVersion,
      'title': document.title,
      'documentType': document.type.name,
      'presentation': document.presentation.name,
      'pdfDataBase64': document.pdfData == null
          ? null
          : base64Encode(document.pdfData!),
      'sourceDescription': document.sourceDescription,
      'displayHtml': document.displayHtml,
      'speakableText': document.speakableText,
      'normalizedImportResult': <String, Object?>{
        'documentId': document.normalizedImportResult.documentId,
        'sourceType': document.normalizedImportResult.sourceType,
        'bestAvailableTitle':
            document.normalizedImportResult.bestAvailableTitle,
        'sourceUri': document.normalizedImportResult.sourceUri?.toString(),
        'sourceFingerprint': document.normalizedImportResult.sourceFingerprint,
        'normalizationVersion':
            document.normalizedImportResult.normalizationVersion,
        'mappingVersion': document.normalizedImportResult.mappingVersion,
        'diagnostics': document.normalizedImportResult.diagnostics
            .map(
              (diagnostic) => <String, Object?>{
                'severity': diagnostic.severity.name,
                'code': diagnostic.code,
                'message': diagnostic.message,
                'relatedBlockId': diagnostic.relatedBlockId,
                'sourceLocator': diagnostic.sourceLocator,
              },
            )
            .toList(growable: false),
      },
      'displayDocument': _displayDocumentToMap(document.displayDocument),
      'speechDocument': _speechDocumentToMap(document.speechDocument),
      'positionMap': _positionMapToMap(document.positionMap),
      'baseSpeechAnnotations': document.baseSpeechAnnotations.toJson(
        includePerformanceIntents: true,
      ),
      'dialogueAttributions': _dialogueAttributionsToMap(
        document.dialogueAttributions,
      ),
      'characterCastRegistry': _characterCastRegistryToMap(
        document.characterCastRegistry,
      ),
      'documentVoiceAttribution': _documentVoiceAttributionToMap(
        document.documentVoiceAttribution,
      ),
      'basePronunciationArtifacts': _pronunciationArtifactsToMap(
        document.basePronunciationArtifacts,
      ),
      'attachments': document.attachments
          .map(
            (attachment) => <String, Object?>{
              'label': attachment.label,
              'type': attachment.type.name,
              'source': attachment.source,
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, Object?> _displayDocumentToMap(DisplayDocument document) {
    return <String, Object?>{
      'documentId': document.documentId,
      'sourceType': document.sourceType,
      'sourceUri': document.sourceUri?.toString(),
      'title': document.title,
      'normalizationVersion': document.normalizationVersion,
      'metadata': document.metadata,
      'blocks': document.blocks
          .map(
            (block) => <String, Object?>{
              'blockId': block.blockId,
              'kind': block.kind.name,
              'ordinal': block.ordinal,
              'assetId': block.assetId,
              'parentBlockId': block.parentBlockId,
              'attributes': block.attributes,
              'inlines': block.inlines
                  .map(
                    (inline) => <String, Object?>{
                      'kind': inline.kind.name,
                      'text': inline.text,
                      'attributes': inline.attributes,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
      'assets': <String, Object?>{
        for (final entry in document.assets.entries)
          entry.key: <String, Object?>{
            'assetId': entry.value.assetId,
            'kind': entry.value.kind.name,
            'resolvedUri': entry.value.resolvedUri.toString(),
            'mimeType': entry.value.mimeType,
            'metadata': entry.value.metadata,
          },
      },
    };
  }

  Map<String, Object?> _speechDocumentToMap(SpeechDocument document) {
    return <String, Object?>{
      'documentId': document.documentId,
      'sourceType': document.sourceType,
      'languageTag': document.languageTag,
      'normalizationVersion': document.normalizationVersion,
      'totalWordCount': document.totalWordCount,
      'segmentIndexById': document.segmentIndexById,
      'segments': document.segments
          .map(
            (segment) => <String, Object?>{
              'segmentId': segment.segmentId,
              'blockId': segment.blockId,
              'ordinal': segment.ordinal,
              'paragraphIndex': segment.paragraphIndex,
              'sentenceIndex': segment.sentenceIndex,
              'normalizedText': segment.normalizedText,
              'wordCount': segment.wordCount,
              'sourceRange': segment.sourceRange == null
                  ? null
                  : <String, Object?>{
                      'startOffset': segment.sourceRange!.startOffset,
                      'endOffset': segment.sourceRange!.endOffset,
                      'coordinateSpace': segment.sourceRange!.coordinateSpace,
                    },
              'displayAnchor': segment.displayAnchor == null
                  ? null
                  : <String, Object?>{
                      'blockId': segment.displayAnchor!.blockId,
                      'startInlineOffset':
                          segment.displayAnchor!.startInlineOffset,
                      'endInlineOffset': segment.displayAnchor!.endInlineOffset,
                    },
              'wordSpans': segment.wordSpans
                  .map(
                    (span) => <String, Object?>{
                      'wordIndexWithinSegment': span.wordIndexWithinSegment,
                      'startUtf16': span.startUtf16,
                      'endUtf16': span.endUtf16,
                      'text': span.text,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, Object?> _positionMapToMap(PositionMap positionMap) {
    return <String, Object?>{
      'documentId': positionMap.documentId,
      'mappingVersion': positionMap.mappingVersion,
      'entries': positionMap.entries
          .map(
            (entry) => <String, Object?>{
              'entryId': entry.entryId,
              'displayBlockId': entry.displayBlockId,
              'speechSegmentId': entry.speechSegmentId,
              'displayStart': entry.displayStart,
              'displayEnd': entry.displayEnd,
              'speechStartWord': entry.speechStartWord,
              'speechEndWord': entry.speechEndWord,
              'confidence': entry.confidence,
              'recoveryAnchor': entry.recoveryAnchor == null
                  ? null
                  : <String, Object?>{
                      'exact': entry.recoveryAnchor!.exact,
                      'prefix': entry.recoveryAnchor!.prefix,
                      'suffix': entry.recoveryAnchor!.suffix,
                    },
              'sourceAnchor': _sourceAnchorToMap(entry.sourceAnchor),
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, Object?>? _sourceAnchorToMap(SourceAnchor? sourceAnchor) {
    if (sourceAnchor == null) {
      return null;
    }
    return switch (sourceAnchor) {
      EpubSourceAnchor() => <String, Object?>{
        'kind': 'epub',
        'spineItemId': sourceAnchor.spineItemId,
        'cfi': sourceAnchor.cfi,
      },
      PdfSourceAnchor() => <String, Object?>{
        'kind': 'pdf',
        'pageIndex': sourceAnchor.pageIndex,
        'sourceBlockId': sourceAnchor.sourceBlockId,
      },
      HtmlSourceAnchor() => <String, Object?>{
        'kind': 'html',
        'cssSelector': sourceAnchor.cssSelector,
      },
    };
  }

  Map<String, Object?> _dialogueAttributionsToMap(
    DialogueAttributionSet attributions,
  ) {
    return <String, Object?>{
      'documentId': attributions.documentId,
      'attributionVersion': attributions.attributionVersion,
      'providerId': attributions.providerId,
      'providerVersion': attributions.providerVersion,
      'outcomes': attributions.outcomes
          .map(
            (outcome) => <String, Object?>{
              'attributionId': outcome.attributionId,
              'dialogueSpanId': outcome.dialogueSpanId,
              'resolution': outcome.resolution.name,
              'confidence': outcome.confidence,
              'provenance': outcome.provenance.name,
              'ruleUsed': outcome.ruleUsed.name,
              'evidenceSpan': outcome.evidenceSpan == null
                  ? null
                  : <String, Object?>{
                      'segmentId': outcome.evidenceSpan!.segmentId,
                      'startUtf16': outcome.evidenceSpan!.startUtf16,
                      'endUtf16': outcome.evidenceSpan!.endUtf16,
                      'text': outcome.evidenceSpan!.text,
                    },
              'speakerReference': outcome.speakerReference == null
                  ? null
                  : <String, Object?>{
                      'referenceId': outcome.speakerReference!.referenceId,
                      'displayLabel': outcome.speakerReference!.displayLabel,
                      'normalizedLabel':
                          outcome.speakerReference!.normalizedLabel,
                    },
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, Object?> _characterCastRegistryToMap(
    CharacterCastRegistry registry,
  ) {
    return <String, Object?>{
      'documentId': registry.documentId,
      'registryVersion': registry.registryVersion,
      'castIdRedirects': registry.castIdRedirects,
      'entries': registry.entries
          .map(
            (entry) => <String, Object?>{
              'castId': entry.castId,
              'roleKind': entry.roleKind.name,
              'displayLabel': entry.displayLabel,
              'confidence': entry.confidence,
              'provenance': entry.provenance.name,
              'observedAliases': entry.observedAliases,
              'attributionIds': entry.attributionIds,
              'identityProfile': entry.identityProfile == null
                  ? null
                  : <String, Object?>{
                      'genderIdentityLabel': _identityLabelName(
                        entry.identityProfile!.genderIdentityLabel,
                      ),
                      'genderConfidence':
                          entry.identityProfile!.genderConfidence,
                      'genderSource': _identitySourceName(
                        entry.identityProfile!.genderSource,
                      ),
                      'pronounProfile': <String, Object?>{
                        'counts': entry.identityProfile!.pronounProfile.counts,
                      },
                      'evidenceSpans': entry.identityProfile!.evidenceSpans
                          .map(
                            (span) => <String, Object?>{
                              'segmentId': span.segmentId,
                              'startUtf16': span.startUtf16,
                              'endUtf16': span.endUtf16,
                              'text': span.text,
                              'source': _identitySourceName(span.source),
                              'genderIdentityLabel':
                                  span.genderIdentityLabel == null
                                  ? null
                                  : _identityLabelName(
                                      span.genderIdentityLabel!,
                                    ),
                            },
                          )
                          .toList(growable: false),
                      'conflictFlag': entry.identityProfile!.conflictFlag,
                      'countedSegmentIds':
                          entry.identityProfile!.countedSegmentIds,
                    },
              'inferredGender': entry.inferredGender?.name,
              'inferredGenderConfidence': entry.inferredGenderConfidence,
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, Object?> _documentVoiceAttributionToMap(
    DocumentVoiceAttributionSet attribution,
  ) {
    return <String, Object?>{
      'documentId': attribution.documentId,
      'attributionVersion': attribution.attributionVersion,
      'ranges': attribution.ranges
          .map(
            (range) => <String, Object?>{
              'rangeId': range.rangeId,
              'segmentIds': range.segmentIds,
              'startSegmentId': range.startSegmentId,
              'endSegmentId': range.endSegmentId,
              'startWordIndex': range.startWordIndex,
              'endWordIndex': range.endWordIndex,
              'castId': range.castId,
              'kind': range.kind.name,
              'dialogueSpanId': range.dialogueSpanId,
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, Object?> _pronunciationArtifactsToMap(
    BasePronunciationArtifactSet artifacts,
  ) {
    return <String, Object?>{
      'documentId': artifacts.documentId,
      'artifactVersion': artifacts.artifactVersion,
      'normalizationVersion': artifacts.normalizationVersion,
      'pronunciationProfileId': artifacts.pronunciationProfileId,
      'artifacts': artifacts.artifacts
          .map(
            (artifact) => <String, Object?>{
              'artifactId': artifact.artifactId,
              'segmentId': artifact.segmentId,
              'startWord': artifact.startWord,
              'endWord': artifact.endWord,
              'surfaceText': artifact.surfaceText,
              'normalizedSurfaceText': artifact.normalizedSurfaceText,
              'artifactClass': artifact.artifactClass.name,
              'source': artifact.source.name,
              'confidence': artifact.confidence,
              'diagnosticCodes': artifact.diagnosticCodes,
              'representations': artifact.representations
                  .map(
                    (representation) => <String, Object?>{
                      'representationId': representation.representationId,
                      'representationType': representation.representationType,
                      'representationValue': representation.representationValue,
                      'accentFamily': representation.accentFamily,
                      'priority': representation.priority,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
  }

  String _identityLabelName(CharacterGenderIdentityLabel label) {
    return switch (label) {
      CharacterGenderIdentityLabel.male => 'male',
      CharacterGenderIdentityLabel.female => 'female',
      CharacterGenderIdentityLabel.cisMale => 'cis_male',
      CharacterGenderIdentityLabel.cisFemale => 'cis_female',
      CharacterGenderIdentityLabel.transgender => 'transgender',
      CharacterGenderIdentityLabel.transMale => 'trans_male',
      CharacterGenderIdentityLabel.transFemale => 'trans_female',
      CharacterGenderIdentityLabel.nonbinary => 'nonbinary',
      CharacterGenderIdentityLabel.genderqueer => 'genderqueer',
      CharacterGenderIdentityLabel.unknown => 'unknown',
    };
  }

  String _identitySourceName(CharacterGenderEvidenceSource source) {
    return switch (source) {
      CharacterGenderEvidenceSource.explicitIdentity => 'explicit_identity',
      CharacterGenderEvidenceSource.explicitApposition => 'explicit_apposition',
      CharacterGenderEvidenceSource.descriptor => 'descriptor',
      CharacterGenderEvidenceSource.pronoun => 'pronoun',
      CharacterGenderEvidenceSource.unknown => 'unknown',
    };
  }
}

// Keep closures outside async scopes containing UI cancellation callbacks.
Future<String> _serializeDocumentOnWorker(
  ReaderDocument document,
  Map<String, String> userVoiceAssignments,
) => Isolate.run(
  () => const ReaderDocumentSerializationService().serializeToJsonString(
    document,
    userVoiceAssignments: userVoiceAssignments,
  ),
);

/// Resolve an existing destination parent so directory symlinks cannot alias
/// original inputs or checkpoint files. Rename replaces a final symlink rather
/// than following it; the parent is the relevant publication destination.
Future<void> requirePreservedDocumentExportPath(
  String outputPath, {
  String? sourcePath,
  String? checkpointRoot,
}) async {
  Future<String> destination(String path) async {
    final absolute = p.normalize(p.absolute(path));
    try {
      final parent = await Directory(
        p.dirname(absolute),
      ).resolveSymbolicLinks();
      return p.join(parent, p.basename(absolute));
    } on FileSystemException {
      return absolute;
    }
  }

  final output = await destination(outputPath);
  if (sourcePath != null) {
    var source = await destination(sourcePath);
    try {
      source = await File(sourcePath).resolveSymbolicLinks();
    } on FileSystemException {
      // A source may have been moved since its complete checkpoint was made.
    }
    if (output == source || output == await destination(sourcePath)) {
      throw ArgumentError('Export must preserve the original source');
    }
  }
  if (checkpointRoot != null) {
    final root = await Directory(checkpointRoot).resolveSymbolicLinks();
    if (output == root || p.isWithin(root, output)) {
      throw ArgumentError('Export must preserve checkpoint files');
    }
  }
}
