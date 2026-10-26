import 'dart:convert';
import 'dart:typed_data';

import '../models/character_cast_registry.dart';
import '../models/dialogue_attribution.dart';
import '../models/display_document.dart';
import '../models/document_voice_attribution.dart';
import '../models/import_diagnostic.dart';
import '../models/normalized_import_result.dart';
import '../models/position_map.dart';
import '../models/pronunciation_artifact.dart';
import '../models/reader_document.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';
import '../models/voice_profile.dart';
import 'prepared_document_snapshot.dart';

Map<String, dynamic> _map(dynamic v) => (v as Map).cast<String, dynamic>();
List<Map<String, dynamic>> _rows(dynamic v) => (v as List).map(_map).toList();
Map<String, String> _strings(dynamic v) => (v as Map).cast<String, String>();
List<String> _list(dynamic v) => (v as List).cast<String>();
T _enum<T extends Enum>(List<T> values, dynamic v) =>
    values.byName(v as String);
double _number(dynamic v) => (v as num).toDouble();
Uri? _uri(dynamic v) => v == null ? null : Uri.parse(v as String);

/// V1 remains readable; unknown future schemas fail closed. Derived artifacts
/// are decoded as data, never recreated by analysis on the opening isolate.
ReaderDocument decodeReaderDocument(String source) {
  try {
    final m = _map(jsonDecode(source));
    if (m['formatId'] != 'read-aloud-document' ||
        !const ['radoc-v1', 'radoc-v2'].contains(m['formatVersion'])) {
      throw const FormatException('Unsupported radoc schema');
    }
    final n = _map(m['normalizedImportResult']);
    final d = _map(m['displayDocument']);
    final s = _map(m['speechDocument']);
    final p = _map(m['positionMap']);
    final a = _map(m['baseSpeechAnnotations']);
    final t = _map(m['dialogueAttributions']);
    final c = _map(m['characterCastRegistry']);
    final v = _map(m['documentVoiceAttribution']);
    final r = _map(m['basePronunciationArtifacts']);
    final documentId = n['documentId'] as String;
    for (final graph in [d, s, p, a, t, c, v, r]) {
      if (graph['documentId'] != documentId) {
        throw const FormatException('Mismatched graph document identity');
      }
    }
    if (d['sourceType'] != n['sourceType'] ||
        s['sourceType'] != n['sourceType'] ||
        d['title'] != n['bestAvailableTitle'] ||
        d['sourceUri'] != n['sourceUri'] ||
        d['normalizationVersion'] != n['normalizationVersion'] ||
        s['normalizationVersion'] != n['normalizationVersion'] ||
        r['normalizationVersion'] != n['normalizationVersion'] ||
        p['mappingVersion'] != n['mappingVersion']) {
      throw const FormatException('Inconsistent derived dependency versions');
    }
    final display = DisplayDocument(
      documentId: documentId,
      sourceType: d['sourceType'],
      sourceUri: _uri(d['sourceUri']),
      title: d['title'],
      normalizationVersion: d['normalizationVersion'],
      metadata: _strings(d['metadata']),
      assets: _map(d['assets']).map((k, value) {
        final x = _map(value);
        return MapEntry(
          k,
          DisplayAsset(
            assetId: x['assetId'],
            kind: _enum(DisplayAssetKind.values, x['kind']),
            resolvedUri: Uri.parse(x['resolvedUri']),
            mimeType: x['mimeType'],
            metadata: _strings(x['metadata']),
          ),
        );
      }),
      blocks: _rows(d['blocks'])
          .map(
            (x) => DisplayBlock(
              blockId: x['blockId'],
              kind: _enum(DisplayBlockKind.values, x['kind']),
              ordinal: x['ordinal'],
              assetId: x['assetId'],
              parentBlockId: x['parentBlockId'],
              attributes: _strings(x['attributes']),
              inlines: _rows(x['inlines'])
                  .map(
                    (i) => DisplayInline(
                      kind: _enum(DisplayInlineKind.values, i['kind']),
                      text: i['text'],
                      attributes: _strings(i['attributes']),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
    final speech = SpeechDocument(
      documentId: documentId,
      sourceType: s['sourceType'],
      languageTag: s['languageTag'],
      normalizationVersion: s['normalizationVersion'],
      totalWordCount: s['totalWordCount'],
      segmentIndexById: (s['segmentIndexById'] as Map).cast<String, int>(),
      segments: _rows(s['segments']).map((x) {
        final sr = x['sourceRange'] == null ? null : _map(x['sourceRange']);
        final da = x['displayAnchor'] == null ? null : _map(x['displayAnchor']);
        return SpeechSegment(
          segmentId: x['segmentId'],
          blockId: x['blockId'],
          ordinal: x['ordinal'],
          paragraphIndex: x['paragraphIndex'],
          sentenceIndex: x['sentenceIndex'],
          normalizedText: x['normalizedText'],
          wordCount: x['wordCount'],
          sourceRange: sr == null
              ? null
              : SourceRange(
                  startOffset: sr['startOffset'],
                  endOffset: sr['endOffset'],
                  coordinateSpace: sr['coordinateSpace'],
                ),
          displayAnchor: da == null
              ? null
              : DisplayAnchor(
                  blockId: da['blockId'],
                  startInlineOffset: da['startInlineOffset'],
                  endInlineOffset: da['endInlineOffset'],
                ),
          wordSpans: _rows(x['wordSpans'])
              .map(
                (w) => SpeechWordSpan(
                  wordIndexWithinSegment: w['wordIndexWithinSegment'],
                  startUtf16: w['startUtf16'],
                  endUtf16: w['endUtf16'],
                  text: w['text'],
                ),
              )
              .toList(),
        );
      }).toList(),
    );
    final positionMap = PositionMap(
      documentId: documentId,
      mappingVersion: p['mappingVersion'],
      entries: _rows(p['entries']).map((x) {
        final ra = x['recoveryAnchor'] == null
            ? null
            : _map(x['recoveryAnchor']);
        final sa = x['sourceAnchor'] == null ? null : _map(x['sourceAnchor']);
        return PositionMapEntry(
          entryId: x['entryId'],
          displayBlockId: x['displayBlockId'],
          speechSegmentId: x['speechSegmentId'],
          displayStart: x['displayStart'],
          displayEnd: x['displayEnd'],
          speechStartWord: x['speechStartWord'],
          speechEndWord: x['speechEndWord'],
          confidence: _number(x['confidence']),
          recoveryAnchor: ra == null
              ? null
              : RecoveryAnchor(
                  exact: ra['exact'],
                  prefix: ra['prefix'],
                  suffix: ra['suffix'],
                ),
          sourceAnchor: sa == null
              ? null
              : switch (sa['kind']) {
                  'epub' => EpubSourceAnchor(
                    spineItemId: sa['spineItemId'],
                    cfi: sa['cfi'],
                  ),
                  'pdf' => PdfSourceAnchor(
                    pageIndex: sa['pageIndex'],
                    sourceBlockId: sa['sourceBlockId'],
                  ),
                  'html' => HtmlSourceAnchor(cssSelector: sa['cssSelector']),
                  _ => throw const FormatException('Unknown source anchor'),
                },
        );
      }).toList(),
    );
    final result = ReaderDocument.restored(
      title: m['title'],
      type: _enum(ReaderDocumentType.values, m['documentType']),
      displayHtml: m['displayHtml'],
      speakableText: m['speakableText'],
      presentation: _enum(ReaderDocumentPresentation.values, m['presentation']),
      pdfData: m['pdfDataBase64'] == null
          ? null
          : Uint8List.fromList(base64Decode(m['pdfDataBase64'])),
      sourceDescription: m['sourceDescription'],
      attachments: _rows(m['attachments'])
          .map(
            (x) => ReaderAttachment(
              label: x['label'],
              type: _enum(ReaderAttachmentType.values, x['type']),
              source: x['source'],
            ),
          )
          .toList(),
      normalizedImportResult: NormalizedImportResult(
        documentId: documentId,
        sourceType: n['sourceType'],
        bestAvailableTitle: n['bestAvailableTitle'],
        sourceUri: _uri(n['sourceUri']),
        sourceFingerprint: n['sourceFingerprint'],
        normalizationVersion: n['normalizationVersion'],
        mappingVersion: n['mappingVersion'],
        displayDocument: display,
        speechDocument: speech,
        positionMap: positionMap,
        diagnostics: _rows(n['diagnostics'])
            .map(
              (x) => ImportDiagnostic(
                severity: _enum(ImportDiagnosticSeverity.values, x['severity']),
                code: x['code'],
                message: x['message'],
                relatedBlockId: x['relatedBlockId'],
                sourceLocator: x['sourceLocator'],
              ),
            )
            .toList(),
      ),
      baseSpeechAnnotations: BaseSpeechAnnotationSet(
        documentId: documentId,
        annotationVersion: a['annotationVersion'],
        annotations: _rows(a['annotations']).map(_annotation).toList(),
      ),
      dialogueAttributions: DialogueAttributionSet(
        documentId: documentId,
        attributionVersion: t['attributionVersion'],
        providerId: t['providerId'],
        providerVersion: t['providerVersion'],
        outcomes: _rows(t['outcomes']).map((x) {
          final e = x['evidenceSpan'] == null ? null : _map(x['evidenceSpan']);
          final sr = x['speakerReference'] == null
              ? null
              : _map(x['speakerReference']);
          return DialogueAttributionOutcome(
            attributionId: x['attributionId'],
            dialogueSpanId: x['dialogueSpanId'],
            resolution: _enum(
              DialogueAttributionResolution.values,
              x['resolution'],
            ),
            confidence: _number(x['confidence']),
            provenance: _enum(
              DialogueAttributionProvenance.values,
              x['provenance'],
            ),
            ruleUsed: _enum(DialogueAttributionRule.values, x['ruleUsed']),
            evidenceSpan: e == null
                ? null
                : DialogueEvidenceSpan(
                    segmentId: e['segmentId'],
                    startUtf16: e['startUtf16'],
                    endUtf16: e['endUtf16'],
                    text: e['text'],
                  ),
            speakerReference: sr == null
                ? null
                : SpeakerReference(
                    referenceId: sr['referenceId'],
                    displayLabel: sr['displayLabel'],
                    normalizedLabel: sr['normalizedLabel'],
                  ),
          );
        }).toList(),
      ),
      characterCastRegistry: CharacterCastRegistry(
        documentId: documentId,
        registryVersion: c['registryVersion'],
        castIdRedirects: _strings(c['castIdRedirects'] ?? <String, String>{}),
        entries: _rows(c['entries'])
            .map(
              (x) => CastEntry(
                castId: x['castId'],
                roleKind: _enum(CastEntryRoleKind.values, x['roleKind']),
                displayLabel: x['displayLabel'],
                confidence: _number(x['confidence']),
                provenance: _enum(CastEntryProvenance.values, x['provenance']),
                observedAliases: _list(x['observedAliases']),
                attributionIds: _list(x['attributionIds']),
                identityProfile: x['identityProfile'] == null
                    ? null
                    : _profile(_map(x['identityProfile'])),
                inferredGender: x['inferredGender'] == null
                    ? null
                    : _enum(VoiceGender.values, x['inferredGender']),
                inferredGenderConfidence:
                    (x['inferredGenderConfidence'] as num?)?.toDouble(),
              ),
            )
            .toList(),
      ),
      documentVoiceAttribution: DocumentVoiceAttributionSet(
        documentId: documentId,
        attributionVersion: v['attributionVersion'],
        ranges: _rows(v['ranges'])
            .map(
              (x) => DocumentVoiceAttributionRange(
                rangeId: x['rangeId'],
                segmentIds: _list(x['segmentIds']),
                startSegmentId: x['startSegmentId'],
                endSegmentId: x['endSegmentId'],
                startWordIndex: x['startWordIndex'],
                endWordIndex: x['endWordIndex'],
                castId: x['castId'],
                kind: _enum(DocumentVoiceAttributionKind.values, x['kind']),
                dialogueSpanId: x['dialogueSpanId'],
              ),
            )
            .toList(),
      ),
      basePronunciationArtifacts: BasePronunciationArtifactSet(
        documentId: documentId,
        artifactVersion: r['artifactVersion'],
        normalizationVersion: r['normalizationVersion'],
        pronunciationProfileId: r['pronunciationProfileId'],
        artifacts: _rows(r['artifacts'])
            .map(
              (x) => PronunciationArtifact(
                artifactId: x['artifactId'],
                segmentId: x['segmentId'],
                startWord: x['startWord'],
                endWord: x['endWord'],
                surfaceText: x['surfaceText'],
                normalizedSurfaceText: x['normalizedSurfaceText'],
                artifactClass: _enum(
                  PronunciationArtifactClass.values,
                  x['artifactClass'],
                ),
                source: _enum(PronunciationArtifactSource.values, x['source']),
                confidence: _number(x['confidence']),
                diagnosticCodes: _list(x['diagnosticCodes']),
                representations: _rows(x['representations'])
                    .map(
                      (q) => PronunciationRepresentation(
                        representationId: q['representationId'],
                        representationType: q['representationType'],
                        representationValue: q['representationValue'],
                        accentFamily: q['accentFamily'],
                        priority: q['priority'],
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
    if (speech.segments.map((x) => x.segmentId).toSet().length !=
            speech.segments.length ||
        speech.totalWordCount !=
            speech.segments.fold<int>(0, (v, x) => v + x.wordCount)) {
      throw const FormatException('Invalid speech coverage');
    }
    for (var index = 0; index < speech.segments.length; index++) {
      final segment = speech.segments[index];
      if (speech.segmentIndexById[segment.segmentId] != index ||
          segment.wordCount != segment.wordSpans.length ||
          segment.wordSpans.any(
            (w) =>
                w.startUtf16 < 0 ||
                w.endUtf16 < w.startUtf16 ||
                w.endUtf16 > segment.normalizedText.length,
          )) {
        throw const FormatException('Invalid segment index or word coverage');
      }
    }
    if (speech.segmentIndexById.length != speech.segments.length ||
        result.wordCount != speech.totalWordCount ||
        positionMap.entries.any(
          (e) => !speech.segmentIndexById.containsKey(e.speechSegmentId),
        )) {
      throw const FormatException('Invalid snapshot coverage');
    }
    return freezePreparedDocument(result);
  } catch (error) {
    if (error is FormatException) rethrow;
    throw FormatException('Invalid radoc snapshot: $error');
  }
}

CharacterGenderIdentityLabel _label(dynamic v) =>
    _enum(CharacterGenderIdentityLabel.values, _camel(v as String));
CharacterGenderEvidenceSource _source(dynamic v) =>
    _enum(CharacterGenderEvidenceSource.values, _camel(v as String));
String _camel(String s) =>
    s.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());
CharacterIdentityProfile _profile(Map<String, dynamic> x) =>
    CharacterIdentityProfile(
      genderIdentityLabel: _label(x['genderIdentityLabel']),
      genderConfidence: _number(x['genderConfidence']),
      genderSource: _source(x['genderSource']),
      pronounProfile: CharacterPronounProfile(
        counts: (_map(x['pronounProfile'])['counts'] as Map)
            .cast<String, int>(),
      ),
      conflictFlag: x['conflictFlag'],
      countedSegmentIds: _list(x['countedSegmentIds'] ?? []),
      evidenceSpans: _rows(x['evidenceSpans'])
          .map(
            (e) => CharacterIdentityEvidenceSpan(
              segmentId: e['segmentId'],
              startUtf16: e['startUtf16'],
              endUtf16: e['endUtf16'],
              text: e['text'],
              source: _source(e['source'] ?? 'unknown'),
              genderIdentityLabel: e['genderIdentityLabel'] == null
                  ? null
                  : _label(e['genderIdentityLabel']),
            ),
          )
          .toList(),
    );
SpeechAnnotation _annotation(Map<String, dynamic> x) {
  final p = x['pronunciationCandidate'] == null
      ? null
      : _map(x['pronunciationCandidate']);
  return SpeechAnnotation(
    annotationId: x['annotationId'],
    segmentId: x['segmentId'],
    kind: _enum(SpeechAnnotationKind.values, x['kind']),
    startWord: x['startWord'],
    endWord: x['endWord'],
    confidence: _number(x['confidence']),
    source: _enum(SpeechAnnotationSource.values, x['source']),
    deliveryIntent: x['deliveryIntent'] == null
        ? null
        : _enum(DeliveryIntent.values, x['deliveryIntent']),
    inflectionIntent: x['inflectionIntent'] == null
        ? null
        : _enum(InflectionIntent.values, x['inflectionIntent']),
    breakClass: x['breakClass'] == null
        ? null
        : _enum(BreakClass.values, x['breakClass']),
    sayAsClass: x['sayAsClass'],
    discourseRole: x['discourseRole'],
    dialogueSpanId: x['dialogueSpanId'],
    dialogueSpanClass: x['dialogueSpanClass'],
    pronunciationCandidate: p == null
        ? null
        : PronunciationCandidatePayload(
            surfaceText: p['surfaceText'],
            normalizedSurfaceText: p['normalizedSurfaceText'],
            representationType: p['representationType'],
            representationValue: p['representationValue'],
            accentFamily: p['accentFamily'],
            priorityHint: p['priorityHint'],
          ),
  );
}
