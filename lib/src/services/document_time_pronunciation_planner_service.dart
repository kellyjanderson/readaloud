import '../models/import_diagnostic.dart';
import '../models/english_pronunciation_profile.dart';
import '../models/position_map.dart';
import '../models/pronunciation_artifact.dart';
import '../models/speech_annotation.dart';
import '../models/speech_document.dart';
import 'english_speech_preprocessor.dart';
import 'explicit_phoneme_override.dart';
import 'pronunciation_resource_layering_service.dart';
import 'pronunciation_rule_module.dart';

class DocumentTimePronunciationPlannerInput {
  const DocumentTimePronunciationPlannerInput({
    required this.speechDocument,
    required this.baseAnnotations,
    required this.positionMap,
    required this.normalizationVersion,
    required this.selectedProfile,
    required this.mergedPronunciationResources,
    required this.enabledDocumentTimeRuleModules,
    required this.diagnostics,
  });

  final SpeechDocument speechDocument;
  final BaseSpeechAnnotationSet baseAnnotations;
  final PositionMap positionMap;
  final String normalizationVersion;
  final EnglishPronunciationProfile selectedProfile;
  final MergedPronunciationResources mergedPronunciationResources;
  final List<PronunciationRuleModule> enabledDocumentTimeRuleModules;
  final List<ImportDiagnostic> diagnostics;
}

class DocumentTimePronunciationPlannerService {
  const DocumentTimePronunciationPlannerService();

  static const artifactVersion = 'read-aloud-pronunciation-artifacts-v1';

  BasePronunciationArtifactSet plan(
    DocumentTimePronunciationPlannerInput input,
  ) {
    final artifacts = <PronunciationArtifact>[];
    final seenSpans = <String>{};
    var ordinal = 0;

    for (final segment in input.speechDocument.segments) {
      for (final wordSpan in segment.wordSpans) {
        final surfaceText = wordSpan.text;
        final explicitOverride = parseExplicitPhonemeSuffixOverride(surfaceText);
        final normalizedSurfaceText =
            explicitOverride?.normalizedBaseSurfaceText ??
            _normalizedToken(surfaceText);
        if (normalizedSurfaceText.isEmpty) {
          continue;
        }

        final spanKey =
            '${segment.segmentId}:${wordSpan.wordIndexWithinSegment}:${wordSpan.wordIndexWithinSegment + 1}';
        if (!seenSpans.add(spanKey)) {
          continue;
        }

        if (explicitOverride != null) {
          artifacts.add(
            PronunciationArtifact(
              artifactId: 'pa_${ordinal++}',
              segmentId: segment.segmentId,
              startWord: wordSpan.wordIndexWithinSegment,
              endWord: wordSpan.wordIndexWithinSegment + 1,
              surfaceText: surfaceText,
              normalizedSurfaceText: normalizedSurfaceText,
              artifactClass: PronunciationArtifactClass.resolvedLexicalCase,
              source: PronunciationArtifactSource.userOverride,
              confidence: 1.0,
              representations: <PronunciationRepresentation>[
                PronunciationRepresentation(
                  representationId:
                      'explicit_suffix_${segment.segmentId}_${wordSpan.wordIndexWithinSegment}',
                  representationType: 'explicit_suffix_phoneme',
                  representationValue: explicitOverride.suffixPhoneme,
                  accentFamily: input.selectedProfile.accentFamily,
                  priority: 120,
                ),
              ],
              diagnosticCodes: <String>[
                'pronunciation.explicit_suffix_override',
                'pronunciation.profile.${input.selectedProfile.profileId}',
              ],
            ),
          );
          continue;
        }

        final lexicalRepresentations =
            input.mergedPronunciationResources[normalizedSurfaceText];
        if (lexicalRepresentations != null &&
            lexicalRepresentations.isNotEmpty) {
          artifacts.add(
            PronunciationArtifact(
              artifactId: 'pa_${ordinal++}',
              segmentId: segment.segmentId,
              startWord: wordSpan.wordIndexWithinSegment,
              endWord: wordSpan.wordIndexWithinSegment + 1,
              surfaceText: surfaceText,
              normalizedSurfaceText: normalizedSurfaceText,
              artifactClass: PronunciationArtifactClass.resolvedLexicalCase,
              source: PronunciationArtifactSource.appLexicon,
              confidence: 0.98,
              representations: lexicalRepresentations,
              diagnosticCodes: <String>[
                'pronunciation.resolved.lexicon',
                'pronunciation.profile.${input.selectedProfile.profileId}',
              ],
            ),
          );
          continue;
        }

        final moduleResolution = _applyRuleModules(
          input: input,
          segment: segment,
          wordIndexWithinSegment: wordSpan.wordIndexWithinSegment,
          surfaceText: surfaceText,
          normalizedSurfaceText: normalizedSurfaceText,
        );
        if (moduleResolution != null) {
          artifacts.add(
            PronunciationArtifact(
              artifactId: 'pa_${ordinal++}',
              segmentId: segment.segmentId,
              startWord: wordSpan.wordIndexWithinSegment,
              endWord: wordSpan.wordIndexWithinSegment + 1,
              surfaceText: surfaceText,
              normalizedSurfaceText: normalizedSurfaceText,
              artifactClass:
                  moduleResolution.kind ==
                      PronunciationRuleModuleDecisionKind.unresolvedDiagnostic
                  ? PronunciationArtifactClass.unresolvedCase
                  : PronunciationArtifactClass.resolvedLexicalCase,
              source:
                  moduleResolution.kind ==
                      PronunciationRuleModuleDecisionKind.unresolvedDiagnostic
                  ? PronunciationArtifactSource.fallbackUnresolved
                  : PronunciationArtifactSource.ruleBasedInference,
              confidence: moduleResolution.confidence,
              representations: moduleResolution.representations,
              diagnosticCodes: moduleResolution.diagnosticCodes,
            ),
          );
          continue;
        }

        final inferredResolution = _inferResolvedPronunciation(
          segment: segment,
          wordIndexWithinSegment: wordSpan.wordIndexWithinSegment,
          normalizedSurfaceText: normalizedSurfaceText,
        );
        if (inferredResolution != null) {
          artifacts.add(
            PronunciationArtifact(
              artifactId: 'pa_${ordinal++}',
              segmentId: segment.segmentId,
              startWord: wordSpan.wordIndexWithinSegment,
              endWord: wordSpan.wordIndexWithinSegment + 1,
              surfaceText: surfaceText,
              normalizedSurfaceText: normalizedSurfaceText,
              artifactClass: PronunciationArtifactClass.resolvedLexicalCase,
              source: PronunciationArtifactSource.ruleBasedInference,
              confidence: inferredResolution.confidence,
              representations: inferredResolution.representations,
              diagnosticCodes: inferredResolution.diagnosticCodes,
            ),
          );
          continue;
        }

        if (_isContextSensitiveToken(normalizedSurfaceText)) {
          artifacts.add(
            PronunciationArtifact(
              artifactId: 'pa_${ordinal++}',
              segmentId: segment.segmentId,
              startWord: wordSpan.wordIndexWithinSegment,
              endWord: wordSpan.wordIndexWithinSegment + 1,
              surfaceText: surfaceText,
              normalizedSurfaceText: normalizedSurfaceText,
              artifactClass: PronunciationArtifactClass.contextSensitiveCase,
              source: PronunciationArtifactSource.ruleBasedInference,
              confidence: 0.66,
              representations: const <PronunciationRepresentation>[],
              diagnosticCodes: const <String>[
                'pronunciation.context_sensitive.pending',
              ],
            ),
          );
          continue;
        }

        if (_isUnresolvedCandidate(normalizedSurfaceText)) {
          artifacts.add(
            PronunciationArtifact(
              artifactId: 'pa_${ordinal++}',
              segmentId: segment.segmentId,
              startWord: wordSpan.wordIndexWithinSegment,
              endWord: wordSpan.wordIndexWithinSegment + 1,
              surfaceText: surfaceText,
              normalizedSurfaceText: normalizedSurfaceText,
              artifactClass: PronunciationArtifactClass.unresolvedCase,
              source: PronunciationArtifactSource.fallbackUnresolved,
              confidence: 0.35,
              representations: const <PronunciationRepresentation>[],
              diagnosticCodes: const <String>[
                'pronunciation.unresolved.document_time',
              ],
            ),
          );
        }
      }
    }

    return BasePronunciationArtifactSet(
      documentId: input.speechDocument.documentId,
      artifactVersion: artifactVersion,
      normalizationVersion: input.normalizationVersion,
      pronunciationProfileId: input.selectedProfile.profileId,
      artifacts: artifacts,
    );
  }
}

class _InferredPronunciationResolution {
  const _InferredPronunciationResolution({
    required this.representations,
    required this.diagnosticCodes,
    required this.confidence,
  });

  final List<PronunciationRepresentation> representations;
  final List<String> diagnosticCodes;
  final double confidence;
}

String _normalizedToken(String token) {
  final normalized = normalizeEnglishSpeechText(token)
      .replaceAll(RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$'), '')
      .trim()
      .toLowerCase();
  return normalized;
}

_InferredPronunciationResolution? _inferResolvedPronunciation({
  required SpeechSegment segment,
  required int wordIndexWithinSegment,
  required String normalizedSurfaceText,
}) {
  final contextualResolution = _inferContextualResolvedPronunciation(
    segment: segment,
    wordIndexWithinSegment: wordIndexWithinSegment,
    normalizedSurfaceText: normalizedSurfaceText,
  );
  if (contextualResolution != null) {
    return contextualResolution;
  }

  final spokenNumber = _spokenNumberForToken(normalizedSurfaceText);
  if (spokenNumber != null) {
    return _InferredPronunciationResolution(
      representations: <PronunciationRepresentation>[
        PronunciationRepresentation(
          representationId: 'rule_number_$normalizedSurfaceText',
          representationType: 'normalized_spoken_text',
          representationValue: spokenNumber,
          priority: 85,
        ),
      ],
      diagnosticCodes: const <String>[
        'pronunciation.resolved.rule_based',
        'pronunciation.resolved.number_cardinal',
      ],
      confidence: 0.97,
    );
  }

  return null;
}

_InferredPronunciationResolution? _inferContextualResolvedPronunciation({
  required SpeechSegment segment,
  required int wordIndexWithinSegment,
  required String normalizedSurfaceText,
}) {
  if (normalizedSurfaceText != 'bow') {
    return null;
  }

  final nextToken = _normalizedSegmentToken(segment, wordIndexWithinSegment + 1);
  final nextNextToken = _normalizedSegmentToken(
    segment,
    wordIndexWithinSegment + 2,
  );

  final isWeaponBow =
      (nextToken == 'and' && _isArrowToken(nextNextToken)) ||
      (nextToken == 'with' && _isArrowToken(nextNextToken));
  if (!isWeaponBow) {
    return null;
  }

  return _InferredPronunciationResolution(
    representations: <PronunciationRepresentation>[
      PronunciationRepresentation(
        representationId: 'rule_bow_weapon_phoneme',
        representationType: 'phoneme_string',
        representationValue: 'bˈoʊ',
        priority: 95,
      ),
    ],
    diagnosticCodes: const <String>[
      'pronunciation.resolved.rule_based',
      'pronunciation.resolved.heteronym.weapon_bow',
    ],
    confidence: 0.98,
  );
}

PronunciationRuleModuleDecision? _applyRuleModules({
  required DocumentTimePronunciationPlannerInput input,
  required SpeechSegment segment,
  required int wordIndexWithinSegment,
  required String surfaceText,
  required String normalizedSurfaceText,
}) {
  final previousToken = wordIndexWithinSegment > 0
      ? segment.wordSpans[wordIndexWithinSegment - 1].text
      : null;
  final nextToken = wordIndexWithinSegment + 1 < segment.wordSpans.length
      ? segment.wordSpans[wordIndexWithinSegment + 1].text
      : null;

  for (final module in input.enabledDocumentTimeRuleModules) {
    if (!module.supportsDocumentTime) {
      continue;
    }
    final decision = module.apply(
      PronunciationRuleModuleContext(
        segmentId: segment.segmentId,
        segmentText: segment.normalizedText,
        tokenIndex: wordIndexWithinSegment,
        surfaceText: surfaceText,
        normalizedSurfaceText: normalizedSurfaceText,
        selectedProfile: input.selectedProfile,
        mergedResources: input.mergedPronunciationResources,
        previousToken: previousToken,
        nextToken: nextToken,
      ),
    );
    if (decision.kind != PronunciationRuleModuleDecisionKind.noDecision) {
      return decision;
    }
  }
  return null;
}

bool _isContextSensitiveToken(String normalizedToken) {
  return false;
}

bool _isUnresolvedCandidate(String normalizedToken) {
  if (normalizedToken.length < 5) {
    return false;
  }
  if (!RegExp(r"^[a-z]+(?:'[a-z]+)?$").hasMatch(normalizedToken)) {
    return false;
  }
  return normalizedToken.endsWith('ed');
}

String? _normalizedSegmentToken(SpeechSegment segment, int wordIndex) {
  if (wordIndex < 0 || wordIndex >= segment.wordSpans.length) {
    return null;
  }
  final normalized = _normalizedToken(segment.wordSpans[wordIndex].text);
  return normalized.isEmpty ? null : normalized;
}

bool _isArrowToken(String? token) => token == 'arrow' || token == 'arrows';

String? _spokenNumberForToken(String normalizedSurfaceText) {
  if (!RegExp(r'^\d{1,3}(,\d{3})*$|^\d+$').hasMatch(normalizedSurfaceText)) {
    return null;
  }
  final numeric = normalizedSurfaceText.replaceAll(',', '');
  final value = int.tryParse(numeric);
  if (value == null || value < 0) {
    return null;
  }
  if (value > 999999999999) {
    return null;
  }
  return _integerToEnglishWords(value);
}

String _integerToEnglishWords(int value) {
  const smallNumbers = <String>[
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  const tens = <String>[
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];

  if (value < 20) {
    return smallNumbers[value];
  }
  if (value < 100) {
    final tensValue = value ~/ 10;
    final onesValue = value % 10;
    if (onesValue == 0) {
      return tens[tensValue];
    }
    return '${tens[tensValue]} ${smallNumbers[onesValue]}';
  }
  if (value < 1000) {
    final hundredsValue = value ~/ 100;
    final remainder = value % 100;
    if (remainder == 0) {
      return '${smallNumbers[hundredsValue]} hundred';
    }
    return '${smallNumbers[hundredsValue]} hundred ${_integerToEnglishWords(remainder)}';
  }

  const scales = <(int, String)>[
    (1000000000, 'billion'),
    (1000000, 'million'),
    (1000, 'thousand'),
  ];

  for (final scale in scales) {
    final scaleValue = scale.$1;
    final scaleName = scale.$2;
    if (value >= scaleValue) {
      final major = value ~/ scaleValue;
      final remainder = value % scaleValue;
      final majorWords = _integerToEnglishWords(major);
      if (remainder == 0) {
        return '$majorWords $scaleName';
      }
      return '$majorWords $scaleName ${_integerToEnglishWords(remainder)}';
    }
  }

  return value.toString();
}
