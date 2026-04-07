import '../models/dialogue_attribution.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';

class SpeakerAttributionService {
  const SpeakerAttributionService();

  static const attributionVersion = 'read-aloud-speaker-attribution-v5';
  static const providerId = 'heuristic_speaker_attribution';
  static const providerVersion = 'v5';
  static const _minimumAttributionConfidence = 0.75;

  static const _speechVerbPattern =
      r'(said|says|say|asked|asks|ask|replied|replies|reply|whispered|whispers|whisper|yelled|yells|yell|cried|cries|cry|muttered|mutters|mutter|called|calls|call|answered|answers|answer|remarked|remarks|remark|added|adds|add|snapped|snaps|snap|continued|continues|continue|finished|finishes|finish|screamed|screams|scream|exclaimed|exclaims|exclaim|retorted|retorts|retort|shouted|shouts|shout|barked|barks|bark|hissed|hisses|hiss|growled|growls|growl)';

  static final RegExp _exactSpeakerBeforeVerbPattern = RegExp(
    "\\b([A-Z][A-Za-z'’-]+(?:\\s+[A-Z][A-Za-z'’-]+){0,2})\\s+$_speechVerbPattern\\b",
  );
  static final RegExp _exactVerbBeforeSpeakerPattern = RegExp(
    "\\b$_speechVerbPattern\\s+([A-Z][A-Za-z'’-]+(?:\\s+[A-Z][A-Za-z'’-]+){0,2})\\b",
  );
  static final RegExp _looseSpeakerBeforeVerbPattern = RegExp(
    "\\b([A-Z][A-Za-z'’-]+(?:\\s+[A-Z][A-Za-z'’-]+){0,2})\\b"
    "(?:\\s+[a-z][A-Za-z'’-]*){0,4}\\s+$_speechVerbPattern\\b",
  );
  static final RegExp _looseVerbBeforeSpeakerPattern = RegExp(
    "\\b$_speechVerbPattern"
    "(?:\\s+[a-z][A-Za-z'’-]*){0,4}\\s+"
    "([A-Z][A-Za-z'’-]+(?:\\s+[A-Z][A-Za-z'’-]+){0,2})\\b",
  );
  static final RegExp _pronounBeforeVerbPattern = RegExp(
    "\\b(he|she|they)\\s+$_speechVerbPattern\\b",
    caseSensitive: false,
  );
  static final RegExp _verbBeforePronounPattern = RegExp(
    "\\b$_speechVerbPattern\\s+(he|she|they)\\b",
    caseSensitive: false,
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

    final spans = <_DialogueSpanContext>[];
    for (final dialogueSpanId in orderedSpanIds) {
      final spanAnnotations = annotationsBySpanId[dialogueSpanId]!;
      spans.add(
        _DialogueSpanContext.fromAnnotations(
          dialogueSpanId: dialogueSpanId,
          annotations: spanAnnotations,
          segmentById: segmentById,
          segmentIndexById: speechDocument.segmentIndexById,
        ),
      );
    }

    final outcomes = <DialogueAttributionOutcome>[];
    final resolvedSpans = <_ResolvedDialogueSpan>[];
    for (final span in spans) {
      final outcome = _attributeDialogueSpan(
        span: span,
        speechDocument: speechDocument,
        priorResolvedSpans: resolvedSpans,
      );
      outcomes.add(outcome);
      resolvedSpans.add(_ResolvedDialogueSpan(span: span, outcome: outcome));
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
    required List<_ResolvedDialogueSpan> priorResolvedSpans,
  }) {
    final decision =
        _sameSentenceDecision(span) ??
        _adjacentDecision(
          span: span,
          speechDocument: speechDocument,
          direction: _AdjacentDirection.after,
        ) ??
        _adjacentDecision(
          span: span,
          speechDocument: speechDocument,
          direction: _AdjacentDirection.before,
        ) ??
        _paragraphOwnershipDecision(
          span: span,
          priorResolvedSpans: priorResolvedSpans,
        ) ??
        _dialogueAlternationDecision(
          span: span,
          priorResolvedSpans: priorResolvedSpans,
        ) ??
        _pronounResolutionDecision(
          span: span,
          speechDocument: speechDocument,
          priorResolvedSpans: priorResolvedSpans,
        ) ??
        _speakerPersistenceDecision(
          span: span,
          priorResolvedSpans: priorResolvedSpans,
        );

    if (decision == null) {
      return _unknownOutcome(
        dialogueSpanId: span.dialogueSpanId,
        confidence: 0.0,
        ruleUsed: DialogueAttributionRule.noEvidence,
      );
    }

    if (decision.confidence < _minimumAttributionConfidence) {
      return _unknownOutcome(
        dialogueSpanId: span.dialogueSpanId,
        confidence: decision.confidence,
        ruleUsed: DialogueAttributionRule.unknownBelowThreshold,
        evidenceSpan: decision.evidenceSpan,
      );
    }

    return _attributedOutcome(
      dialogueSpanId: span.dialogueSpanId,
      label: decision.label,
      confidence: decision.confidence,
      ruleUsed: decision.ruleUsed,
      evidenceSpan: decision.evidenceSpan,
    );
  }

  _AttributionDecision? _sameSentenceDecision(_DialogueSpanContext span) {
    if (span.segmentIds.length != 1) {
      return null;
    }
    return _bestCandidateForText(
      text: span.combinedText,
      sourceSegmentId: span.segmentIds.single,
      ruleUsed: DialogueAttributionRule.sameSentenceExplicit,
      exactConfidence: 0.97,
      looseConfidence: 0.93,
    );
  }

  _AttributionDecision? _adjacentDecision({
    required _DialogueSpanContext span,
    required SpeechDocument speechDocument,
    required _AdjacentDirection direction,
  }) {
    final segmentIndex = switch (direction) {
      _AdjacentDirection.after => span.lastSegmentIndex + 1,
      _AdjacentDirection.before => span.firstSegmentIndex - 1,
    };
    if (segmentIndex < 0 || segmentIndex >= speechDocument.segments.length) {
      return null;
    }

    final segment = speechDocument.segments[segmentIndex];
    if (!_isLocalEvidenceSegment(span: span, segment: segment)) {
      return null;
    }

    return _bestCandidateForText(
      text: segment.normalizedText,
      sourceSegmentId: segment.segmentId,
      ruleUsed: direction == _AdjacentDirection.after
          ? DialogueAttributionRule.adjacentAfter
          : DialogueAttributionRule.adjacentBefore,
      exactConfidence: direction == _AdjacentDirection.after ? 0.90 : 0.88,
      looseConfidence: direction == _AdjacentDirection.after ? 0.84 : 0.82,
    );
  }

  _AttributionDecision? _paragraphOwnershipDecision({
    required _DialogueSpanContext span,
    required List<_ResolvedDialogueSpan> priorResolvedSpans,
  }) {
    final sameParagraphAttributions = priorResolvedSpans
        .where(
          (resolved) =>
              resolved.isAttributed &&
              resolved.span.blockId == span.blockId &&
              resolved.span.paragraphIndex == span.paragraphIndex,
        )
        .toList(growable: false);
    if (sameParagraphAttributions.isEmpty) {
      return null;
    }

    final speakersById = <String, _ResolvedDialogueSpan>{};
    for (final resolved in sameParagraphAttributions) {
      final speaker = resolved.outcome.speakerReference!;
      speakersById.putIfAbsent(speaker.referenceId, () => resolved);
    }
    if (speakersById.length != 1) {
      return null;
    }

    final ownerResolution = sameParagraphAttributions.last;
    final ownerSpeaker = ownerResolution.outcome.speakerReference!;
    return _AttributionDecision(
      label: ownerSpeaker.displayLabel,
      confidence: 0.79,
      ruleUsed: DialogueAttributionRule.paragraphOwnership,
      evidenceSpan: ownerResolution.outcome.evidenceSpan!,
    );
  }

  _AttributionDecision? _dialogueAlternationDecision({
    required _DialogueSpanContext span,
    required List<_ResolvedDialogueSpan> priorResolvedSpans,
  }) {
    final recentParagraphResolutions = <_ResolvedDialogueSpan>[];
    final seenParagraphs = <int>{};
    for (final resolved in priorResolvedSpans.reversed) {
      if (!resolved.isAttributed ||
          resolved.span.paragraphIndex >= span.paragraphIndex ||
          !seenParagraphs.add(resolved.span.paragraphIndex)) {
        continue;
      }
      recentParagraphResolutions.add(resolved);
      if (recentParagraphResolutions.length == 2) {
        break;
      }
    }

    if (recentParagraphResolutions.length < 2) {
      return null;
    }

    final mostRecent = recentParagraphResolutions[0];
    final previous = recentParagraphResolutions[1];
    final mostRecentSpeaker = mostRecent.outcome.speakerReference!;
    final previousSpeaker = previous.outcome.speakerReference!;
    if (span.paragraphIndex != mostRecent.span.paragraphIndex + 1 ||
        mostRecent.span.paragraphIndex != previous.span.paragraphIndex + 1 ||
        mostRecentSpeaker.referenceId == previousSpeaker.referenceId) {
      return null;
    }

    return _AttributionDecision(
      label: previousSpeaker.displayLabel,
      confidence: 0.78,
      ruleUsed: DialogueAttributionRule.dialogueAlternation,
      evidenceSpan: previous.outcome.evidenceSpan!,
    );
  }

  _AttributionDecision? _pronounResolutionDecision({
    required _DialogueSpanContext span,
    required SpeechDocument speechDocument,
    required List<_ResolvedDialogueSpan> priorResolvedSpans,
  }) {
    final localSpeaker = _singleRecentLocalSpeaker(
      span: span,
      priorResolvedSpans: priorResolvedSpans,
    );
    if (localSpeaker == null) {
      return null;
    }

    for (final direction in _AdjacentDirection.values) {
      final segment = _adjacentLocalSegment(
        span: span,
        speechDocument: speechDocument,
        direction: direction,
      );
      if (segment == null) {
        continue;
      }
      final evidenceSpan = _pronounEvidenceSpan(
        text: segment.normalizedText,
        sourceSegmentId: segment.segmentId,
      );
      if (evidenceSpan == null) {
        continue;
      }
      return _AttributionDecision(
        label: localSpeaker.outcome.speakerReference!.displayLabel,
        confidence: 0.77,
        ruleUsed: DialogueAttributionRule.pronounResolution,
        evidenceSpan: evidenceSpan,
      );
    }

    return null;
  }

  _AttributionDecision? _speakerPersistenceDecision({
    required _DialogueSpanContext span,
    required List<_ResolvedDialogueSpan> priorResolvedSpans,
  }) {
    final localSpeaker = _singleRecentLocalSpeaker(
      span: span,
      priorResolvedSpans: priorResolvedSpans,
    );
    if (localSpeaker == null) {
      return null;
    }

    return _AttributionDecision(
      label: localSpeaker.outcome.speakerReference!.displayLabel,
      confidence: 0.76,
      ruleUsed: DialogueAttributionRule.speakerPersistence,
      evidenceSpan: localSpeaker.outcome.evidenceSpan!,
    );
  }

  SpeechSegment? _adjacentLocalSegment({
    required _DialogueSpanContext span,
    required SpeechDocument speechDocument,
    required _AdjacentDirection direction,
  }) {
    final segmentIndex = switch (direction) {
      _AdjacentDirection.after => span.lastSegmentIndex + 1,
      _AdjacentDirection.before => span.firstSegmentIndex - 1,
    };
    if (segmentIndex < 0 || segmentIndex >= speechDocument.segments.length) {
      return null;
    }
    final segment = speechDocument.segments[segmentIndex];
    if (!_isLocalEvidenceSegment(span: span, segment: segment)) {
      return null;
    }
    return segment;
  }

  _ResolvedDialogueSpan? _singleRecentLocalSpeaker({
    required _DialogueSpanContext span,
    required List<_ResolvedDialogueSpan> priorResolvedSpans,
  }) {
    final localSpeakers = <String, _ResolvedDialogueSpan>{};
    for (final resolved in priorResolvedSpans.reversed) {
      if (!resolved.isAttributed ||
          span.paragraphIndex - resolved.span.paragraphIndex > 1) {
        continue;
      }
      final speaker = resolved.outcome.speakerReference!;
      localSpeakers.putIfAbsent(speaker.referenceId, () => resolved);
      if (localSpeakers.length > 1) {
        return null;
      }
    }
    if (localSpeakers.length != 1) {
      return null;
    }
    return localSpeakers.values.single;
  }

  DialogueEvidenceSpan? _pronounEvidenceSpan({
    required String text,
    required String sourceSegmentId,
  }) {
    final beforeMatch = _pronounBeforeVerbPattern.firstMatch(text);
    if (beforeMatch != null) {
      return _evidenceSpanForGroup(
        match: beforeMatch,
        groupIndex: 1,
        sourceSegmentId: sourceSegmentId,
      );
    }

    final afterMatch = _verbBeforePronounPattern.firstMatch(text);
    if (afterMatch != null) {
      return _evidenceSpanForGroup(
        match: afterMatch,
        groupIndex: 1,
        sourceSegmentId: sourceSegmentId,
      );
    }

    return null;
  }

  _AttributionDecision? _bestCandidateForText({
    required String text,
    required String sourceSegmentId,
    required DialogueAttributionRule ruleUsed,
    required double exactConfidence,
    required double looseConfidence,
  }) {
    final candidates = _extractSpeakerCandidates(
      text,
      sourceSegmentId: sourceSegmentId,
      ruleUsed: ruleUsed,
      exactConfidence: exactConfidence,
      looseConfidence: looseConfidence,
    );
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort(
      (left, right) => right.confidence.compareTo(left.confidence),
    );
    return candidates.first;
  }

  DialogueAttributionOutcome _attributedOutcome({
    required String dialogueSpanId,
    required String label,
    required double confidence,
    required DialogueAttributionRule ruleUsed,
    required DialogueEvidenceSpan evidenceSpan,
  }) {
    final normalizedLabel = _normalizeSpeakerLabel(label);
    return DialogueAttributionOutcome(
      attributionId: 'attr_$dialogueSpanId',
      dialogueSpanId: dialogueSpanId,
      resolution: DialogueAttributionResolution.attributedSpeaker,
      confidence: confidence.clamp(0.0, 1.0),
      provenance: DialogueAttributionProvenance.heuristicInference,
      ruleUsed: ruleUsed,
      speakerReference: SpeakerReference(
        referenceId: _speakerReferenceIdForLabel(normalizedLabel),
        displayLabel: label,
        normalizedLabel: normalizedLabel,
      ),
      evidenceSpan: evidenceSpan,
    );
  }

  DialogueAttributionOutcome _unknownOutcome({
    required String dialogueSpanId,
    required double confidence,
    required DialogueAttributionRule ruleUsed,
    DialogueEvidenceSpan? evidenceSpan,
  }) {
    return DialogueAttributionOutcome(
      attributionId: 'attr_$dialogueSpanId',
      dialogueSpanId: dialogueSpanId,
      resolution: DialogueAttributionResolution.unattributedDialogue,
      confidence: confidence.clamp(0.0, 1.0),
      provenance: DialogueAttributionProvenance.heuristicInference,
      ruleUsed: ruleUsed,
      evidenceSpan: evidenceSpan,
    );
  }

  bool _isLocalEvidenceSegment({
    required _DialogueSpanContext span,
    required SpeechSegment segment,
  }) {
    return segment.paragraphIndex == span.paragraphIndex ||
        segment.blockId == span.blockId;
  }

  DialogueEvidenceSpan _evidenceSpanForGroup({
    required RegExpMatch match,
    required int groupIndex,
    required String sourceSegmentId,
  }) {
    final groupText = match.group(groupIndex)!;
    final wholeMatchText = match.group(0)!;
    final relativeStart = wholeMatchText.indexOf(groupText);
    final startUtf16 = relativeStart >= 0
        ? match.start + relativeStart
        : match.start;
    final endUtf16 = startUtf16 + groupText.length;
    return DialogueEvidenceSpan(
      segmentId: sourceSegmentId,
      startUtf16: startUtf16,
      endUtf16: endUtf16,
      text: groupText,
    );
  }

  List<_AttributionDecision> _extractSpeakerCandidates(
    String text, {
    required String sourceSegmentId,
    required DialogueAttributionRule ruleUsed,
    required double exactConfidence,
    required double looseConfidence,
  }) {
    final candidates = <_AttributionDecision>[];

    final exactBeforeVerbMatch = _exactSpeakerBeforeVerbPattern.firstMatch(
      text,
    );
    final exactBeforeVerbLabel = exactBeforeVerbMatch?.group(1)?.trim();
    if (_isLikelySpeakerLabel(exactBeforeVerbLabel) &&
        exactBeforeVerbMatch != null) {
      candidates.add(
        _AttributionDecision(
          label: exactBeforeVerbLabel!,
          confidence: exactConfidence,
          ruleUsed: ruleUsed,
          evidenceSpan: _evidenceSpanForGroup(
            match: exactBeforeVerbMatch,
            groupIndex: 1,
            sourceSegmentId: sourceSegmentId,
          ),
        ),
      );
    }

    final exactVerbBeforeMatch = _exactVerbBeforeSpeakerPattern.firstMatch(
      text,
    );
    final exactVerbBeforeLabel = exactVerbBeforeMatch?.group(2)?.trim();
    if (_isLikelySpeakerLabel(exactVerbBeforeLabel) &&
        exactVerbBeforeMatch != null) {
      candidates.add(
        _AttributionDecision(
          label: exactVerbBeforeLabel!,
          confidence: exactConfidence,
          ruleUsed: ruleUsed,
          evidenceSpan: _evidenceSpanForGroup(
            match: exactVerbBeforeMatch,
            groupIndex: 2,
            sourceSegmentId: sourceSegmentId,
          ),
        ),
      );
    }

    final looseBeforeVerbMatch = _looseSpeakerBeforeVerbPattern.firstMatch(
      text,
    );
    final looseBeforeVerbLabel = looseBeforeVerbMatch?.group(1)?.trim();
    if (_isLikelySpeakerLabel(looseBeforeVerbLabel) &&
        looseBeforeVerbMatch != null) {
      candidates.add(
        _AttributionDecision(
          label: looseBeforeVerbLabel!,
          confidence: looseConfidence,
          ruleUsed: ruleUsed,
          evidenceSpan: _evidenceSpanForGroup(
            match: looseBeforeVerbMatch,
            groupIndex: 1,
            sourceSegmentId: sourceSegmentId,
          ),
        ),
      );
    }

    final looseVerbBeforeMatch = _looseVerbBeforeSpeakerPattern.firstMatch(
      text,
    );
    final looseVerbBeforeLabel = looseVerbBeforeMatch?.group(2)?.trim();
    if (_isLikelySpeakerLabel(looseVerbBeforeLabel) &&
        looseVerbBeforeMatch != null) {
      candidates.add(
        _AttributionDecision(
          label: looseVerbBeforeLabel!,
          confidence: looseConfidence,
          ruleUsed: ruleUsed,
          evidenceSpan: _evidenceSpanForGroup(
            match: looseVerbBeforeMatch,
            groupIndex: 2,
            sourceSegmentId: sourceSegmentId,
          ),
        ),
      );
    }

    return candidates;
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

class _AttributionDecision {
  const _AttributionDecision({
    required this.label,
    required this.confidence,
    required this.ruleUsed,
    required this.evidenceSpan,
  });

  final String label;
  final double confidence;
  final DialogueAttributionRule ruleUsed;
  final DialogueEvidenceSpan evidenceSpan;
}

class _ResolvedDialogueSpan {
  const _ResolvedDialogueSpan({required this.span, required this.outcome});

  final _DialogueSpanContext span;
  final DialogueAttributionOutcome outcome;

  bool get isAttributed =>
      outcome.resolution == DialogueAttributionResolution.attributedSpeaker;
}

enum _AdjacentDirection { before, after }

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
      segmentIds: sortedAnnotations
          .map((annotation) => annotation.segmentId)
          .toList(growable: false),
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
    required this.segmentIds,
    required this.combinedText,
  });

  final String dialogueSpanId;
  final String blockId;
  final int paragraphIndex;
  final int firstSegmentIndex;
  final int lastSegmentIndex;
  final List<String> segmentIds;
  final String combinedText;
}
