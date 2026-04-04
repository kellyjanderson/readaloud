import '../models/dialogue_attribution.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';

class SpeakerAttributionService {
  const SpeakerAttributionService();

  static const attributionVersion = 'read-aloud-speaker-attribution-v1';
  static const providerId = 'heuristic_speaker_attribution';
  static const providerVersion = 'v1';

  static final RegExp _speakerBeforeVerbPattern = RegExp(
    r"\b([A-Z][A-Za-z'’-]+(?:\s+[A-Z][A-Za-z'’-]+){0,2})\s+"
    r"(said|says|asked|asks|replied|replies|whispered|yelled|cried|muttered|called|answered|remarked|added|snapped|continued|finished)\b",
  );
  static final RegExp _verbBeforeSpeakerPattern = RegExp(
    r"\b(said|says|asked|asks|replied|replies|whispered|yelled|cried|muttered|called|answered|remarked|added|snapped|continued|finished)\s+"
    r"([A-Z][A-Za-z'’-]+(?:\s+[A-Z][A-Za-z'’-]+){0,2})\b",
  );
  static const Set<String> _excludedSpeakerLabels = <String>{
    'A',
    'An',
    'He',
    'Her',
    'His',
    'I',
    'It',
    'She',
    'The',
    'They',
    'We',
    'You',
  };

  DialogueAttributionSet attribute({
    required SpeechDocument speechDocument,
    required BaseSpeechAnnotationSet baseAnnotations,
  }) {
    final segmentById = <String, SpeechSegment>{
      for (final segment in speechDocument.segments) segment.segmentId: segment,
    };
    final orderedSpanIds = <String>[];
    final annotationsBySpanId = <String, List<SpeechAnnotation>>{};

    for (final annotation in baseAnnotations.annotations) {
      if (annotation.kind != SpeechAnnotationKind.dialogueSpan ||
          annotation.dialogueSpanId == null) {
        continue;
      }
      final dialogueSpanId = annotation.dialogueSpanId!;
      final entries = annotationsBySpanId.putIfAbsent(dialogueSpanId, () {
        orderedSpanIds.add(dialogueSpanId);
        return <SpeechAnnotation>[];
      });
      entries.add(annotation);
    }

    final outcomes = <DialogueAttributionOutcome>[];
    for (final dialogueSpanId in orderedSpanIds) {
      final spanAnnotations = annotationsBySpanId[dialogueSpanId]!;
      final span = _DialogueSpanContext.fromAnnotations(
        dialogueSpanId: dialogueSpanId,
        annotations: spanAnnotations,
        segmentById: segmentById,
        segmentIndexById: speechDocument.segmentIndexById,
      );
      outcomes.add(
        _attributeDialogueSpan(span: span, speechDocument: speechDocument),
      );
    }

    return DialogueAttributionSet(
      documentId: speechDocument.documentId,
      attributionVersion: attributionVersion,
      providerId: providerId,
      providerVersion: providerVersion,
      outcomes: outcomes,
    );
  }

  DialogueAttributionOutcome _attributeDialogueSpan({
    required _DialogueSpanContext span,
    required SpeechDocument speechDocument,
  }) {
    final inSpanMatch = _extractSpeakerLabel(span.combinedText);
    if (inSpanMatch != null) {
      return _attributedOutcome(
        dialogueSpanId: span.dialogueSpanId,
        label: inSpanMatch,
        confidence: 0.84,
      );
    }

    final previousSegment = span.firstSegmentIndex > 0
        ? speechDocument.segments[span.firstSegmentIndex - 1]
        : null;
    if (_isAdjacentEvidenceSegment(span: span, segment: previousSegment)) {
      final previousMatch = _extractSpeakerLabel(
        previousSegment!.normalizedText,
      );
      if (previousMatch != null) {
        return _attributedOutcome(
          dialogueSpanId: span.dialogueSpanId,
          label: previousMatch,
          confidence: 0.72,
        );
      }
    }

    final nextSegment =
        span.lastSegmentIndex + 1 < speechDocument.segments.length
        ? speechDocument.segments[span.lastSegmentIndex + 1]
        : null;
    if (_isAdjacentEvidenceSegment(span: span, segment: nextSegment)) {
      final nextMatch = _extractSpeakerLabel(nextSegment!.normalizedText);
      if (nextMatch != null) {
        return _attributedOutcome(
          dialogueSpanId: span.dialogueSpanId,
          label: nextMatch,
          confidence: 0.72,
        );
      }
    }

    return DialogueAttributionOutcome(
      attributionId: 'attr_${span.dialogueSpanId}',
      dialogueSpanId: span.dialogueSpanId,
      resolution: DialogueAttributionResolution.unattributedDialogue,
      confidence: 0.0,
      provenance: DialogueAttributionProvenance.heuristicInference,
    );
  }

  DialogueAttributionOutcome _attributedOutcome({
    required String dialogueSpanId,
    required String label,
    required double confidence,
  }) {
    final normalizedLabel = _normalizeSpeakerLabel(label);
    return DialogueAttributionOutcome(
      attributionId: 'attr_$dialogueSpanId',
      dialogueSpanId: dialogueSpanId,
      resolution: DialogueAttributionResolution.attributedSpeaker,
      confidence: confidence,
      provenance: DialogueAttributionProvenance.heuristicInference,
      speakerReference: SpeakerReference(
        referenceId: _speakerReferenceIdForLabel(normalizedLabel),
        displayLabel: label,
        normalizedLabel: normalizedLabel,
      ),
    );
  }

  bool _isAdjacentEvidenceSegment({
    required _DialogueSpanContext span,
    required SpeechSegment? segment,
  }) {
    if (segment == null) {
      return false;
    }
    return segment.paragraphIndex == span.paragraphIndex ||
        segment.blockId == span.blockId;
  }

  String? _extractSpeakerLabel(String text) {
    final beforeVerbMatch = _speakerBeforeVerbPattern.firstMatch(text);
    final beforeVerbLabel = beforeVerbMatch?.group(1)?.trim();
    if (_isLikelySpeakerLabel(beforeVerbLabel)) {
      return beforeVerbLabel;
    }

    final verbBeforeMatch = _verbBeforeSpeakerPattern.firstMatch(text);
    final verbBeforeLabel = verbBeforeMatch?.group(2)?.trim();
    if (_isLikelySpeakerLabel(verbBeforeLabel)) {
      return verbBeforeLabel;
    }

    return null;
  }

  bool _isLikelySpeakerLabel(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }
    return !_excludedSpeakerLabels.contains(value);
  }

  String _normalizeSpeakerLabel(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _speakerReferenceIdForLabel(String normalizedLabel) {
    final slug = normalizedLabel
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'speaker_${slug.isEmpty ? 'unknown' : slug}';
  }
}

class _DialogueSpanContext {
  factory _DialogueSpanContext.fromAnnotations({
    required String dialogueSpanId,
    required List<SpeechAnnotation> annotations,
    required Map<String, SpeechSegment> segmentById,
    required Map<String, int> segmentIndexById,
  }) {
    final sortedAnnotations = List<SpeechAnnotation>.from(annotations)
      ..sort(
        (left, right) => segmentIndexById[left.segmentId]!.compareTo(
          segmentIndexById[right.segmentId]!,
        ),
      );
    final firstSegment = segmentById[sortedAnnotations.first.segmentId]!;
    final lastSegment = segmentById[sortedAnnotations.last.segmentId]!;
    return _DialogueSpanContext._(
      dialogueSpanId: dialogueSpanId,
      blockId: firstSegment.blockId,
      paragraphIndex: firstSegment.paragraphIndex,
      firstSegmentIndex: segmentIndexById[firstSegment.segmentId]!,
      lastSegmentIndex: segmentIndexById[lastSegment.segmentId]!,
      combinedText: sortedAnnotations
          .map(
            (annotation) => segmentById[annotation.segmentId]!.normalizedText,
          )
          .join(' '),
    );
  }

  const _DialogueSpanContext._({
    required this.dialogueSpanId,
    required this.blockId,
    required this.paragraphIndex,
    required this.firstSegmentIndex,
    required this.lastSegmentIndex,
    required this.combinedText,
  });

  final String dialogueSpanId;
  final String blockId;
  final int paragraphIndex;
  final int firstSegmentIndex;
  final int lastSegmentIndex;
  final String combinedText;
}
