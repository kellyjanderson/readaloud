import '../models/display_document.dart';
import '../models/position_map.dart';
import '../models/speech_document.dart';
import '../models/spoken_selection.dart';
import 'tts_engine.dart';

class SpokenSelectionMapperInput {
  const SpokenSelectionMapperInput({
    required this.displayDocument,
    required this.speechDocument,
    required this.positionMap,
    required this.progress,
  });

  final DisplayDocument displayDocument;
  final SpeechDocument speechDocument;
  final PositionMap positionMap;
  final TtsProgressUpdate progress;
}

class SpokenSelectionMapperService {
  const SpokenSelectionMapperService();

  SpokenSelection map(SpokenSelectionMapperInput input) {
    final segment = _segmentForProgress(
      speechDocument: input.speechDocument,
      progress: input.progress,
    );
    if (segment == null) {
      return const SpokenSelection.none();
    }

    PositionMapEntry? entry;
    for (final candidate in input.positionMap.entries) {
      if (candidate.speechSegmentId == segment.segmentId) {
        entry = candidate;
        break;
      }
    }

    DisplayBlock? block;
    for (final candidate in input.displayDocument.blocks) {
      if (candidate.blockId == segment.blockId) {
        block = candidate;
        break;
      }
    }

    final segmentStartWordIndex = _startWordIndexForSegment(
      input.speechDocument,
      segment.segmentId,
    );
    final segmentEndWordIndex = segmentStartWordIndex + segment.wordCount;

    final wordStartIndex = input.progress.wordStartIndex;
    final wordEndIndex = input.progress.wordEndIndex;
    if (entry != null &&
        block != null &&
        wordStartIndex != null &&
        wordEndIndex != null) {
      final localStart = wordStartIndex - segmentStartWordIndex;
      final localEndExclusive = wordEndIndex - segmentStartWordIndex;
      if (localStart >= 0 &&
          localEndExclusive > localStart &&
          localEndExclusive <= segment.wordSpans.length) {
        final startSpan = segment.wordSpans[localStart];
        final endSpan = segment.wordSpans[localEndExclusive - 1];
        final displayBase =
            segment.displayAnchor?.startInlineOffset ?? entry.displayStart;
        return SpokenSelection(
          precision: SpokenSelectionPrecision.word,
          confidence: entry.confidence,
          segmentId: segment.segmentId,
          displayBlockId: entry.displayBlockId,
          displayStart: displayBase + startSpan.startUtf16,
          displayEnd: displayBase + endSpan.endUtf16,
          speechStartWordIndex: wordStartIndex,
          speechEndWordIndex: wordEndIndex,
          voiceId: input.progress.voiceId,
          routeId: input.progress.routeId,
          castId: input.progress.castId,
          dialogueSpanId: input.progress.dialogueSpanId,
        );
      }
    }

    if (entry != null) {
      return SpokenSelection(
        precision: SpokenSelectionPrecision.segment,
        confidence: entry.confidence,
        segmentId: segment.segmentId,
        displayBlockId: entry.displayBlockId,
        displayStart: entry.displayStart,
        displayEnd: entry.displayEnd,
        speechStartWordIndex: segmentStartWordIndex,
        speechEndWordIndex: segmentEndWordIndex,
        voiceId: input.progress.voiceId,
        routeId: input.progress.routeId,
        castId: input.progress.castId,
        dialogueSpanId: input.progress.dialogueSpanId,
      );
    }

    if (block != null) {
      return SpokenSelection(
        precision: SpokenSelectionPrecision.block,
        confidence: 0.25,
        segmentId: segment.segmentId,
        displayBlockId: block.blockId,
        displayStart: 0,
        displayEnd: block.plainText.length,
        speechStartWordIndex: segmentStartWordIndex,
        speechEndWordIndex: segmentEndWordIndex,
        voiceId: input.progress.voiceId,
        routeId: input.progress.routeId,
        castId: input.progress.castId,
        dialogueSpanId: input.progress.dialogueSpanId,
      );
    }

    return const SpokenSelection.none();
  }

  SpeechSegment? _segmentForProgress({
    required SpeechDocument speechDocument,
    required TtsProgressUpdate progress,
  }) {
    final explicitSegmentId = progress.segmentId;
    if (explicitSegmentId != null) {
      final index = speechDocument.segmentIndexById[explicitSegmentId];
      if (index != null) {
        return speechDocument.segments[index];
      }
    }

    final wordIndex = progress.wordStartIndex;
    if (wordIndex == null) {
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
    return speechDocument.segments.isEmpty ? null : speechDocument.segments.last;
  }
}

int _startWordIndexForSegment(SpeechDocument speechDocument, String segmentId) {
  var runningWordCount = 0;
  for (final segment in speechDocument.segments) {
    if (segment.segmentId == segmentId) {
      return runningWordCount;
    }
    runningWordCount += segment.wordCount;
  }
  return 0;
}
