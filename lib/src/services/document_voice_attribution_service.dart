import '../models/character_cast_registry.dart';
import '../models/dialogue_attribution.dart';
import '../models/document_voice_attribution.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';

class DocumentVoiceAttributionInput {
  const DocumentVoiceAttributionInput({
    required this.speechDocument,
    required this.baseAnnotations,
    required this.dialogueAttributions,
    required this.characterCastRegistry,
  });

  final SpeechDocument speechDocument;
  final BaseSpeechAnnotationSet baseAnnotations;
  final DialogueAttributionSet dialogueAttributions;
  final CharacterCastRegistry characterCastRegistry;
}

class DocumentVoiceAttributionService {
  const DocumentVoiceAttributionService();

  static const attributionVersion = 'read-aloud-document-voice-attribution-v1';

  DocumentVoiceAttributionSet build(DocumentVoiceAttributionInput input) {
    final narratorCastId = input.characterCastRegistry.narratorEntry.castId;
    final castIdByAttributionId = <String, String>{};
    for (final entry in input.characterCastRegistry.characterEntries) {
      for (final attributionId in entry.attributionIds) {
        castIdByAttributionId[attributionId] = entry.castId;
      }
    }

    final attributedSegments = <_AttributedSegment>[];
    var runningWordIndex = 0;
    for (final segment in input.speechDocument.segments) {
      final dialogueAnnotation = input.baseAnnotations
          .forSegment(segment.segmentId)
          .where(
            (annotation) =>
                annotation.kind == SpeechAnnotationKind.dialogueSpan,
          )
          .cast<SpeechAnnotation?>()
          .firstWhere((annotation) => annotation != null, orElse: () => null);
      final dialogueSpanId = dialogueAnnotation?.dialogueSpanId;
      final attribution = dialogueSpanId == null
          ? null
          : input.dialogueAttributions.forDialogueSpan(dialogueSpanId);

      final kind = switch (attribution?.resolution) {
        DialogueAttributionResolution.attributedSpeaker =>
          DocumentVoiceAttributionKind.attributedDialogue,
        DialogueAttributionResolution.unattributedDialogue =>
          DocumentVoiceAttributionKind.unattributedDialogue,
        _ => DocumentVoiceAttributionKind.narration,
      };
      final castId = switch (attribution?.resolution) {
        DialogueAttributionResolution.attributedSpeaker =>
          castIdByAttributionId[attribution!.attributionId] ?? narratorCastId,
        _ => narratorCastId,
      };

      attributedSegments.add(
        _AttributedSegment(
          segmentId: segment.segmentId,
          startWordIndex: runningWordIndex,
          endWordIndex: runningWordIndex + segment.wordCount,
          castId: castId,
          kind: kind,
          dialogueSpanId: dialogueSpanId,
        ),
      );
      runningWordIndex += segment.wordCount;
    }

    final mergedRanges = <DocumentVoiceAttributionRange>[];
    _AttributedSegment? active;
    for (final segment in attributedSegments) {
      if (active == null) {
        active = segment;
        continue;
      }
      if (_canMerge(active, segment)) {
        active = active.copyWith(
          segmentIds: <String>[...active.segmentIds, ...segment.segmentIds],
          endWordIndex: segment.endWordIndex,
          endSegmentId: segment.endSegmentId,
        );
        continue;
      }
      mergedRanges.add(_toRange(active));
      active = segment;
    }
    if (active != null) {
      mergedRanges.add(_toRange(active));
    }

    return DocumentVoiceAttributionSet(
      documentId: input.speechDocument.documentId,
      attributionVersion: attributionVersion,
      ranges: mergedRanges,
    );
  }

  bool _canMerge(_AttributedSegment left, _AttributedSegment right) {
    return left.castId == right.castId &&
        left.kind == right.kind &&
        left.endWordIndex == right.startWordIndex &&
        left.dialogueSpanId == right.dialogueSpanId;
  }

  DocumentVoiceAttributionRange _toRange(_AttributedSegment range) {
    return DocumentVoiceAttributionRange(
      rangeId: 'attr_range_${range.segmentIds.first}',
      segmentIds: range.segmentIds,
      startSegmentId: range.segmentIds.first,
      endSegmentId: range.endSegmentId,
      startWordIndex: range.startWordIndex,
      endWordIndex: range.endWordIndex,
      castId: range.castId,
      kind: range.kind,
      dialogueSpanId: range.dialogueSpanId,
    );
  }
}

class _AttributedSegment {
  _AttributedSegment({
    required this.segmentId,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.castId,
    required this.kind,
    required this.dialogueSpanId,
  }) : segmentIds = <String>[segmentId],
       endSegmentId = segmentId;

  _AttributedSegment._({
    required this.segmentIds,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.castId,
    required this.kind,
    required this.dialogueSpanId,
    required this.endSegmentId,
  }) : segmentId = segmentIds.first;

  final String segmentId;
  final List<String> segmentIds;
  final String endSegmentId;
  final int startWordIndex;
  final int endWordIndex;
  final String castId;
  final DocumentVoiceAttributionKind kind;
  final String? dialogueSpanId;

  _AttributedSegment copyWith({
    List<String>? segmentIds,
    int? endWordIndex,
    String? endSegmentId,
  }) {
    return _AttributedSegment._(
      segmentIds: segmentIds ?? this.segmentIds,
      startWordIndex: startWordIndex,
      endWordIndex: endWordIndex ?? this.endWordIndex,
      castId: castId,
      kind: kind,
      dialogueSpanId: dialogueSpanId,
      endSegmentId: endSegmentId ?? this.endSegmentId,
    );
  }
}
