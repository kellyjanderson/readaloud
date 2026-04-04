enum SpeechAnnotationKind {
  phraseBoundary,
  pauseCandidate,
  emphasisCandidate,
  pronunciationCandidate,
  sayAsCandidate,
  discourseRole,
  dialogueSpan,
}

enum SpeechAnnotationSource {
  importerStructuralInference,
  ruleBasedLinguisticInference,
  explicitSourceMetadata,
  userOverride,
}

enum BreakClass { none, weak, sentence, paragraph, section }

const Set<String> supportedDiscourseRoles = <String>{
  'heading',
  'narration',
  'quotation',
  'dialogue',
  'list_item',
  'caption',
};

const Set<String> supportedDialogueSpanClasses = <String>{
  'dialogue',
  'quotation',
};

const Set<String> supportedSayAsClasses = <String>{'letters', 'cardinal'};

class BaseSpeechAnnotationSet {
  factory BaseSpeechAnnotationSet({
    required String documentId,
    required String annotationVersion,
    required List<SpeechAnnotation> annotations,
  }) {
    if (documentId.trim().isEmpty) {
      throw ArgumentError.value(
        documentId,
        'documentId',
        'documentId must not be empty.',
      );
    }
    if (annotationVersion.trim().isEmpty) {
      throw ArgumentError.value(
        annotationVersion,
        'annotationVersion',
        'annotationVersion must not be empty.',
      );
    }

    final seenIds = <String>{};
    for (final annotation in annotations) {
      if (!seenIds.add(annotation.annotationId)) {
        throw ArgumentError.value(
          annotations,
          'annotations',
          'annotationId values must be unique within one BaseSpeechAnnotationSet.',
        );
      }
    }

    return BaseSpeechAnnotationSet._(
      documentId: documentId,
      annotationVersion: annotationVersion,
      annotations: List<SpeechAnnotation>.unmodifiable(annotations),
    );
  }

  const BaseSpeechAnnotationSet._({
    required this.documentId,
    required this.annotationVersion,
    required this.annotations,
  });

  final String documentId;
  final String annotationVersion;
  final List<SpeechAnnotation> annotations;

  Iterable<SpeechAnnotation> forSegment(String segmentId) =>
      annotations.where((annotation) => annotation.segmentId == segmentId);

  Iterable<SpeechAnnotation> forDialogueSpan(String dialogueSpanId) =>
      annotations.where(
        (annotation) => annotation.dialogueSpanId == dialogueSpanId,
      );

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'annotationVersion': annotationVersion,
      'annotations': annotations
          .map((annotation) => annotation.toJson())
          .toList(growable: false),
    };
  }
}

class SpeechAnnotation {
  factory SpeechAnnotation({
    required String annotationId,
    required String segmentId,
    required SpeechAnnotationKind kind,
    required int startWord,
    required int endWord,
    required double confidence,
    required SpeechAnnotationSource source,
    BreakClass? breakClass,
    PronunciationCandidatePayload? pronunciationCandidate,
    String? sayAsClass,
    String? discourseRole,
    String? dialogueSpanId,
    String? dialogueSpanClass,
  }) {
    final normalizedDiscourseRole = discourseRole?.trim();
    final normalizedDialogueSpanId = dialogueSpanId?.trim();
    final normalizedDialogueSpanClass = dialogueSpanClass?.trim();
    final normalizedSayAsClass = sayAsClass?.trim();

    if (annotationId.trim().isEmpty) {
      throw ArgumentError.value(
        annotationId,
        'annotationId',
        'annotationId must not be empty.',
      );
    }
    if (segmentId.trim().isEmpty) {
      throw ArgumentError.value(
        segmentId,
        'segmentId',
        'segmentId must not be empty.',
      );
    }
    if (startWord < 0 || endWord < 0) {
      throw ArgumentError.value(
        <int>[startWord, endWord],
        'startWord/endWord',
        'Word offsets must not be negative.',
      );
    }
    if (endWord < startWord) {
      throw ArgumentError.value(
        <int>[startWord, endWord],
        'startWord/endWord',
        'endWord must be greater than or equal to startWord.',
      );
    }
    final normalizedConfidence = source == SpeechAnnotationSource.userOverride
        ? 1.0
        : confidence;
    if (normalizedConfidence < 0.0 || normalizedConfidence > 1.0) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'confidence must be between 0.0 and 1.0.',
      );
    }

    final isBoundaryKind =
        kind == SpeechAnnotationKind.phraseBoundary ||
        kind == SpeechAnnotationKind.pauseCandidate;
    if (!isBoundaryKind && startWord == endWord) {
      throw ArgumentError.value(
        <int>[startWord, endWord],
        'startWord/endWord',
        'Non-boundary annotations must span at least one word.',
      );
    }
    if (kind == SpeechAnnotationKind.pronunciationCandidate &&
        pronunciationCandidate == null) {
      throw ArgumentError.value(
        pronunciationCandidate,
        'pronunciationCandidate',
        'Pronunciation candidate annotations must carry a pronunciation candidate payload.',
      );
    }
    if (kind != SpeechAnnotationKind.pronunciationCandidate &&
        pronunciationCandidate != null) {
      throw ArgumentError.value(
        pronunciationCandidate,
        'pronunciationCandidate',
        'Pronunciation candidate payloads are only valid on pronunciation candidate annotations.',
      );
    }
    if (kind == SpeechAnnotationKind.sayAsCandidate) {
      if (normalizedSayAsClass == null ||
          !supportedSayAsClasses.contains(normalizedSayAsClass)) {
        throw ArgumentError.value(
          sayAsClass,
          'sayAsClass',
          'Say-as candidate annotations must use a supported say-as class.',
        );
      }
    } else if (normalizedSayAsClass != null) {
      throw ArgumentError.value(
        sayAsClass,
        'sayAsClass',
        'sayAsClass is only valid on say-as candidate annotations.',
      );
    }
    if (kind == SpeechAnnotationKind.discourseRole) {
      if (normalizedDiscourseRole == null ||
          !supportedDiscourseRoles.contains(normalizedDiscourseRole)) {
        throw ArgumentError.value(
          discourseRole,
          'discourseRole',
          'Discourse-role annotations must use a supported discourse role.',
        );
      }
    } else if (normalizedDiscourseRole != null) {
      throw ArgumentError.value(
        discourseRole,
        'discourseRole',
        'discourseRole is only valid on discourse-role annotations.',
      );
    }
    if (kind == SpeechAnnotationKind.dialogueSpan) {
      if (normalizedDialogueSpanId == null ||
          normalizedDialogueSpanId.isEmpty) {
        throw ArgumentError.value(
          dialogueSpanId,
          'dialogueSpanId',
          'Dialogue-span annotations must carry a dialogue span id.',
        );
      }
      if (normalizedDialogueSpanClass == null ||
          !supportedDialogueSpanClasses.contains(normalizedDialogueSpanClass)) {
        throw ArgumentError.value(
          dialogueSpanClass,
          'dialogueSpanClass',
          'Dialogue-span annotations must use a supported dialogue span class.',
        );
      }
    } else if (normalizedDialogueSpanId != null ||
        normalizedDialogueSpanClass != null) {
      throw ArgumentError.value(
        <String?>[dialogueSpanId, dialogueSpanClass],
        'dialogueSpanId/dialogueSpanClass',
        'Dialogue-span fields are only valid on dialogue-span annotations.',
      );
    }

    return SpeechAnnotation._(
      annotationId: annotationId,
      segmentId: segmentId,
      kind: kind,
      startWord: startWord,
      endWord: endWord,
      confidence: normalizedConfidence,
      source: source,
      breakClass: breakClass,
      pronunciationCandidate: pronunciationCandidate,
      sayAsClass: normalizedSayAsClass,
      discourseRole: normalizedDiscourseRole,
      dialogueSpanId: normalizedDialogueSpanId,
      dialogueSpanClass: normalizedDialogueSpanClass,
    );
  }

  const SpeechAnnotation._({
    required this.annotationId,
    required this.segmentId,
    required this.kind,
    required this.startWord,
    required this.endWord,
    required this.confidence,
    required this.source,
    this.breakClass,
    this.pronunciationCandidate,
    this.sayAsClass,
    this.discourseRole,
    this.dialogueSpanId,
    this.dialogueSpanClass,
  });

  final String annotationId;
  final String segmentId;
  final SpeechAnnotationKind kind;
  final int startWord;
  final int endWord;
  final double confidence;
  final SpeechAnnotationSource source;
  final BreakClass? breakClass;
  final PronunciationCandidatePayload? pronunciationCandidate;
  final String? sayAsClass;
  final String? discourseRole;
  final String? dialogueSpanId;
  final String? dialogueSpanClass;

  bool get isBoundaryAnnotation =>
      kind == SpeechAnnotationKind.phraseBoundary ||
      kind == SpeechAnnotationKind.pauseCandidate;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'annotationId': annotationId,
      'segmentId': segmentId,
      'kind': kind.name,
      'startWord': startWord,
      'endWord': endWord,
      'confidence': confidence,
      'source': source.name,
      'breakClass': breakClass?.name,
      'pronunciationCandidate': pronunciationCandidate?.toJson(),
      'sayAsClass': sayAsClass,
      'discourseRole': discourseRole,
      'dialogueSpanId': dialogueSpanId,
      'dialogueSpanClass': dialogueSpanClass,
    };
  }
}

class PronunciationCandidatePayload {
  const PronunciationCandidatePayload({
    required this.surfaceText,
    required this.normalizedSurfaceText,
    required this.representationType,
    required this.representationValue,
    required this.accentFamily,
    required this.priorityHint,
  });

  final String surfaceText;
  final String normalizedSurfaceText;
  final String representationType;
  final String representationValue;
  final String? accentFamily;
  final int priorityHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'surfaceText': surfaceText,
      'normalizedSurfaceText': normalizedSurfaceText,
      'representationType': representationType,
      'representationValue': representationValue,
      'accentFamily': accentFamily,
      'priorityHint': priorityHint,
    };
  }
}
