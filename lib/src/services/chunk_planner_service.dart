import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../models/cast_aware_speech_route.dart';
import '../models/chunk_plan.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';
import '../models/speech_engine_catalog.dart';
import '../models/tts_artifact.dart';

class ChunkPlannerService {
  const ChunkPlannerService();

  static const _firstChunkSoftTargetWords = 16;
  static const _steadyChunkSoftTargetWords = 42;
  static const _hardChunkWordCap = 75;

  ChunkPlan plan(ChunkPlannerInput input) => ChunkPlannerGraph(
    input.speechDocument,
    input.castAwareSpeechRoutes,
  ).plan(input);
}

/// Document-wide indexes built once per retained immutable planning graph.
class ChunkPlannerGraph {
  ChunkPlannerGraph(this.document, this._routeSet)
    : _offsets = List.unmodifiable(_globalWordOffsets(document)),
      _routes = Map.unmodifiable(_routingContextBySegmentId(_routeSet));
  final SpeechDocument document;
  final List<int> _offsets;
  final Map<String, _ChunkRoutingContext> _routes;
  final CastAwareSpeechRouteSet? _routeSet;
  late final _wordRoutes = _rangesBySegmentId(_routeSet);
  late final bool _hasPartialRoutes =
      _routeSet?.ranges.any((range) {
        final first = document.segmentIndexById[range.startSegmentId];
        final last = document.segmentIndexById[range.endSegmentId];
        return first != null &&
            last != null &&
            (range.startWordIndex > _offsets[first] ||
                range.endWordIndex <
                    _offsets[last] + document.segments[last].wordCount);
      }) ??
      false;

  ChunkPlan plan(ChunkPlannerInput input, {int? endSegmentIndex}) {
    if (!identical(input.speechDocument, document)) {
      throw ArgumentError("Planning input does not belong to retained graph.");
    }
    final speechDocument = input.speechDocument;
    final startSegmentIndex =
        speechDocument.segmentIndexById[input.startSegmentId] ?? 0;
    var chunks = <ChunkSpec>[];
    final scenes =
        input.engineId == 'fish_drama3' &&
        input.engineVersion.endsWith('-q0-native-scene-v2');
    final globalWordOffsets = _offsets;
    final routingContextBySegmentId = _routes;

    final horizon = endSegmentIndex == null
        ? speechDocument.segments.length
        : (endSegmentIndex + 1).clamp(
            startSegmentIndex,
            speechDocument.segments.length,
          );
    var cursor = startSegmentIndex;
    final useChapterBoundaries =
        isDramaEngine(input.engineId) &&
        (input.fishSceneBoundaries.isNotEmpty || _hasPartialRoutes);
    if (useChapterBoundaries) {
      chunks = _planFishChapters(input, cursor, horizon, nativeScenes: scenes);
      if (chunks.isNotEmpty) cursor = chunks.last.endSegmentIndex + 1;
    }
    while (!useChapterBoundaries &&
        cursor < horizon &&
        (input.maxChunks == null ||
            chunks.length < input.maxChunks! * (scenes ? 16 : 1))) {
      final isFirstChunk = chunks.isEmpty;
      final softTarget = isFirstChunk
          ? ChunkPlannerService._firstChunkSoftTargetWords
          : ChunkPlannerService._steadyChunkSoftTargetWords;

      final built = _buildChunk(
        speechDocument: speechDocument,
        ttsArtifactSet: input.ttsArtifactSet,
        startSegmentIndex: cursor,
        globalWordOffsets: globalWordOffsets,
        softTarget: softTarget,
        endSegmentExclusive: horizon,
        fallbackVoiceId: input.voiceId,
        routingContextBySegmentId: routingContextBySegmentId,
      );
      chunks.add(
        _finalizeChunk(
          speechDocument: speechDocument,
          built: built,
          input: input,
          ordinal: chunks.length,
        ),
      );
      cursor = built.nextSegmentIndex;
    }

    if (scenes && !useChapterBoundaries) {
      chunks = packNativeSceneChunks(chunks);
      if (input.maxChunks != null) {
        chunks = chunks.take(input.maxChunks!).toList();
      }
      if (chunks.isNotEmpty) cursor = chunks.last.endSegmentIndex + 1;
    }
    final planDigest = crypto.sha256.convert(
      utf8.encode(
        [
          input.startSegmentId,
          input.voiceId,
          input.rate.toString(),
          input.engineId,
          input.engineVersion,
          chunks.map((chunk) => chunk.cacheKey).join('|'),
        ].join('::'),
      ),
    );

    return ChunkPlan(
      planId: 'plan_${planDigest.toString().substring(0, 16)}',
      chunks: chunks,
      nextSegmentId: cursor < speechDocument.segments.length
          ? speechDocument.segments[cursor].segmentId
          : null,
    );
  }

  List<ChunkSpec> _planFishChapters(
    ChunkPlannerInput input,
    int start,
    int horizon, {
    required bool nativeScenes,
  }) {
    final chunks = <ChunkSpec>[];
    var cursor = start;
    while (cursor < horizon &&
        (input.maxChunks == null || chunks.length < input.maxChunks!)) {
      final softTarget = chunks.isEmpty
          ? ChunkPlannerService._firstChunkSoftTargetWords
          : ChunkPlannerService._steadyChunkSoftTargetWords;
      final remainingChunks = input.maxChunks == null
          ? _fishTurnCap
          : input.maxChunks! - chunks.length;
      final parts = _fishSceneParts(
        input,
        cursor,
        horizon,
        softTarget: softTarget,
        turnBudget: nativeScenes ? _fishTurnCap : remainingChunks,
        firstChunk: chunks.isEmpty,
      );
      if (parts.isEmpty) break;
      final turns = <ChunkSpec>[];
      var first = 0;
      for (var i = 1; i <= parts.length; i++) {
        if (i < parts.length && _canShareFishTurn(parts[i - 1], parts[i])) {
          continue;
        }
        turns.add(
          _finalizeFishTurn(
            input,
            parts.sublist(first, i),
            ordinal: chunks.length + turns.length,
          ),
        );
        first = i;
      }
      if (nativeScenes) {
        chunks.add(_nativeScene(turns));
      } else {
        chunks.addAll(turns);
      }
      cursor = parts.last.segment.ordinal + 1;
    }
    return chunks;
  }

  List<_FishPart> _fishSceneParts(
    ChunkPlannerInput input,
    int start,
    int horizon, {
    required int softTarget,
    required int turnBudget,
    required bool firstChunk,
  }) {
    final parts = <_FishPart>[];
    var wordCount = 0;
    var turnCount = 0;
    var safeCut = 0;
    for (var i = start; i < horizon; i++) {
      final segment = document.segments[i];
      if (parts.isNotEmpty) {
        final boundary =
            input.fishSceneBoundaries[segment.segmentId] ??
            _sourceBoundary(parts.last.segment, segment);
        if (boundary == FishSceneBoundary.chapter ||
            boundary == FishSceneBoundary.sourceRange ||
            (boundary == FishSceneBoundary.paragraph &&
                wordCount * 2 >= softTarget) ||
            (boundary == FishSceneBoundary.sentence &&
                wordCount >= softTarget)) {
          break;
        }
        if (boundary != FishSceneBoundary.continuation) safeCut = parts.length;
      }
      final additions = _fishParts(input, segment, _offsets[i]);
      var candidateTurns = turnCount;
      _FishPart? previous = parts.lastOrNull;
      for (final part in additions) {
        if (previous == null || !_canShareFishTurn(previous, part)) {
          ++candidateTurns;
        }
        previous = part;
      }
      if (wordCount + segment.wordCount >
              ChunkPlannerService._hardChunkWordCap ||
          candidateTurns > _fishTurnCap) {
        if (parts.isEmpty) {
          if (!firstChunk) break;
          throw StateError(
            'Fish cannot plan segment ${segment.segmentId}: '
            'the source unit exceeds 75 words or $_fishTurnCap speaker turns.',
          );
        }
        if (safeCut > 0) parts.removeRange(safeCut, parts.length);
        break;
      }
      if (candidateTurns > turnBudget) {
        if (parts.isNotEmpty || !firstChunk) break;
        // Preserve every turn of the first source segment before handing the
        // segment-based refill cursor back to the caller.
        parts.addAll(additions);
        break;
      }
      parts.addAll(additions);
      wordCount += segment.wordCount;
      turnCount = candidateTurns;
    }
    return parts;
  }

  List<_FishPart> _fishParts(
    ChunkPlannerInput input,
    SpeechSegment segment,
    int start,
  ) {
    final ranges = _wordRoutes[segment.segmentId] ?? const [];
    final end = start + segment.wordCount;
    final parts = <_FishPart>[];
    // Count authored performance boundaries identically before and after
    // realization. A later pass may lower model controls for this segment.
    final isolates = input.baseAnnotations
        .forSegment(segment.segmentId)
        .any((annotation) => annotation.isPerformanceIntent);
    final fallback = _ChunkRoutingContext(voiceId: input.voiceId);
    var cursor = start;
    for (final range in ranges) {
      final left = range.startWordIndex.clamp(start, end);
      final right = range.endWordIndex.clamp(start, end);
      if (left == right) continue;
      if (left < cursor) {
        throw StateError(
          'Fish received overlapping speaker ranges for '
          '${segment.segmentId}.',
        );
      }
      if (cursor < left) {
        parts.add(_FishPart(segment, start, cursor, left, fallback, isolates));
      }
      parts.add(
        _FishPart(
          segment,
          start,
          left,
          right,
          _ChunkRoutingContext.fromRange(range),
          isolates,
        ),
      );
      cursor = right;
    }
    if (cursor < end) {
      parts.add(_FishPart(segment, start, cursor, end, fallback, isolates));
    }
    return parts;
  }

  ChunkSpec _finalizeFishTurn(
    ChunkPlannerInput input,
    List<_FishPart> parts, {
    required int ordinal,
  }) {
    final first = parts.first;
    final last = parts.last;
    final artifacts = parts.map((part) => _fishArtifact(part, input)).toList();
    final continuesSentence =
        first.startWord > first.segmentStartWord ||
        (first.segment.ordinal > 0 &&
            (input.fishSceneBoundaries[first.segment.segmentId] ??
                    _sourceBoundary(
                      document.segments[first.segment.ordinal - 1],
                      first.segment,
                    )) ==
                FishSceneBoundary.continuation);
    return _finalizeChunk(
      speechDocument: document,
      input: input,
      ordinal: ordinal,
      built: _BuiltChunk(
        chunkId:
            'chunk_${first.segment.segmentId}'
            '${first.startWord == first.segmentStartWord ? '' : '_w${first.startWord}'}',
        segmentIds: parts.map((part) => part.segment.segmentId).toList(),
        speakText: artifacts.map((artifact) => artifact.speakText).join(' '),
        voiceId: first.route.voiceId,
        startSegmentIndex: first.segment.ordinal,
        endSegmentIndex: last.segment.ordinal,
        estimatedWordCount: last.endWord - first.startWord,
        startWordIndex: first.startWord,
        endWordIndex: last.endWord,
        nextSegmentIndex: last.segment.ordinal + 1,
        routeId: first.route.routeId,
        castId: first.route.castId,
        dialogueSpanId: first.route.dialogueSpanId,
      ),
      realizedSegments: artifacts,
      boundaryClass: continuesSentence ? BreakClass.none : null,
      segmentWordRanges: List.unmodifiable(
        parts.map(
          (part) => ChunkSegmentWordRange(
            part.segment.segmentId,
            part.startWord,
            part.endWord,
          ),
        ),
      ),
    );
  }
}

const _fishTurnCap = 16;

FishSceneBoundary _sourceBoundary(SpeechSegment previous, SpeechSegment next) {
  if (previous.paragraphIndex != next.paragraphIndex ||
      previous.blockId != next.blockId) {
    return FishSceneBoundary.paragraph;
  }
  return previous.sentenceIndex == next.sentenceIndex
      ? FishSceneBoundary.continuation
      : FishSceneBoundary.sentence;
}

class _FishPart {
  const _FishPart(
    this.segment,
    this.segmentStartWord,
    this.startWord,
    this.endWord,
    this.route,
    this.isolatesTurn,
  );

  final SpeechSegment segment;
  final int segmentStartWord;
  final int startWord;
  final int endWord;
  final _ChunkRoutingContext route;
  final bool isolatesTurn;
}

bool _canShareFishTurn(_FishPart left, _FishPart right) =>
    left.endWord == right.startWord &&
    !left.isolatesTurn &&
    !right.isolatesTurn &&
    _canShareChunkRoute(left.route, right.route);

TtsArtifactSegment _fishArtifact(_FishPart part, ChunkPlannerInput input) {
  final artifact = _ttsSegmentFor(
    speechSegment: part.segment,
    ttsArtifactSet: input.ttsArtifactSet,
  );
  final start = part.startWord - part.segmentStartWord;
  final end = part.endWord - part.segmentStartWord;
  if (start == 0 && end == part.segment.wordCount) return artifact;

  // The importer's word coordinates include adjacent punctuation. Splitting at
  // these coordinates preserves the original token text and assigns quotes,
  // commas and other punctuation to the same words as the reading track.
  final words = part.segment.wordSpans;
  final text = part.segment.normalizedText.substring(
    start == 0 ? 0 : words[start].startUtf16,
    end == words.length
        ? part.segment.normalizedText.length
        : words[end - 1].endUtf16,
  );
  return TtsArtifactSegment(
    segmentId: artifact.segmentId,
    speakText: text,
    pronunciationArtifacts: List.unmodifiable([
      for (final pronunciation in artifact.pronunciationArtifacts)
        if (pronunciation.startWord >= start && pronunciation.endWord <= end)
          RealizedPronunciationArtifact(
            artifactId: pronunciation.artifactId,
            segmentId: pronunciation.segmentId,
            startWord: pronunciation.startWord - start,
            endWord: pronunciation.endWord - start,
            resolutionClass: pronunciation.resolutionClass,
            translationIntent: pronunciation.translationIntent,
            selectedRepresentation: pronunciation.selectedRepresentation,
            diagnosticCodes: pronunciation.diagnosticCodes,
          ),
    ]),
    performanceIntents: List.unmodifiable(
      artifact.performanceIntents.where(
        (intent) =>
            intent.annotation.startWord < end &&
            intent.annotation.endWord > start,
      ),
    ),
    boundaryIntents: List.unmodifiable(
      artifact.boundaryIntents.where(
        (intent) => intent.endWord > start && intent.endWord <= end,
      ),
    ),
    emphasisIntents: List.unmodifiable(
      artifact.emphasisIntents.where(
        (intent) => intent.startWord < end && intent.endWord > start,
      ),
    ),
    diagnosticCodes: artifact.diagnosticCodes,
  );
}

_BuiltChunk _buildChunk({
  required SpeechDocument speechDocument,
  required TtsArtifactSet ttsArtifactSet,
  required int startSegmentIndex,
  required List<int> globalWordOffsets,
  required int softTarget,
  required int endSegmentExclusive,
  required String fallbackVoiceId,
  required Map<String, _ChunkRoutingContext> routingContextBySegmentId,
}) {
  final collectedSegments = <SpeechSegment>[];
  final collectedTexts = <String>[];
  var wordCount = 0;
  var cursor = startSegmentIndex;
  _ChunkRoutingContext? routingContext;

  while (cursor < endSegmentExclusive) {
    final segment = speechDocument.segments[cursor];
    final segmentRoutingContext =
        routingContextBySegmentId[segment.segmentId] ??
        _ChunkRoutingContext(
          voiceId: fallbackVoiceId,
          routeId: null,
          castId: null,
          dialogueSpanId: null,
        );
    if (collectedSegments.isNotEmpty &&
        !_canShareChunkRoute(routingContext!, segmentRoutingContext)) {
      break;
    }

    final ttsSegment = _ttsSegmentFor(
      speechSegment: segment,
      ttsArtifactSet: ttsArtifactSet,
    );
    if (collectedSegments.isNotEmpty &&
        ttsSegment.performanceIntents.any(
          (intent) => intent.engineControl != null,
        )) {
      break;
    }
    final candidateWordCount = wordCount + segment.wordCount;
    final wouldExceedHardCap =
        collectedSegments.isNotEmpty &&
        candidateWordCount > ChunkPlannerService._hardChunkWordCap;
    if (wouldExceedHardCap) {
      break;
    }

    collectedSegments.add(segment);
    collectedTexts.add(ttsSegment.speakText);
    wordCount = candidateWordCount;
    routingContext ??= segmentRoutingContext;
    cursor += 1;
    if (ttsSegment.performanceIntents.any(
      (intent) => intent.engineControl != null,
    )) {
      break;
    }

    final nextSegment = cursor < speechDocument.segments.length
        ? speechDocument.segments[cursor]
        : null;
    final paragraphBoundary =
        nextSegment == null ||
        nextSegment.paragraphIndex != segment.paragraphIndex;
    final sentenceBoundary = true;

    if (wordCount >= softTarget && (paragraphBoundary || sentenceBoundary)) {
      break;
    }
  }

  if (collectedSegments.isEmpty) {
    final oversizeSegment = speechDocument.segments[startSegmentIndex];
    final routingContext =
        routingContextBySegmentId[oversizeSegment.segmentId] ??
        _ChunkRoutingContext(
          voiceId: fallbackVoiceId,
          routeId: null,
          castId: null,
          dialogueSpanId: null,
        );
    return _splitOversizeSegment(
      segment: oversizeSegment,
      globalWordOffset: globalWordOffsets[startSegmentIndex],
      softTarget: softTarget,
      routingContext: routingContext,
    );
  }

  final startWordIndex = globalWordOffsets[collectedSegments.first.ordinal];
  final endWordIndex = startWordIndex + wordCount;
  return _BuiltChunk(
    chunkId: 'chunk_${collectedSegments.first.segmentId}',
    segmentIds: collectedSegments
        .map((segment) => segment.segmentId)
        .toList(growable: false),
    speakText: collectedTexts.join(' '),
    voiceId: routingContext?.voiceId ?? fallbackVoiceId,
    startSegmentIndex: collectedSegments.first.ordinal,
    endSegmentIndex: collectedSegments.last.ordinal,
    estimatedWordCount: wordCount,
    startWordIndex: startWordIndex,
    endWordIndex: endWordIndex,
    nextSegmentIndex: cursor,
    routeId: routingContext?.routeId,
    castId: routingContext?.castId,
    dialogueSpanId: routingContext?.dialogueSpanId,
  );
}

_BuiltChunk _splitOversizeSegment({
  required SpeechSegment segment,
  required int globalWordOffset,
  required int softTarget,
  required _ChunkRoutingContext routingContext,
}) {
  final clauses = segment.normalizedText
      .split(RegExp(r'(?<=[,;:])\s+'))
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  if (clauses.length <= 1) {
    final words = segment.normalizedText.split(RegExp(r'\s+'));
    final slice = words
        .take(softTarget.clamp(1, words.length))
        .toList(growable: false);
    return _BuiltChunk(
      chunkId: '${segment.segmentId}_part_0',
      segmentIds: <String>[segment.segmentId],
      speakText: slice.join(' '),
      voiceId: routingContext.voiceId,
      startSegmentIndex: segment.ordinal,
      endSegmentIndex: segment.ordinal,
      estimatedWordCount: slice.length,
      startWordIndex: globalWordOffset,
      endWordIndex: globalWordOffset + slice.length,
      nextSegmentIndex: segment.ordinal + 1,
      routeId: routingContext.routeId,
      castId: routingContext.castId,
      dialogueSpanId: routingContext.dialogueSpanId,
    );
  }

  final buffer = <String>[];
  var wordCount = 0;
  for (final clause in clauses) {
    final clauseWords = clause.split(RegExp(r'\s+')).length;
    if (buffer.isNotEmpty && wordCount + clauseWords > softTarget) {
      break;
    }
    buffer.add(clause);
    wordCount += clauseWords;
  }
  if (buffer.isEmpty) {
    buffer.add(clauses.first);
    wordCount = clauses.first.split(RegExp(r'\s+')).length;
  }

  return _BuiltChunk(
    chunkId: '${segment.segmentId}_part_0',
    segmentIds: <String>[segment.segmentId],
    speakText: buffer.join(' '),
    voiceId: routingContext.voiceId,
    startSegmentIndex: segment.ordinal,
    endSegmentIndex: segment.ordinal,
    estimatedWordCount: wordCount,
    startWordIndex: globalWordOffset,
    endWordIndex: globalWordOffset + wordCount,
    nextSegmentIndex: segment.ordinal + 1,
    routeId: routingContext.routeId,
    castId: routingContext.castId,
    dialogueSpanId: routingContext.dialogueSpanId,
  );
}

ChunkSpec _finalizeChunk({
  required SpeechDocument speechDocument,
  required _BuiltChunk built,
  required ChunkPlannerInput input,
  required int ordinal,
  List<TtsArtifactSegment>? realizedSegments,
  BreakClass? boundaryClass,
  List<ChunkSegmentWordRange> segmentWordRanges = const [],
}) {
  final speakHash = crypto.sha256
      .convert(utf8.encode(built.speakText))
      .toString();
  final ttsSegments =
      realizedSegments ??
      built.segmentIds
          .map((segmentId) {
            final segment = speechDocument
                .segments[speechDocument.segmentIndexById[segmentId] ?? 0];
            return _ttsSegmentFor(
              speechSegment: segment,
              ttsArtifactSet: input.ttsArtifactSet,
            );
          })
          .toList(growable: false);
  final pronunciationFingerprint = _pronunciationFingerprint(ttsSegments);
  final cacheKey = [
    input.engineId,
    input.engineVersion,
    built.voiceId,
    input.rate.toString(),
    speechDocument.normalizationVersion,
    speakHash,
    pronunciationFingerprint,
  ].join(':');

  return ChunkSpec(
    chunkId: built.chunkId.isEmpty ? 'chunk_$ordinal' : built.chunkId,
    segmentIds: built.segmentIds,
    speakText: built.speakText,
    voiceId: built.voiceId.isEmpty ? input.voiceId : built.voiceId,
    boundaryClass:
        boundaryClass ??
        _boundaryClassForChunk(
          speechDocument: speechDocument,
          annotations: input.baseAnnotations,
          ttsArtifactSet: input.ttsArtifactSet,
          built: built,
          ordinal: ordinal,
        ),
    startSegmentIndex: built.startSegmentIndex,
    endSegmentIndex: built.endSegmentIndex,
    estimatedWordCount: built.estimatedWordCount,
    cacheKey: cacheKey,
    startWordIndex: built.startWordIndex,
    endWordIndex: built.endWordIndex,
    ttsSegments: ttsSegments,
    segmentWordRanges: segmentWordRanges,
    routeId: built.routeId,
    castId: built.castId,
    dialogueSpanId: built.dialogueSpanId,
  );
}

BreakClass _boundaryClassForChunk({
  required SpeechDocument speechDocument,
  required BaseSpeechAnnotationSet annotations,
  required TtsArtifactSet ttsArtifactSet,
  required _BuiltChunk built,
  required int ordinal,
}) {
  if (ordinal == 0 || built.startSegmentIndex <= 0) {
    return BreakClass.none;
  }

  final previousSegment = speechDocument.segments[built.startSegmentIndex - 1];
  final realizedBoundaryIntents =
      ttsArtifactSet.segmentById(previousSegment.segmentId)?.boundaryIntents ??
      const <RealizedBoundaryIntent>[];
  if (realizedBoundaryIntents.isNotEmpty) {
    final strongestBoundary = realizedBoundaryIntents.reduce((best, candidate) {
      return _realizedBoundaryStrength(candidate) >
              _realizedBoundaryStrength(best)
          ? candidate
          : best;
    });
    return BreakClass.values.byName(strongestBoundary.breakClass);
  }

  final pauseCandidates = annotations
      .forSegment(previousSegment.segmentId)
      .where(
        (annotation) =>
            annotation.kind == SpeechAnnotationKind.pauseCandidate &&
            annotation.breakClass != null,
      )
      .toList(growable: false);

  if (pauseCandidates.isEmpty) {
    return BreakClass.sentence;
  }

  return pauseCandidates.last.breakClass ?? BreakClass.sentence;
}

int _realizedBoundaryStrength(RealizedBoundaryIntent intent) {
  final kindBonus = intent.sourceKind == 'pause_candidate' ? 10 : 0;
  final classStrength = switch (intent.breakClass) {
    'none' => 0,
    'weak' => 1,
    'sentence' => 2,
    'paragraph' => 3,
    'section' => 4,
    _ => 0,
  };
  return kindBonus + classStrength;
}

List<int> _globalWordOffsets(SpeechDocument document) {
  final offsets = <int>[];
  var running = 0;
  for (final segment in document.segments) {
    offsets.add(running);
    running += segment.wordCount;
  }
  return offsets;
}

class _BuiltChunk {
  const _BuiltChunk({
    required this.chunkId,
    required this.segmentIds,
    required this.speakText,
    required this.voiceId,
    required this.startSegmentIndex,
    required this.endSegmentIndex,
    required this.estimatedWordCount,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.nextSegmentIndex,
    required this.routeId,
    required this.castId,
    required this.dialogueSpanId,
  });

  final String chunkId;
  final List<String> segmentIds;
  final String speakText;
  final String voiceId;
  final int startSegmentIndex;
  final int endSegmentIndex;
  final int estimatedWordCount;
  final int startWordIndex;
  final int endWordIndex;
  final int nextSegmentIndex;
  final String? routeId;
  final String? castId;
  final String? dialogueSpanId;
}

TtsArtifactSegment _ttsSegmentFor({
  required SpeechSegment speechSegment,
  required TtsArtifactSet ttsArtifactSet,
}) {
  return ttsArtifactSet.segmentById(speechSegment.segmentId) ??
      TtsArtifactSegment(
        segmentId: speechSegment.segmentId,
        speakText: speechSegment.normalizedText,
        pronunciationArtifacts: const <RealizedPronunciationArtifact>[],
      );
}

String _pronunciationFingerprint(List<TtsArtifactSegment> segments) {
  if (segments.isEmpty) {
    return 'no_artifacts';
  }
  final serialized = segments
      .map((segment) {
        final artifacts = segment.pronunciationArtifacts
            .map((artifact) {
              final representation = artifact.selectedRepresentation;
              return [
                artifact.artifactId,
                artifact.resolutionClass,
                artifact.translationIntent,
                representation?.representationType ?? 'none',
                representation?.representationValue ?? 'none',
              ].join('/');
            })
            .join(',');
        return '${segment.segmentId}[$artifacts]';
      })
      .join('|');
  return crypto.sha256
      .convert(utf8.encode(serialized))
      .toString()
      .substring(0, 16);
}

Map<String, _ChunkRoutingContext> _routingContextBySegmentId(
  CastAwareSpeechRouteSet? routeSet,
) {
  if (routeSet == null) {
    return const <String, _ChunkRoutingContext>{};
  }

  final contexts = <String, _ChunkRoutingContext>{};
  for (final range in routeSet.ranges) {
    final context = _ChunkRoutingContext.fromRange(range);
    for (final segmentId in range.segmentIds) {
      contexts[segmentId] = context;
    }
  }
  return contexts;
}

Map<String, List<CastAwareSpeechRange>> _rangesBySegmentId(
  CastAwareSpeechRouteSet? routeSet,
) {
  if (routeSet == null) return const {};
  final ranges = routeSet.ranges.toList()
    ..sort(
      (left, right) => left.startWordIndex.compareTo(right.startWordIndex),
    );
  final bySegment = <String, List<CastAwareSpeechRange>>{};
  for (final range in ranges) {
    for (final id in range.segmentIds) {
      (bySegment[id] ??= []).add(range);
    }
  }
  return bySegment;
}

bool _canShareChunkRoute(
  _ChunkRoutingContext left,
  _ChunkRoutingContext right,
) {
  return left.voiceId == right.voiceId &&
      left.routeId == right.routeId &&
      left.castId == right.castId &&
      left.dialogueSpanId == right.dialogueSpanId;
}

class _ChunkRoutingContext {
  const _ChunkRoutingContext({
    required this.voiceId,
    this.routeId,
    this.castId,
    this.dialogueSpanId,
  });

  _ChunkRoutingContext.fromRange(CastAwareSpeechRange range)
    : this(
        voiceId: range.voiceId,
        routeId: range.routeId,
        castId: range.castId,
        dialogueSpanId: range.dialogueSpanId,
      );

  final String voiceId;
  final String? routeId;
  final String? castId;
  final String? dialogueSpanId;
}

ChunkSpec _nativeScene(List<ChunkSpec> turns) {
  final first = turns.first;
  final last = turns.last;
  return ChunkSpec(
    chunkId: 'scene_${first.chunkId}',
    segmentIds: List.unmodifiable(
      turns.expand((turn) => turn.segmentIds).toSet(),
    ),
    speakText: turns.map((turn) => turn.speakText).join(' '),
    voiceId: first.voiceId,
    boundaryClass: first.boundaryClass,
    startSegmentIndex: first.startSegmentIndex,
    endSegmentIndex: last.endSegmentIndex,
    estimatedWordCount: last.endWordIndex - first.startWordIndex,
    cacheKey: crypto.sha256
        .convert(utf8.encode(turns.map((turn) => turn.cacheKey).join('|')))
        .toString(),
    startWordIndex: first.startWordIndex,
    endWordIndex: last.endWordIndex,
    ttsSegments: List.unmodifiable(turns.expand((turn) => turn.ttsSegments)),
    sceneTurns: List.unmodifiable(turns),
  );
}

/// Application work-ahead bound, distinct from the library's native splitter.
List<ChunkSpec> packNativeSceneChunks(List<ChunkSpec> turns) {
  final result = <ChunkSpec>[];
  var group = <ChunkSpec>[];
  var words = 0;
  final voices = <String>{};
  void flush() {
    if (group.isEmpty) return;
    result.add(_nativeScene(group));
    group = [];
    words = 0;
    voices.clear();
  }

  for (final turn in turns) {
    if (group.isNotEmpty &&
        (group.length >= _fishTurnCap ||
            words + turn.estimatedWordCount >
                ChunkPlannerService._hardChunkWordCap ||
            (!voices.contains(turn.voiceId) && voices.length == _fishTurnCap) ||
            group.last.endWordIndex != turn.startWordIndex)) {
      flush();
    }
    group.add(turn);
    words += turn.estimatedWordCount;
    voices.add(turn.voiceId);
  }
  flush();
  return result;
}
