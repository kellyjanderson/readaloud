import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'character_cast_registry.dart';
import 'dialogue_attribution.dart';
import 'display_document.dart';
import 'import_diagnostic.dart';
import 'normalized_import_result.dart';
import 'position_map.dart';
import 'pronunciation_artifact.dart';
import 'speech_annotation.dart';
import 'speech_document.dart';
import '../services/base_speech_annotation_inference_service.dart';
import '../services/document_time_pronunciation_planner_service.dart';
import '../services/display_document_html_renderer.dart';
import '../services/english_pronunciation_profile_selector.dart';
import '../services/english_suffix_allomorph_module.dart';
import '../services/character_cast_registry_service.dart';
import '../services/pronunciation_resource_layering_service.dart';
import '../services/speaker_attribution_service.dart';

enum ReaderDocumentType { sample, plainText, html, epub, pdf, unsupported }

enum ReaderAttachmentType { image, audio, video, other }

enum ReaderDocumentPresentation { html, pdf }

class ReaderAttachment {
  const ReaderAttachment({
    required this.label,
    required this.type,
    this.source,
  });

  final String label;
  final ReaderAttachmentType type;
  final String? source;
}

class WordSpan {
  const WordSpan({required this.start, required this.end});

  final int start;
  final int end;
}

class ReaderDocument {
  ReaderDocument._({
    required this.title,
    required this.type,
    required this.displayHtml,
    required this.speakableText,
    required this.normalizedImportResult,
    required this.baseSpeechAnnotations,
    required this.dialogueAttributions,
    required this.characterCastRegistry,
    required this.basePronunciationArtifacts,
    this.presentation = ReaderDocumentPresentation.html,
    this.pdfData,
    this.sourceDescription,
    this.attachments = const <ReaderAttachment>[],
  }) : assert(
         presentation != ReaderDocumentPresentation.pdf || pdfData != null,
         'PDF presentation requires pdfData.',
       ),
       wordSpans = _buildWordSpans(speakableText);

  factory ReaderDocument.fromNormalized({
    required String title,
    required ReaderDocumentType type,
    required NormalizedImportResult normalizedImportResult,
    required BaseSpeechAnnotationSet baseSpeechAnnotations,
    required DialogueAttributionSet dialogueAttributions,
    required CharacterCastRegistry characterCastRegistry,
    required BasePronunciationArtifactSet basePronunciationArtifacts,
    ReaderDocumentPresentation presentation = ReaderDocumentPresentation.html,
    Uint8List? pdfData,
    String? sourceDescription,
    List<ReaderAttachment> attachments = const <ReaderAttachment>[],
  }) {
    final displayHtml = renderDisplayDocumentToHtml(
      normalizedImportResult.displayDocument,
    );
    final speakableText = _flattenSpeechDocument(
      normalizedImportResult.speechDocument,
    );
    return ReaderDocument._(
      title: title,
      type: type,
      displayHtml: displayHtml,
      speakableText: speakableText,
      normalizedImportResult: normalizedImportResult,
      baseSpeechAnnotations: baseSpeechAnnotations,
      dialogueAttributions: dialogueAttributions,
      characterCastRegistry: characterCastRegistry,
      basePronunciationArtifacts: basePronunciationArtifacts,
      presentation: presentation,
      pdfData: pdfData,
      sourceDescription: sourceDescription,
      attachments: attachments,
    );
  }

  final String title;
  final ReaderDocumentType type;
  final String displayHtml;
  final String speakableText;
  final NormalizedImportResult normalizedImportResult;
  DisplayDocument get displayDocument => normalizedImportResult.displayDocument;
  SpeechDocument get speechDocument => normalizedImportResult.speechDocument;
  PositionMap get positionMap => normalizedImportResult.positionMap;
  List<ImportDiagnostic> get diagnostics => normalizedImportResult.diagnostics;
  final BaseSpeechAnnotationSet baseSpeechAnnotations;
  final DialogueAttributionSet dialogueAttributions;
  final CharacterCastRegistry characterCastRegistry;
  final BasePronunciationArtifactSet basePronunciationArtifacts;
  final ReaderDocumentPresentation presentation;
  final Uint8List? pdfData;
  final String? sourceDescription;
  final List<ReaderAttachment> attachments;
  final List<WordSpan> wordSpans;

  int get wordCount => wordSpans.length;

  int charOffsetForWord(int wordIndex) {
    if (wordSpans.isEmpty) return 0;
    final clamped = wordIndex.clamp(0, wordSpans.length - 1);
    return wordSpans[clamped].start;
  }

  int wordIndexForOffset(int offset) {
    if (wordSpans.isEmpty) return 0;
    var low = 0;
    var high = wordSpans.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final span = wordSpans[mid];
      if (offset < span.start) {
        high = mid - 1;
      } else if (offset > span.end) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return math.max(0, math.min(low, wordSpans.length - 1));
  }

  SpeechSegment? segmentForWordIndex(int wordIndex) {
    if (speechDocument.segments.isEmpty) {
      return null;
    }
    var runningWordCount = 0;
    for (final segment in speechDocument.segments) {
      final nextCount = runningWordCount + segment.wordCount;
      if (wordIndex < nextCount) {
        return segment;
      }
      runningWordCount = nextCount;
    }
    return speechDocument.segments.last;
  }

  int startWordIndexForSegmentId(String segmentId) {
    var runningWordCount = 0;
    for (final segment in speechDocument.segments) {
      if (segment.segmentId == segmentId) {
        return runningWordCount;
      }
      runningWordCount += segment.wordCount;
    }
    return math.max(0, wordCount - 1);
  }

  int startWordIndexForSegment(SpeechSegment segment) {
    return startWordIndexForSegmentId(segment.segmentId);
  }

  static ReaderDocument sample() {
    const sampleTitle = 'For Probe';
    const sampleParagraphs = <String>[
      'Short phrases for tracing how "for" is realized by the TTS pipeline.',
      'for the road.',
      'I waited for them.',
      'I am sorry for taking your starting position on the football team.',
      'my feelings for John are undeniable.',
      'for better or worse.',
      'for now.',
    ];
    const documentId = 'doc_sample';
    const normalizationVersion = 'read-aloud-normalization-v1';
    final displayDocument = DisplayDocument(
      documentId: documentId,
      sourceType: ReaderDocumentType.sample.name,
      sourceUri: null,
      title: sampleTitle,
      normalizationVersion: normalizationVersion,
      metadata: const <String, String>{
        'sample': 'true',
        'source': 'For pronunciation probe',
      },
      assets: const <String, DisplayAsset>{},
      blocks: [
        for (var i = 0; i < sampleParagraphs.length; i += 1)
          DisplayBlock(
            blockId: 'b_$i',
            kind: DisplayBlockKind.paragraph,
            inlines: [
              DisplayInline(
                kind: DisplayInlineKind.text,
                text: sampleParagraphs[i],
                attributes: const <String, String>{},
              ),
            ],
            attributes: const <String, String>{},
            assetId: null,
            parentBlockId: null,
            ordinal: i,
          ),
      ],
    );
    final sampleSegments = <SpeechSegment>[
      for (var i = 0; i < sampleParagraphs.length; i += 1)
        _segmentForSample(
          segmentId: 's_$i',
          blockId: 'b_$i',
          paragraphIndex: i,
          sentenceIndex: 0,
          ordinal: i,
          text: sampleParagraphs[i],
        ),
    ];
    final speechDocument = SpeechDocument(
      documentId: documentId,
      sourceType: ReaderDocumentType.sample.name,
      languageTag: 'en-US',
      segments: sampleSegments,
      segmentIndexById: {
        for (var i = 0; i < sampleSegments.length; i += 1)
          sampleSegments[i].segmentId: i,
      },
      totalWordCount: sampleSegments.fold<int>(
        0,
        (sum, segment) => sum + segment.wordCount,
      ),
      normalizationVersion: normalizationVersion,
    );
    final positionMap = PositionMap(
      documentId: documentId,
      mappingVersion: normalizationVersion,
      entries: sampleSegments
          .map(
            (segment) => PositionMapEntry(
              entryId: 'pm_${segment.ordinal}',
              displayBlockId: segment.blockId,
              speechSegmentId: segment.segmentId,
              displayStart: 0,
              displayEnd: segment.normalizedText.length,
              speechStartWord: 0,
              speechEndWord: segment.wordCount,
              confidence: 0.8,
              recoveryAnchor: RecoveryAnchor(exact: segment.normalizedText),
            ),
          )
          .toList(growable: false),
    );

    final normalizedImportResult = NormalizedImportResult(
      documentId: documentId,
      sourceType: ReaderDocumentType.sample.name,
      bestAvailableTitle: sampleTitle,
      sourceUri: null,
      sourceFingerprint: 'sample-document',
      normalizationVersion: normalizationVersion,
      mappingVersion: normalizationVersion,
      displayDocument: displayDocument,
      speechDocument: speechDocument,
      positionMap: positionMap,
    );
    const annotationInferenceService = BaseSpeechAnnotationInferenceService();
    const speakerAttributionService = SpeakerAttributionService();
    const characterCastRegistryService = CharacterCastRegistryService();
    const pronunciationProfileSelector = EnglishPronunciationProfileSelector();
    const pronunciationResourceLayeringService =
        PronunciationResourceLayeringService();
    const pronunciationPlannerService =
        DocumentTimePronunciationPlannerService();

    final baseSpeechAnnotations = annotationInferenceService.infer(
      speechDocument: speechDocument,
      displayDocument: displayDocument,
    );
    final dialogueAttributions = speakerAttributionService.attribute(
      speechDocument: speechDocument,
      baseAnnotations: baseSpeechAnnotations,
    );
    final characterCastRegistry = characterCastRegistryService.build(
      dialogueAttributions: dialogueAttributions,
    );
    final selectedProfile = pronunciationProfileSelector.select(
      const EnglishPronunciationProfileSelectionInput(engineId: 'kokoro'),
    );
    final mergedPronunciationResources = pronunciationResourceLayeringService
        .merge(PronunciationResourceLayeringInput(profile: selectedProfile));
    final basePronunciationArtifacts = pronunciationPlannerService.plan(
      DocumentTimePronunciationPlannerInput(
        speechDocument: speechDocument,
        baseAnnotations: baseSpeechAnnotations,
        positionMap: positionMap,
        normalizationVersion: normalizationVersion,
        selectedProfile: selectedProfile,
        mergedPronunciationResources: mergedPronunciationResources,
        enabledDocumentTimeRuleModules: const <EnglishSuffixAllomorphModule>[
          EnglishSuffixAllomorphModule(),
        ],
        diagnostics: normalizedImportResult.diagnostics,
      ),
    );

    return ReaderDocument.fromNormalized(
      title: sampleTitle,
      type: ReaderDocumentType.sample,
      normalizedImportResult: normalizedImportResult,
      baseSpeechAnnotations: baseSpeechAnnotations,
      dialogueAttributions: dialogueAttributions,
      characterCastRegistry: characterCastRegistry,
      basePronunciationArtifacts: basePronunciationArtifacts,
      sourceDescription: 'Bundled project sample',
      attachments: const <ReaderAttachment>[],
    );
  }
}

SpeechSegment _segmentForSample({
  required String segmentId,
  required String blockId,
  required int paragraphIndex,
  required int sentenceIndex,
  required int ordinal,
  required String text,
}) {
  final words = RegExp(r'\S+').allMatches(text).toList(growable: false);
  return SpeechSegment(
    segmentId: segmentId,
    blockId: blockId,
    ordinal: ordinal,
    paragraphIndex: paragraphIndex,
    sentenceIndex: sentenceIndex,
    normalizedText: text,
    wordCount: words.length,
    sourceRange: null,
    displayAnchor: DisplayAnchor(
      blockId: blockId,
      startInlineOffset: 0,
      endInlineOffset: text.length,
    ),
    wordSpans: [
      for (var i = 0; i < words.length; i += 1)
        SpeechWordSpan(
          wordIndexWithinSegment: i,
          startUtf16: words[i].start,
          endUtf16: words[i].end,
          text: words[i].group(0)!,
        ),
    ],
  );
}

List<WordSpan> _buildWordSpans(String text) {
  final matches = RegExp(r'\S+').allMatches(text);
  return matches
      .map((match) => WordSpan(start: match.start, end: match.end))
      .toList(growable: false);
}

String _flattenSpeechDocument(SpeechDocument document) {
  if (document.segments.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  int? lastParagraphIndex;
  for (final segment in document.segments) {
    if (buffer.isNotEmpty) {
      if (lastParagraphIndex != null &&
          segment.paragraphIndex != lastParagraphIndex) {
        buffer.write('\n\n');
      } else {
        buffer.write(' ');
      }
    }
    buffer.write(segment.normalizedText.trim());
    lastParagraphIndex = segment.paragraphIndex;
  }
  return buffer.toString().trim();
}

String plainTextToHtml(String text) {
  final paragraphs = text.trim().isEmpty
      ? const <String>[]
      : text
            .trim()
            .split(RegExp(r'\n\s*\n'))
            .map((block) => block.trim())
            .where((block) => block.isNotEmpty)
            .map((block) => '<p>${const HtmlEscape().convert(block)}</p>')
            .toList(growable: false);

  return '<article>${paragraphs.join('\n')}</article>';
}
