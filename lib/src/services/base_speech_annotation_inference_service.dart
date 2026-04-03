import '../models/display_document.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';

class BaseSpeechAnnotationInferenceService {
  const BaseSpeechAnnotationInferenceService();

  static const annotationVersion = 'read-aloud-annotations-v1';

  BaseSpeechAnnotationSet infer({
    required SpeechDocument speechDocument,
    required DisplayDocument displayDocument,
  }) {
    final blockById = {
      for (final block in displayDocument.blocks) block.blockId: block,
    };
    final annotations = <SpeechAnnotation>[];
    var ordinal = 0;

    for (var index = 0; index < speechDocument.segments.length; index += 1) {
      final segment = speechDocument.segments[index];
      final block = blockById[segment.blockId];
      final nextSegment = index + 1 < speechDocument.segments.length
          ? speechDocument.segments[index + 1]
          : null;

      for (final boundary in _inferWeakBoundaries(segment)) {
        annotations.add(
          SpeechAnnotation(
            annotationId: 'ann_${ordinal++}',
            segmentId: segment.segmentId,
            kind: SpeechAnnotationKind.phraseBoundary,
            startWord: boundary,
            endWord: boundary,
            confidence: 0.72,
            source: SpeechAnnotationSource.ruleBasedLinguisticInference,
            breakClass: BreakClass.weak,
          ),
        );
        annotations.add(
          SpeechAnnotation(
            annotationId: 'ann_${ordinal++}',
            segmentId: segment.segmentId,
            kind: SpeechAnnotationKind.pauseCandidate,
            startWord: boundary,
            endWord: boundary,
            confidence: 0.7,
            source: SpeechAnnotationSource.ruleBasedLinguisticInference,
            breakClass: BreakClass.weak,
          ),
        );
      }

      for (final emphasis in _inferEmphasisCandidates(segment)) {
        annotations.add(
          SpeechAnnotation(
            annotationId: 'ann_${ordinal++}',
            segmentId: segment.segmentId,
            kind: SpeechAnnotationKind.emphasisCandidate,
            startWord: emphasis.startWord,
            endWord: emphasis.endWord,
            confidence: emphasis.confidence,
            source: emphasis.source,
          ),
        );
      }

      final trailingBreakClass = _trailingBreakClass(
        block: block,
        segment: segment,
        nextSegment: nextSegment,
      );
      annotations.add(
        SpeechAnnotation(
          annotationId: 'ann_${ordinal++}',
          segmentId: segment.segmentId,
          kind: SpeechAnnotationKind.pauseCandidate,
          startWord: segment.wordCount,
          endWord: segment.wordCount,
          confidence: 0.9,
          source: SpeechAnnotationSource.importerStructuralInference,
          breakClass: trailingBreakClass,
        ),
      );

      final discourseRole = _discourseRole(segment, block);
      if (segment.wordCount > 0) {
        annotations.add(
          SpeechAnnotation(
            annotationId: 'ann_${ordinal++}',
            segmentId: segment.segmentId,
            kind: SpeechAnnotationKind.discourseRole,
            startWord: 0,
            endWord: segment.wordCount,
            confidence: 0.75,
            source: SpeechAnnotationSource.ruleBasedLinguisticInference,
            discourseRole: discourseRole,
          ),
        );
      }

      for (final candidate in _inferPronunciationCandidates(segment)) {
        annotations.add(
          SpeechAnnotation(
            annotationId: 'ann_${ordinal++}',
            segmentId: segment.segmentId,
            kind: SpeechAnnotationKind.pronunciationCandidate,
            startWord: candidate.startWord,
            endWord: candidate.endWord,
            confidence: candidate.confidence,
            source: candidate.source,
            pronunciationCandidate: candidate.payload,
          ),
        );

        final sayAsClass = _sayAsClassForPronunciationCandidate(candidate);
        if (sayAsClass != null) {
          annotations.add(
            SpeechAnnotation(
              annotationId: 'ann_${ordinal++}',
              segmentId: segment.segmentId,
              kind: SpeechAnnotationKind.sayAsCandidate,
              startWord: candidate.startWord,
              endWord: candidate.endWord,
              confidence: candidate.confidence,
              source: candidate.source,
              sayAsClass: sayAsClass,
            ),
          );
        }
      }
    }

    return BaseSpeechAnnotationSet(
      documentId: speechDocument.documentId,
      annotationVersion: annotationVersion,
      annotations: annotations,
    );
  }
}

Iterable<int> _inferWeakBoundaries(SpeechSegment segment) sync* {
  for (final span in segment.wordSpans) {
    final token = span.text;
    if (token.endsWith(',') || token.endsWith(';') || token.endsWith(':')) {
      yield span.wordIndexWithinSegment + 1;
    }
  }
}

BreakClass _trailingBreakClass({
  required DisplayBlock? block,
  required SpeechSegment segment,
  required SpeechSegment? nextSegment,
}) {
  if (block?.kind == DisplayBlockKind.heading) {
    return BreakClass.section;
  }
  if (nextSegment == null) {
    return BreakClass.paragraph;
  }
  if (nextSegment.paragraphIndex != segment.paragraphIndex) {
    return BreakClass.paragraph;
  }
  return BreakClass.sentence;
}

String _discourseRole(SpeechSegment segment, DisplayBlock? block) {
  if (block?.kind == DisplayBlockKind.heading) {
    return 'heading';
  }
  if (block?.kind == DisplayBlockKind.listItem) {
    return 'list_item';
  }
  if (block?.attributes['role'] == 'caption') {
    return 'caption';
  }
  if (block?.kind == DisplayBlockKind.blockquote) {
    return 'quotation';
  }
  final text = segment.normalizedText;
  if (_looksLikeDialogue(text)) {
    return 'dialogue';
  }
  if (_containsQuotation(text)) {
    return 'quotation';
  }
  return 'narration';
}

Iterable<_PronunciationCandidateMatch> _inferPronunciationCandidates(
  SpeechSegment segment,
) sync* {
  for (final span in segment.wordSpans) {
    final surface = span.text.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
    if (surface.isEmpty) {
      continue;
    }

    if (RegExp(r'^[A-Z]{2,}$').hasMatch(surface)) {
      yield _PronunciationCandidateMatch(
        startWord: span.wordIndexWithinSegment,
        endWord: span.wordIndexWithinSegment + 1,
        confidence: 0.82,
        source: SpeechAnnotationSource.ruleBasedLinguisticInference,
        payload: PronunciationCandidatePayload(
          surfaceText: span.text,
          normalizedSurfaceText: surface.toLowerCase(),
          representationType: 'say_as_class',
          representationValue: 'letters',
          accentFamily: null,
          priorityHint: 80,
        ),
      );
      continue;
    }

    if (RegExp(r'^\d+$').hasMatch(surface)) {
      yield _PronunciationCandidateMatch(
        startWord: span.wordIndexWithinSegment,
        endWord: span.wordIndexWithinSegment + 1,
        confidence: 0.78,
        source: SpeechAnnotationSource.ruleBasedLinguisticInference,
        payload: PronunciationCandidatePayload(
          surfaceText: span.text,
          normalizedSurfaceText: surface,
          representationType: 'say_as_class',
          representationValue: 'cardinal',
          accentFamily: null,
          priorityHint: 70,
        ),
      );
      continue;
    }

    if (surface.contains('&')) {
      yield _PronunciationCandidateMatch(
        startWord: span.wordIndexWithinSegment,
        endWord: span.wordIndexWithinSegment + 1,
        confidence: 0.65,
        source: SpeechAnnotationSource.ruleBasedLinguisticInference,
        payload: PronunciationCandidatePayload(
          surfaceText: span.text,
          normalizedSurfaceText: surface.toLowerCase(),
          representationType: 'normalized_spoken_text',
          representationValue: surface.replaceAll('&', 'and').toLowerCase(),
          accentFamily: null,
          priorityHint: 45,
        ),
      );
    }
  }
}

Iterable<_EmphasisCandidateMatch> _inferEmphasisCandidates(
  SpeechSegment segment,
) sync* {
  final uppercaseRanges = <_EmphasisCandidateMatch>[];
  int? startWord;
  var wordCount = 0;
  final isExclamatory = segment.normalizedText.contains('!');

  void flushRange(int nextWordIndex) {
    final rangeStart = startWord;
    if (rangeStart == null) {
      return;
    }
    final rangeLength = nextWordIndex - rangeStart;
    if (rangeLength >= 2 || (isExclamatory && rangeLength >= 1)) {
      uppercaseRanges.add(
        _EmphasisCandidateMatch(
          startWord: rangeStart,
          endWord: nextWordIndex,
          confidence: isExclamatory ? 0.82 : 0.74,
          source: SpeechAnnotationSource.ruleBasedLinguisticInference,
        ),
      );
    }
    startWord = null;
  }

  for (final span in segment.wordSpans) {
    wordCount = span.wordIndexWithinSegment + 1;
    final surface = span.text.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
    final isUppercaseWord = RegExp(r'^[A-Z]{2,}$').hasMatch(surface);
    if (isUppercaseWord) {
      startWord ??= span.wordIndexWithinSegment;
      continue;
    }
    flushRange(span.wordIndexWithinSegment);
  }
  flushRange(wordCount);

  if (uppercaseRanges.isNotEmpty) {
    yield* uppercaseRanges;
    return;
  }

  if (isExclamatory && segment.wordCount > 0) {
    yield _EmphasisCandidateMatch(
      startWord: 0,
      endWord: segment.wordCount,
      confidence: 0.68,
      source: SpeechAnnotationSource.ruleBasedLinguisticInference,
    );
  }
}

String? _sayAsClassForPronunciationCandidate(
  _PronunciationCandidateMatch candidate,
) {
  if (candidate.payload.representationType != 'say_as_class') {
    return null;
  }
  final sayAsClass = candidate.payload.representationValue.trim();
  return supportedSayAsClasses.contains(sayAsClass) ? sayAsClass : null;
}

bool _looksLikeDialogue(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final startsWithQuote = RegExp(r'^[\"“‘]').hasMatch(trimmed);
  final endsWithQuote = RegExp(r'[\"”’][.!?,;:]*$').hasMatch(trimmed);
  return startsWithQuote && endsWithQuote;
}

bool _containsQuotation(String text) {
  return RegExp(r'[\"“”]').hasMatch(text);
}

class _PronunciationCandidateMatch {
  const _PronunciationCandidateMatch({
    required this.startWord,
    required this.endWord,
    required this.confidence,
    required this.source,
    required this.payload,
  });

  final int startWord;
  final int endWord;
  final double confidence;
  final SpeechAnnotationSource source;
  final PronunciationCandidatePayload payload;
}

class _EmphasisCandidateMatch {
  const _EmphasisCandidateMatch({
    required this.startWord,
    required this.endWord,
    required this.confidence,
    required this.source,
  });

  final int startWord;
  final int endWord;
  final double confidence;
  final SpeechAnnotationSource source;
}
