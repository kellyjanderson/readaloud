enum DialogueAttributionResolution { attributedSpeaker, unattributedDialogue }

enum DialogueAttributionProvenance {
  heuristicInference,
  explicitSourceMetadata,
  providerOutput,
}

enum DialogueAttributionRule {
  sameSentenceExplicit,
  adjacentAfter,
  adjacentBefore,
  paragraphOwnership,
  dialogueAlternation,
  actionBinding,
  pronounResolution,
  speakerPersistence,
  unknownBelowThreshold,
  noEvidence,
}

class DialogueAttributionSet {
  factory DialogueAttributionSet({
    required String documentId,
    required String attributionVersion,
    required String providerId,
    required String providerVersion,
    required List<DialogueAttributionOutcome> outcomes,
  }) {
    if (documentId.trim().isEmpty) {
      throw ArgumentError.value(
        documentId,
        'documentId',
        'documentId must not be empty.',
      );
    }
    if (attributionVersion.trim().isEmpty) {
      throw ArgumentError.value(
        attributionVersion,
        'attributionVersion',
        'attributionVersion must not be empty.',
      );
    }
    if (providerId.trim().isEmpty) {
      throw ArgumentError.value(
        providerId,
        'providerId',
        'providerId must not be empty.',
      );
    }
    if (providerVersion.trim().isEmpty) {
      throw ArgumentError.value(
        providerVersion,
        'providerVersion',
        'providerVersion must not be empty.',
      );
    }

    final seenIds = <String>{};
    final seenSpanIds = <String>{};
    for (final outcome in outcomes) {
      if (!seenIds.add(outcome.attributionId)) {
        throw ArgumentError.value(
          outcomes,
          'outcomes',
          'attributionId values must be unique within one DialogueAttributionSet.',
        );
      }
      if (!seenSpanIds.add(outcome.dialogueSpanId)) {
        throw ArgumentError.value(
          outcomes,
          'outcomes',
          'dialogueSpanId values must be unique within one DialogueAttributionSet.',
        );
      }
    }

    return DialogueAttributionSet._(
      documentId: documentId,
      attributionVersion: attributionVersion,
      providerId: providerId,
      providerVersion: providerVersion,
      outcomes: List<DialogueAttributionOutcome>.unmodifiable(outcomes),
    );
  }

  const DialogueAttributionSet._({
    required this.documentId,
    required this.attributionVersion,
    required this.providerId,
    required this.providerVersion,
    required this.outcomes,
  });

  final String documentId;
  final String attributionVersion;
  final String providerId;
  final String providerVersion;
  final List<DialogueAttributionOutcome> outcomes;

  DialogueAttributionOutcome? forDialogueSpan(String dialogueSpanId) {
    for (final outcome in outcomes) {
      if (outcome.dialogueSpanId == dialogueSpanId) {
        return outcome;
      }
    }
    return null;
  }
}

class DialogueAttributionOutcome {
  factory DialogueAttributionOutcome({
    required String attributionId,
    required String dialogueSpanId,
    required DialogueAttributionResolution resolution,
    required double confidence,
    required DialogueAttributionProvenance provenance,
    required DialogueAttributionRule ruleUsed,
    SpeakerReference? speakerReference,
    DialogueEvidenceSpan? evidenceSpan,
  }) {
    if (attributionId.trim().isEmpty) {
      throw ArgumentError.value(
        attributionId,
        'attributionId',
        'attributionId must not be empty.',
      );
    }
    if (dialogueSpanId.trim().isEmpty) {
      throw ArgumentError.value(
        dialogueSpanId,
        'dialogueSpanId',
        'dialogueSpanId must not be empty.',
      );
    }
    if (confidence < 0.0 || confidence > 1.0) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'confidence must be between 0.0 and 1.0.',
      );
    }
    if (resolution == DialogueAttributionResolution.attributedSpeaker &&
        speakerReference == null) {
      throw ArgumentError.value(
        speakerReference,
        'speakerReference',
        'Attributed-speaker outcomes must carry a speaker reference.',
      );
    }
    if (resolution == DialogueAttributionResolution.unattributedDialogue &&
        speakerReference != null) {
      throw ArgumentError.value(
        speakerReference,
        'speakerReference',
        'Unattributed dialogue outcomes must not carry a speaker reference.',
      );
    }
    if (resolution == DialogueAttributionResolution.attributedSpeaker &&
        evidenceSpan == null) {
      throw ArgumentError.value(
        evidenceSpan,
        'evidenceSpan',
        'Attributed-speaker outcomes must carry an evidence span.',
      );
    }

    return DialogueAttributionOutcome._(
      attributionId: attributionId,
      dialogueSpanId: dialogueSpanId,
      resolution: resolution,
      confidence: confidence,
      provenance: provenance,
      ruleUsed: ruleUsed,
      speakerReference: speakerReference,
      evidenceSpan: evidenceSpan,
    );
  }

  const DialogueAttributionOutcome._({
    required this.attributionId,
    required this.dialogueSpanId,
    required this.resolution,
    required this.confidence,
    required this.provenance,
    required this.ruleUsed,
    required this.speakerReference,
    required this.evidenceSpan,
  });

  final String attributionId;
  final String dialogueSpanId;
  final DialogueAttributionResolution resolution;
  final double confidence;
  final DialogueAttributionProvenance provenance;
  final DialogueAttributionRule ruleUsed;
  final SpeakerReference? speakerReference;
  final DialogueEvidenceSpan? evidenceSpan;
}

class SpeakerReference {
  factory SpeakerReference({
    required String referenceId,
    required String displayLabel,
    required String normalizedLabel,
  }) {
    if (referenceId.trim().isEmpty) {
      throw ArgumentError.value(
        referenceId,
        'referenceId',
        'referenceId must not be empty.',
      );
    }
    if (displayLabel.trim().isEmpty) {
      throw ArgumentError.value(
        displayLabel,
        'displayLabel',
        'displayLabel must not be empty.',
      );
    }
    if (normalizedLabel.trim().isEmpty) {
      throw ArgumentError.value(
        normalizedLabel,
        'normalizedLabel',
        'normalizedLabel must not be empty.',
      );
    }

    return SpeakerReference._(
      referenceId: referenceId,
      displayLabel: displayLabel,
      normalizedLabel: normalizedLabel,
    );
  }

  const SpeakerReference._({
    required this.referenceId,
    required this.displayLabel,
    required this.normalizedLabel,
  });

  final String referenceId;
  final String displayLabel;
  final String normalizedLabel;
}

class DialogueEvidenceSpan {
  factory DialogueEvidenceSpan({
    required String segmentId,
    required int startUtf16,
    required int endUtf16,
    required String text,
  }) {
    if (segmentId.trim().isEmpty) {
      throw ArgumentError.value(
        segmentId,
        'segmentId',
        'segmentId must not be empty.',
      );
    }
    if (startUtf16 < 0 || endUtf16 < startUtf16) {
      throw ArgumentError.value(
        <int>[startUtf16, endUtf16],
        'startUtf16/endUtf16',
        'Evidence offsets must be non-negative and ordered.',
      );
    }
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'text must not be empty.');
    }

    return DialogueEvidenceSpan._(
      segmentId: segmentId,
      startUtf16: startUtf16,
      endUtf16: endUtf16,
      text: text,
    );
  }

  const DialogueEvidenceSpan._({
    required this.segmentId,
    required this.startUtf16,
    required this.endUtf16,
    required this.text,
  });

  final String segmentId;
  final int startUtf16;
  final int endUtf16;
  final String text;
}
