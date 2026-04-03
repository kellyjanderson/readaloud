class SpeechDocument {
  const SpeechDocument({
    required this.documentId,
    required this.sourceType,
    required this.languageTag,
    required this.segments,
    required this.segmentIndexById,
    required this.totalWordCount,
    required this.normalizationVersion,
  });

  final String documentId;
  final String sourceType;
  final String languageTag;
  final List<SpeechSegment> segments;
  final Map<String, int> segmentIndexById;
  final int totalWordCount;
  final String normalizationVersion;
}

class SpeechSegment {
  const SpeechSegment({
    required this.segmentId,
    required this.blockId,
    required this.ordinal,
    required this.paragraphIndex,
    required this.sentenceIndex,
    required this.normalizedText,
    required this.wordCount,
    required this.sourceRange,
    required this.displayAnchor,
    required this.wordSpans,
  });

  final String segmentId;
  final String blockId;
  final int ordinal;
  final int paragraphIndex;
  final int sentenceIndex;
  final String normalizedText;
  final int wordCount;
  final SourceRange? sourceRange;
  final DisplayAnchor? displayAnchor;
  final List<SpeechWordSpan> wordSpans;
}

class SourceRange {
  const SourceRange({
    required this.startOffset,
    required this.endOffset,
    required this.coordinateSpace,
  });

  final int startOffset;
  final int endOffset;
  final String coordinateSpace;
}

class DisplayAnchor {
  const DisplayAnchor({
    required this.blockId,
    required this.startInlineOffset,
    required this.endInlineOffset,
  });

  final String blockId;
  final int startInlineOffset;
  final int endInlineOffset;
}

class SpeechWordSpan {
  const SpeechWordSpan({
    required this.wordIndexWithinSegment,
    required this.startUtf16,
    required this.endUtf16,
    required this.text,
  });

  final int wordIndexWithinSegment;
  final int startUtf16;
  final int endUtf16;
  final String text;
}
