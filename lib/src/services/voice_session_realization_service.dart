import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../models/narration_state.dart';
import '../models/pronunciation_artifact.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';
import '../models/tts_artifact.dart';
import '../models/voice_session_realization.dart';
import 'pronunciation_rule_module.dart';

class VoiceSessionRealizationService {
  const VoiceSessionRealizationService();

  static const _preferredLookAheadSegments = 2;

  VoiceSessionRealization realize(VoiceSessionRealizationInput input) {
    final startIndex =
        input.speechDocument.segmentIndexById[input.startSegmentId] ?? 0;
    final windowSegments = _selectWindowSegments(
      input.speechDocument,
      startIndex,
    );
    if (windowSegments.isEmpty) {
      final emptySet = TtsArtifactSet(
        documentId: input.speechDocument.documentId,
        sessionId: input.narrationState.sessionId,
        engineId: input.engineId,
        voiceId: input.voiceId,
        rate: input.rate,
        selectedProfileId: input.selectedProfile.profileId,
        startSegmentId: input.startSegmentId,
        endSegmentId: input.startSegmentId,
        segments: const <TtsArtifactSegment>[],
      );
      return VoiceSessionRealization(
        realizationId: _realizationId(
          input: input,
          segmentIds: const <String>[],
          artifactIds: const <String>[],
          boundaryIntentKeys: const <String>[],
          emphasisIntentKeys: const <String>[],
        ),
        startSegmentId: input.startSegmentId,
        endSegmentId: input.startSegmentId,
        voiceId: input.voiceId,
        engineId: input.engineId,
        rate: input.rate,
        selectedProfileId: input.selectedProfile.profileId,
        artifacts: const <RealizedPronunciationArtifact>[],
        boundaryIntents: const <RealizedBoundaryIntent>[],
        emphasisIntents: const <RealizedEmphasisIntent>[],
        ttsArtifactSet: emptySet,
      );
    }

    final realizedArtifacts = <RealizedPronunciationArtifact>[];
    final realizedBoundaryIntents = <RealizedBoundaryIntent>[];
    final realizedEmphasisIntents = <RealizedEmphasisIntent>[];
    final ttsSegments = <TtsArtifactSegment>[];

    for (final segment in windowSegments) {
      final segmentAnnotations = input.baseAnnotations
          .forSegment(segment.segmentId)
          .toList(growable: false);
      final segmentArtifacts = input.basePronunciationArtifacts
          .forSegment(segment.segmentId)
          .map(
            (artifact) => _realizeArtifact(
              artifact: artifact,
              input: input,
              segment: segment,
            ),
          )
          .toList(growable: false);
      final segmentBoundaryIntents = _realizeBoundaryIntents(
        annotations: segmentAnnotations,
        input: input,
        segment: segment,
      );
      final segmentEmphasisIntents = _realizeEmphasisIntents(
        annotations: segmentAnnotations,
        input: input,
        segment: segment,
      );
      final segmentDiagnosticCodes = <String>{
        for (final intent in segmentBoundaryIntents) ...intent.diagnosticCodes,
        for (final intent in segmentEmphasisIntents) ...intent.diagnosticCodes,
      };
      realizedArtifacts.addAll(segmentArtifacts);
      realizedBoundaryIntents.addAll(segmentBoundaryIntents);
      realizedEmphasisIntents.addAll(segmentEmphasisIntents);
      ttsSegments.add(
        TtsArtifactSegment(
          segmentId: segment.segmentId,
          speakText: segment.normalizedText,
          pronunciationArtifacts: segmentArtifacts,
          boundaryIntents: segmentBoundaryIntents,
          emphasisIntents: segmentEmphasisIntents,
          diagnosticCodes: segmentDiagnosticCodes.toList(growable: false),
        ),
      );
    }

    final ttsArtifactSet = TtsArtifactSet(
      documentId: input.speechDocument.documentId,
      sessionId: input.narrationState.sessionId,
      engineId: input.engineId,
      voiceId: input.voiceId,
      rate: input.rate,
      selectedProfileId: input.selectedProfile.profileId,
      startSegmentId: windowSegments.first.segmentId,
      endSegmentId: windowSegments.last.segmentId,
      segments: ttsSegments,
    );

    return VoiceSessionRealization(
      realizationId: _realizationId(
        input: input,
        segmentIds: windowSegments
            .map((segment) => segment.segmentId)
            .toList(growable: false),
        artifactIds: realizedArtifacts
            .map((artifact) => artifact.artifactId)
            .toList(growable: false),
        boundaryIntentKeys: realizedBoundaryIntents
            .map(
              (intent) =>
                  '${intent.annotationId}:${intent.engineTreatment}:${intent.breakClass}',
            )
            .toList(growable: false),
        emphasisIntentKeys: realizedEmphasisIntents
            .map(
              (intent) =>
                  '${intent.annotationId}:${intent.engineTreatment}:${intent.confidence.toStringAsFixed(3)}',
            )
            .toList(growable: false),
      ),
      startSegmentId: windowSegments.first.segmentId,
      endSegmentId: windowSegments.last.segmentId,
      voiceId: input.voiceId,
      engineId: input.engineId,
      rate: input.rate,
      selectedProfileId: input.selectedProfile.profileId,
      artifacts: realizedArtifacts,
      boundaryIntents: realizedBoundaryIntents,
      emphasisIntents: realizedEmphasisIntents,
      ttsArtifactSet: ttsArtifactSet,
    );
  }
}

List<RealizedBoundaryIntent> _realizeBoundaryIntents({
  required List<SpeechAnnotation> annotations,
  required VoiceSessionRealizationInput input,
  required SpeechSegment segment,
}) {
  final boundaryAnnotations =
      annotations
          .where(
            (annotation) =>
                annotation.kind == SpeechAnnotationKind.phraseBoundary ||
                annotation.kind == SpeechAnnotationKind.pauseCandidate,
          )
          .toList(growable: false)
        ..sort((left, right) {
          final leftStrength = _boundaryStrength(left);
          final rightStrength = _boundaryStrength(right);
          if (left.startWord != right.startWord) {
            return left.startWord.compareTo(right.startWord);
          }
          return rightStrength.compareTo(leftStrength);
        });

  final strongestByBoundary = <String, SpeechAnnotation>{};
  for (final annotation in boundaryAnnotations) {
    final key = '${annotation.startWord}:${annotation.endWord}';
    final existing = strongestByBoundary[key];
    if (existing == null ||
        _boundaryStrength(annotation) > _boundaryStrength(existing)) {
      strongestByBoundary[key] = annotation;
    }
  }

  return strongestByBoundary.values
      .map((annotation) {
        final engineTreatment = _boundaryEngineTreatment(
          annotation: annotation,
          engineId: input.engineId,
        );
        return RealizedBoundaryIntent(
          annotationId: annotation.annotationId,
          segmentId: segment.segmentId,
          startWord: annotation.startWord,
          endWord: annotation.endWord,
          breakClass: (annotation.breakClass ?? BreakClass.none).name,
          sourceKind: annotation.kind == SpeechAnnotationKind.pauseCandidate
              ? 'pause_candidate'
              : 'phrase_boundary',
          engineTreatment: engineTreatment,
          confidence: annotation.confidence,
          diagnosticCodes: <String>[
            'boundary.intent.${annotation.kind == SpeechAnnotationKind.pauseCandidate ? 'pause' : 'phrase'}',
            'boundary.intent.$engineTreatment',
          ],
        );
      })
      .toList(growable: false)
    ..sort((left, right) {
      if (left.startWord != right.startWord) {
        return left.startWord.compareTo(right.startWord);
      }
      return left.endWord.compareTo(right.endWord);
    });
}

List<RealizedEmphasisIntent> _realizeEmphasisIntents({
  required List<SpeechAnnotation> annotations,
  required VoiceSessionRealizationInput input,
  required SpeechSegment segment,
}) {
  final emphasisAnnotations = annotations
      .where(
        (annotation) =>
            annotation.kind == SpeechAnnotationKind.emphasisCandidate,
      )
      .toList(growable: false);

  return emphasisAnnotations
      .map((annotation) {
        final confidence = _normalizedEmphasisConfidence(
          baseConfidence: annotation.confidence,
          recentEmphasisDensity: input.narrationState.recentEmphasisDensity,
        );
        final engineTreatment = _emphasisEngineTreatment(
          engineId: input.engineId,
        );
        return RealizedEmphasisIntent(
          annotationId: annotation.annotationId,
          segmentId: segment.segmentId,
          startWord: annotation.startWord,
          endWord: annotation.endWord,
          confidence: confidence,
          engineTreatment: engineTreatment,
          diagnosticCodes: <String>[
            'emphasis.intent.$engineTreatment',
            if (confidence != annotation.confidence)
              'emphasis.intent.continuity_adjusted',
          ],
        );
      })
      .toList(growable: false);
}

List<SpeechSegment> _selectWindowSegments(
  SpeechDocument speechDocument,
  int startIndex,
) {
  if (speechDocument.segments.isEmpty) {
    return const <SpeechSegment>[];
  }
  if (startIndex >= speechDocument.segments.length) {
    return <SpeechSegment>[speechDocument.segments.last];
  }

  final selected = <SpeechSegment>[speechDocument.segments[startIndex]];
  final anchorParagraph = speechDocument.segments[startIndex].paragraphIndex;
  for (
    var index = startIndex + 1;
    index < speechDocument.segments.length &&
        index <=
            startIndex +
                VoiceSessionRealizationService._preferredLookAheadSegments;
    index += 1
  ) {
    final segment = speechDocument.segments[index];
    if (segment.paragraphIndex != anchorParagraph) {
      break;
    }
    selected.add(segment);
  }
  return selected;
}

RealizedPronunciationArtifact _realizeArtifact({
  required PronunciationArtifact artifact,
  required VoiceSessionRealizationInput input,
  required SpeechSegment segment,
}) {
  final profileLayeredRepresentation = _selectRepresentation(
    representations:
        input.mergedPronunciationResources[artifact.normalizedSurfaceText] ??
        const <PronunciationRepresentation>[],
    voiceId: input.voiceId,
  );
  final activeRuleRepresentation = _resolveActiveRuleModuleArtifact(
    artifact: artifact,
    input: input,
    segment: segment,
  );
  if (activeRuleRepresentation != null) {
    return RealizedPronunciationArtifact(
      artifactId: artifact.artifactId,
      segmentId: artifact.segmentId,
      startWord: artifact.startWord,
      endWord: artifact.endWord,
      resolutionClass: 'context_resolved',
      selectedRepresentation: activeRuleRepresentation,
      translationIntent: _translationIntentFor(activeRuleRepresentation),
      diagnosticCodes: const <String>[
        'pronunciation.context_sensitive.resolved',
        'pronunciation.profile.active_rule_module',
      ],
    );
  }

  final userOverride = _lookupUserOverride(
    narrationState: input.narrationState,
    artifact: artifact,
  );
  if (userOverride != null) {
    return RealizedPronunciationArtifact(
      artifactId: artifact.artifactId,
      segmentId: artifact.segmentId,
      startWord: artifact.startWord,
      endWord: artifact.endWord,
      resolutionClass: 'context_resolved',
      selectedRepresentation: PronunciationRepresentation(
        representationId: '${artifact.artifactId}_user_override',
        representationType: 'normalized_spoken_text',
        representationValue: userOverride,
        accentFamily: _accentFamilyForVoice(input.voiceId),
        priority: 1000,
      ),
      translationIntent: 'normalized_spoken_text',
      diagnosticCodes: const <String>[
        'pronunciation.context_sensitive.resolved',
      ],
    );
  }

  switch (artifact.artifactClass) {
    case PronunciationArtifactClass.resolvedLexicalCase:
      final shouldPreferArtifactRepresentations =
          artifact.source == PronunciationArtifactSource.userOverride;
      final selectedRepresentation = _selectRepresentation(
        representations:
            shouldPreferArtifactRepresentations ||
                profileLayeredRepresentation == null
            ? artifact.representations
            : <PronunciationRepresentation>[profileLayeredRepresentation],
        voiceId: input.voiceId,
      );
      return RealizedPronunciationArtifact(
        artifactId: artifact.artifactId,
        segmentId: artifact.segmentId,
        startWord: artifact.startWord,
        endWord: artifact.endWord,
        resolutionClass: 'direct_resolved',
        selectedRepresentation: selectedRepresentation,
        translationIntent: _translationIntentFor(selectedRepresentation),
        diagnosticCodes: artifact.diagnosticCodes,
      );
    case PronunciationArtifactClass.contextSensitiveCase:
      if (profileLayeredRepresentation != null) {
        return RealizedPronunciationArtifact(
          artifactId: artifact.artifactId,
          segmentId: artifact.segmentId,
          startWord: artifact.startWord,
          endWord: artifact.endWord,
          resolutionClass: 'context_resolved',
          selectedRepresentation: profileLayeredRepresentation,
          translationIntent: _translationIntentFor(
            profileLayeredRepresentation,
          ),
          diagnosticCodes: const <String>[
            'pronunciation.context_sensitive.resolved',
            'pronunciation.profile.resource_layer',
          ],
        );
      }
      final resolvedRepresentation = _resolveContextSensitiveArtifact(
        artifact: artifact,
        voiceId: input.voiceId,
        segment: segment,
      );
      if (resolvedRepresentation != null) {
        return RealizedPronunciationArtifact(
          artifactId: artifact.artifactId,
          segmentId: artifact.segmentId,
          startWord: artifact.startWord,
          endWord: artifact.endWord,
          resolutionClass: 'context_resolved',
          selectedRepresentation: resolvedRepresentation,
          translationIntent: _translationIntentFor(resolvedRepresentation),
          diagnosticCodes: const <String>[
            'pronunciation.context_sensitive.resolved',
          ],
        );
      }
      return RealizedPronunciationArtifact(
        artifactId: artifact.artifactId,
        segmentId: artifact.segmentId,
        startWord: artifact.startWord,
        endWord: artifact.endWord,
        resolutionClass: 'deferred_to_engine',
        selectedRepresentation: null,
        translationIntent: 'engine_default',
        diagnosticCodes: const <String>['pronunciation.translation.deferred'],
      );
    case PronunciationArtifactClass.unresolvedCase:
      if (profileLayeredRepresentation != null) {
        return RealizedPronunciationArtifact(
          artifactId: artifact.artifactId,
          segmentId: artifact.segmentId,
          startWord: artifact.startWord,
          endWord: artifact.endWord,
          resolutionClass: 'direct_resolved',
          selectedRepresentation: profileLayeredRepresentation,
          translationIntent: _translationIntentFor(
            profileLayeredRepresentation,
          ),
          diagnosticCodes: const <String>[
            'pronunciation.profile.resource_layer',
            'pronunciation.unresolved.resolved_in_voice_session',
          ],
        );
      }
      return RealizedPronunciationArtifact(
        artifactId: artifact.artifactId,
        segmentId: artifact.segmentId,
        startWord: artifact.startWord,
        endWord: artifact.endWord,
        resolutionClass: 'unresolved',
        selectedRepresentation: null,
        translationIntent: 'engine_default',
        diagnosticCodes: const <String>[
          'pronunciation.unresolved.voice_session',
        ],
      );
  }
}

PronunciationRepresentation? _resolveActiveRuleModuleArtifact({
  required PronunciationArtifact artifact,
  required VoiceSessionRealizationInput input,
  required SpeechSegment segment,
}) {
  final previousToken = artifact.startWord > 0
      ? segment.wordSpans[artifact.startWord - 1].text
      : null;
  final nextToken = artifact.endWord < segment.wordSpans.length
      ? segment.wordSpans[artifact.endWord].text
      : null;

  for (final module in input.enabledActiveRuleModules) {
    if (!module.supportsSessionTime) {
      continue;
    }
    final decision = module.apply(
      PronunciationRuleModuleContext(
        segmentId: segment.segmentId,
        segmentText: segment.normalizedText,
        tokenIndex: artifact.startWord,
        surfaceText: artifact.surfaceText,
        normalizedSurfaceText: artifact.normalizedSurfaceText,
        selectedProfile: input.selectedProfile,
        mergedResources: input.mergedPronunciationResources,
        previousToken: previousToken,
        nextToken: nextToken,
      ),
    );
    if (decision.kind == PronunciationRuleModuleDecisionKind.resolved &&
        decision.representations.isNotEmpty) {
      return _selectRepresentation(
        representations: decision.representations,
        voiceId: input.voiceId,
      );
    }
  }
  return null;
}

PronunciationRepresentation? _resolveContextSensitiveArtifact({
  required PronunciationArtifact artifact,
  required String voiceId,
  required SpeechSegment segment,
}) {
  return _selectRepresentation(
    representations: artifact.representations,
    voiceId: voiceId,
  );
}

String? _lookupUserOverride({
  required NarrationState narrationState,
  required PronunciationArtifact artifact,
}) {
  final byArtifactId =
      narrationState.localPronunciationChoices[artifact.artifactId];
  if (byArtifactId != null && byArtifactId.trim().isNotEmpty) {
    return byArtifactId.trim();
  }
  final byFullSpan = narrationState.localPronunciationChoices[artifact.spanKey];
  if (byFullSpan != null && byFullSpan.trim().isNotEmpty) {
    return byFullSpan.trim();
  }
  final legacySpanKey = '${artifact.startWord}:${artifact.endWord}';
  final legacyValue = narrationState.localPronunciationChoices[legacySpanKey];
  if (legacyValue != null && legacyValue.trim().isNotEmpty) {
    return legacyValue.trim();
  }
  return null;
}

PronunciationRepresentation? _selectRepresentation({
  required List<PronunciationRepresentation> representations,
  required String voiceId,
}) {
  if (representations.isEmpty) {
    return null;
  }
  final activeAccent = _accentFamilyForVoice(voiceId);
  final sorted = representations.toList(growable: false)
    ..sort((left, right) {
      final leftAccentScore = _accentScore(
        candidateAccent: left.accentFamily,
        activeAccent: activeAccent,
      );
      final rightAccentScore = _accentScore(
        candidateAccent: right.accentFamily,
        activeAccent: activeAccent,
      );
      if (leftAccentScore != rightAccentScore) {
        return rightAccentScore.compareTo(leftAccentScore);
      }
      return right.priority.compareTo(left.priority);
    });
  return sorted.first;
}

int _accentScore({
  required String? candidateAccent,
  required String? activeAccent,
}) {
  if (candidateAccent == null) {
    return 1;
  }
  if (candidateAccent == activeAccent) {
    return 2;
  }
  return 0;
}

String? _accentFamilyForVoice(String voiceId) {
  if (voiceId.startsWith('af_') || voiceId.startsWith('am_')) {
    return 'en-us';
  }
  if (voiceId.startsWith('bf_') || voiceId.startsWith('bm_')) {
    return 'en-gb';
  }
  return null;
}

String _translationIntentFor(PronunciationRepresentation? representation) {
  if (representation == null) {
    return 'engine_default';
  }
  return switch (representation.representationType) {
    'phoneme_string' => 'phoneme_string',
    'explicit_suffix_phoneme' => 'explicit_suffix_phoneme',
    'normalized_spoken_text' => 'normalized_spoken_text',
    _ => 'engine_default',
  };
}

String _realizationId({
  required VoiceSessionRealizationInput input,
  required List<String> segmentIds,
  required List<String> artifactIds,
  required List<String> boundaryIntentKeys,
  required List<String> emphasisIntentKeys,
}) {
  final digest = crypto.sha256.convert(
    utf8.encode(
      [
        input.speechDocument.normalizationVersion,
        input.baseAnnotations.annotationVersion,
        input.startSegmentId,
        input.voiceId,
        input.engineId,
        input.selectedProfile.profileId,
        input.rate.toStringAsFixed(3),
        _narrationStateSignature(input.narrationState),
        segmentIds.join(','),
        artifactIds.join(','),
        boundaryIntentKeys.join(','),
        emphasisIntentKeys.join(','),
      ].join('|'),
    ),
  );
  return 'real_${digest.toString().substring(0, 16)}';
}

int _boundaryStrength(SpeechAnnotation annotation) {
  final breakClass = annotation.breakClass ?? BreakClass.none;
  final kindBonus = annotation.kind == SpeechAnnotationKind.pauseCandidate
      ? 10
      : 0;
  final classStrength = switch (breakClass) {
    BreakClass.none => 0,
    BreakClass.weak => 1,
    BreakClass.sentence => 2,
    BreakClass.paragraph => 3,
    BreakClass.section => 4,
  };
  return kindBonus + classStrength;
}

String _boundaryEngineTreatment({
  required SpeechAnnotation annotation,
  required String engineId,
}) {
  final breakClass = annotation.breakClass ?? BreakClass.none;
  if (breakClass == BreakClass.none) {
    return 'ignored';
  }
  if (engineId == 'kokoro') {
    if (annotation.kind == SpeechAnnotationKind.pauseCandidate) {
      return 'approximated';
    }
    return breakClass == BreakClass.weak ? 'deferred' : 'approximated';
  }
  return 'direct';
}

String _emphasisEngineTreatment({required String engineId}) {
  return switch (engineId) {
    'kokoro' => 'approximated',
    _ => 'direct',
  };
}

double _normalizedEmphasisConfidence({
  required double baseConfidence,
  required double recentEmphasisDensity,
}) {
  final attenuation = recentEmphasisDensity.clamp(0.0, 1.0) * 0.25;
  final normalized = baseConfidence * (1.0 - attenuation);
  if (normalized < 0.0) {
    return 0.0;
  }
  if (normalized > 1.0) {
    return 1.0;
  }
  return normalized;
}

String _narrationStateSignature(NarrationState narrationState) {
  final sortedPronunciationChoices =
      narrationState.localPronunciationChoices.entries.toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
  return jsonEncode(<String, Object?>{
    'currentSectionMode': narrationState.currentSectionMode,
    'discourseMode': narrationState.discourseMode,
    'recentBoundaryClass': narrationState.recentBoundaryClass,
    'continuationPending': narrationState.continuationPending,
    'recentEmphasisDensity': narrationState.recentEmphasisDensity,
    'recentRate': narrationState.recentRate,
    'quoteMode': narrationState.quoteMode,
    'localPronunciationChoices': <String, String>{
      for (final entry in sortedPronunciationChoices) entry.key: entry.value,
    },
  });
}
