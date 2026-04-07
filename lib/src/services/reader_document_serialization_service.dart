import 'dart:convert';
import 'dart:io';

import '../models/character_cast_registry.dart';
import '../models/dialogue_attribution.dart';
import '../models/display_document.dart';
import '../models/document_voice_attribution.dart';
import '../models/position_map.dart';
import '../models/pronunciation_artifact.dart';
import '../models/reader_document.dart';
import '../models/speech_document.dart';

class ReaderDocumentSerializationService {
  const ReaderDocumentSerializationService();

  static const formatId = 'read-aloud-document';
  static const formatVersion = 'radoc-v1';
  static const fileExtension = '.radoc';

  String serializeToJsonString(ReaderDocument document) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_toEnvelope(document));
  }

  Future<File> writeToFile({
    required ReaderDocument document,
    required String outputPath,
  }) async {
    final file = File(outputPath);
    await file.create(recursive: true);
    await file.writeAsString(serializeToJsonString(document));
    return file;
  }

  Map<String, Object?> _toEnvelope(ReaderDocument document) {
    return <String, Object?>{
      'formatId': formatId,
      'formatVersion': formatVersion,
      'title': document.title,
      'documentType': document.type.name,
      'presentation': document.presentation.name,
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
      'baseSpeechAnnotations': document.baseSpeechAnnotations.toJson(),
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
                            },
                          )
                          .toList(growable: false),
                      'conflictFlag': entry.identityProfile!.conflictFlag,
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
