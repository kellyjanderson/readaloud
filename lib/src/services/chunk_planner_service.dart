import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../models/chunk_plan.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';
import '../models/tts_artifact.dart';

class ChunkPlannerService {
  const ChunkPlannerService();

  static const _firstChunkSoftTargetWords = 16;
  static const _steadyChunkSoftTargetWords = 42;
  static const _hardChunkWordCap = 75;

  ChunkPlan plan(ChunkPlannerInput input) {
    final speechDocument = input.speechDocument;
    final startSegmentIndex =
        speechDocument.segmentIndexById[input.startSegmentId] ?? 0;
    final chunks = <ChunkSpec>[];
    final globalWordOffsets = _globalWordOffsets(speechDocument);

    var cursor = startSegmentIndex;
    while (cursor < speechDocument.segments.length) {
      final isFirstChunk = chunks.isEmpty;
      final softTarget = isFirstChunk
          ? _firstChunkSoftTargetWords
          : _steadyChunkSoftTargetWords;

      final built = _buildChunk(
        speechDocument: speechDocument,
        ttsArtifactSet: input.ttsArtifactSet,
        startSegmentIndex: cursor,
        globalWordOffsets: globalWordOffsets,
        softTarget: softTarget,
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

    final planDigest = crypto.sha256.convert(
      utf8.encode(
        [
          input.startSegmentId,
          input.voiceId,
          input.rate.toStringAsFixed(2),
          input.engineId,
          input.engineVersion,
          chunks.map((chunk) => chunk.cacheKey).join('|'),
        ].join('::'),
      ),
    );

    return ChunkPlan(
      planId: 'plan_${planDigest.toString().substring(0, 16)}',
      chunks: chunks,
    );
  }
}

_BuiltChunk _buildChunk({
  required SpeechDocument speechDocument,
  required TtsArtifactSet ttsArtifactSet,
  required int startSegmentIndex,
  required List<int> globalWordOffsets,
  required int softTarget,
}) {
  final collectedSegments = <SpeechSegment>[];
  final collectedTexts = <String>[];
  var wordCount = 0;
  var cursor = startSegmentIndex;

  while (cursor < speechDocument.segments.length) {
    final segment = speechDocument.segments[cursor];
    final ttsSegment = _ttsSegmentFor(
      speechSegment: segment,
      ttsArtifactSet: ttsArtifactSet,
    );
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
    cursor += 1;

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
    return _splitOversizeSegment(
      segment: oversizeSegment,
      globalWordOffset: globalWordOffsets[startSegmentIndex],
      softTarget: softTarget,
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
    startSegmentIndex: collectedSegments.first.ordinal,
    endSegmentIndex: collectedSegments.last.ordinal,
    estimatedWordCount: wordCount,
    startWordIndex: startWordIndex,
    endWordIndex: endWordIndex,
    nextSegmentIndex: cursor,
  );
}

_BuiltChunk _splitOversizeSegment({
  required SpeechSegment segment,
  required int globalWordOffset,
  required int softTarget,
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
      startSegmentIndex: segment.ordinal,
      endSegmentIndex: segment.ordinal,
      estimatedWordCount: slice.length,
      startWordIndex: globalWordOffset,
      endWordIndex: globalWordOffset + slice.length,
      nextSegmentIndex: segment.ordinal + 1,
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
    startSegmentIndex: segment.ordinal,
    endSegmentIndex: segment.ordinal,
    estimatedWordCount: wordCount,
    startWordIndex: globalWordOffset,
    endWordIndex: globalWordOffset + wordCount,
    nextSegmentIndex: segment.ordinal + 1,
  );
}

ChunkSpec _finalizeChunk({
  required SpeechDocument speechDocument,
  required _BuiltChunk built,
  required ChunkPlannerInput input,
  required int ordinal,
}) {
  final speakHash = crypto.sha256
      .convert(utf8.encode(built.speakText))
      .toString();
  final ttsSegments = built.segmentIds
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
    input.voiceId,
    input.rate.toStringAsFixed(2),
    speechDocument.normalizationVersion,
    speakHash,
    pronunciationFingerprint,
  ].join(':');

  return ChunkSpec(
    chunkId: built.chunkId.isEmpty ? 'chunk_$ordinal' : built.chunkId,
    segmentIds: built.segmentIds,
    speakText: built.speakText,
    boundaryClass: _boundaryClassForChunk(
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
    required this.startSegmentIndex,
    required this.endSegmentIndex,
    required this.estimatedWordCount,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.nextSegmentIndex,
  });

  final String chunkId;
  final List<String> segmentIds;
  final String speakText;
  final int startSegmentIndex;
  final int endSegmentIndex;
  final int estimatedWordCount;
  final int startWordIndex;
  final int endWordIndex;
  final int nextSegmentIndex;
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
