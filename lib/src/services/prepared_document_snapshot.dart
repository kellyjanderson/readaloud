import 'dart:typed_data';

import '../models/display_document.dart';
import '../models/normalized_import_result.dart';
import '../models/position_map.dart';
import '../models/pronunciation_artifact.dart';
import '../models/reader_document.dart';
import '../models/speech_document.dart';

/// Runs on the preparation worker. Does not render, normalize or analyze again.
ReaderDocument freezePreparedDocument(ReaderDocument document) {
  final n = document.normalizedImportResult;
  final d = n.displayDocument;
  final s = n.speechDocument;
  final a = document.basePronunciationArtifacts;
  return ReaderDocument.preparedSnapshot(
    source: document,
    pdfData: document.pdfData == null
        ? null
        : Uint8List.fromList(document.pdfData!).asUnmodifiableView(),
    normalizedImportResult: NormalizedImportResult(
      documentId: n.documentId,
      sourceType: n.sourceType,
      bestAvailableTitle: n.bestAvailableTitle,
      sourceUri: n.sourceUri,
      sourceFingerprint: n.sourceFingerprint,
      normalizationVersion: n.normalizationVersion,
      mappingVersion: n.mappingVersion,
      diagnostics: List.unmodifiable(n.diagnostics),
      displayDocument: DisplayDocument(
        documentId: d.documentId,
        sourceType: d.sourceType,
        sourceUri: d.sourceUri,
        title: d.title,
        normalizationVersion: d.normalizationVersion,
        metadata: Map.unmodifiable(d.metadata),
        assets: Map.unmodifiable(
          d.assets.map(
            (key, value) => MapEntry(
              key,
              DisplayAsset(
                assetId: value.assetId,
                kind: value.kind,
                resolvedUri: value.resolvedUri,
                mimeType: value.mimeType,
                metadata: Map.unmodifiable(value.metadata),
              ),
            ),
          ),
        ),
        blocks: List.unmodifiable(
          d.blocks.map(
            (b) => DisplayBlock(
              blockId: b.blockId,
              kind: b.kind,
              inlines: List.unmodifiable(
                b.inlines.map(
                  (i) => DisplayInline(
                    kind: i.kind,
                    text: i.text,
                    attributes: Map.unmodifiable(i.attributes),
                  ),
                ),
              ),
              attributes: Map.unmodifiable(b.attributes),
              assetId: b.assetId,
              parentBlockId: b.parentBlockId,
              ordinal: b.ordinal,
            ),
          ),
        ),
      ),
      speechDocument: SpeechDocument(
        documentId: s.documentId,
        sourceType: s.sourceType,
        languageTag: s.languageTag,
        totalWordCount: s.totalWordCount,
        normalizationVersion: s.normalizationVersion,
        segmentIndexById: Map.unmodifiable(s.segmentIndexById),
        segments: List.unmodifiable(
          s.segments.map(
            (v) => SpeechSegment(
              segmentId: v.segmentId,
              blockId: v.blockId,
              ordinal: v.ordinal,
              paragraphIndex: v.paragraphIndex,
              sentenceIndex: v.sentenceIndex,
              normalizedText: v.normalizedText,
              wordCount: v.wordCount,
              sourceRange: v.sourceRange,
              displayAnchor: v.displayAnchor,
              wordSpans: List.unmodifiable(v.wordSpans),
            ),
          ),
        ),
      ),
      positionMap: PositionMap(
        documentId: n.positionMap.documentId,
        mappingVersion: n.positionMap.mappingVersion,
        entries: List.unmodifiable(n.positionMap.entries),
      ),
    ),
    basePronunciationArtifacts: BasePronunciationArtifactSet(
      documentId: a.documentId,
      artifactVersion: a.artifactVersion,
      normalizationVersion: a.normalizationVersion,
      pronunciationProfileId: a.pronunciationProfileId,
      artifacts: List.unmodifiable(
        a.artifacts.map(
          (v) => PronunciationArtifact(
            artifactId: v.artifactId,
            segmentId: v.segmentId,
            startWord: v.startWord,
            endWord: v.endWord,
            surfaceText: v.surfaceText,
            normalizedSurfaceText: v.normalizedSurfaceText,
            artifactClass: v.artifactClass,
            source: v.source,
            confidence: v.confidence,
            representations: List.unmodifiable(v.representations),
            diagnosticCodes: List.unmodifiable(v.diagnosticCodes),
          ),
        ),
      ),
    ),
  );
}
