import 'dart:math' as math;

import '../models/character_cast_registry.dart';
import '../models/dialogue_attribution.dart';
import '../models/speech_document.dart';

class CharacterCastRegistryService {
  const CharacterCastRegistryService();

  static const registryVersion = 'read-aloud-character-cast-registry-v2';

  CharacterCastRegistry build({
    required DialogueAttributionSet dialogueAttributions,
    required SpeechDocument speechDocument,
  }) {
    final entries = <CastEntry>[
      CastEntry(
        castId: 'cast_narrator',
        roleKind: CastEntryRoleKind.narrator,
        displayLabel: 'Narrator',
        confidence: 1.0,
        provenance: CastEntryProvenance.syntheticNarrator,
      ),
    ];

    final groupedOutcomes = <String, List<DialogueAttributionOutcome>>{};
    for (final outcome in dialogueAttributions.outcomes) {
      if (outcome.resolution !=
              DialogueAttributionResolution.attributedSpeaker ||
          outcome.speakerReference == null) {
        continue;
      }
      final key = outcome.speakerReference!.normalizedLabel;
      groupedOutcomes
          .putIfAbsent(key, () => <DialogueAttributionOutcome>[])
          .add(outcome);
    }

    final consolidated = _consolidateGroupedOutcomes(groupedOutcomes);
    for (final cluster in consolidated) {
      final aliases = cluster.aliases.toList(growable: false)..sort();
      final attributionIds = cluster.attributionIds.toList(growable: false)
        ..sort();
      final confidence = cluster.averageConfidence;
      final identityProfile = _extractIdentityProfileForCluster(
        speechDocument: speechDocument,
        aliases: aliases,
      );
      entries.add(
        CastEntry(
          castId: _castIdForNormalizedLabel(cluster.canonicalNormalizedLabel),
          roleKind: CastEntryRoleKind.character,
          displayLabel: cluster.displayLabel,
          confidence: confidence,
          provenance: castEntryProvenanceForAttribution(
            cluster.primaryOutcome.provenance,
          ),
          observedAliases: aliases,
          attributionIds: attributionIds,
          identityProfile: identityProfile,
        ),
      );
    }

    return CharacterCastRegistry(
      documentId: dialogueAttributions.documentId,
      registryVersion: registryVersion,
      entries: entries,
    );
  }

  String _castIdForNormalizedLabel(String normalizedLabel) {
    final slug = normalizedLabel
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'cast_character_${slug.isEmpty ? 'unknown' : slug}';
  }

  List<_OutcomeCluster> _consolidateGroupedOutcomes(
    Map<String, List<DialogueAttributionOutcome>> groupedOutcomes,
  ) {
    final sortedKeys = groupedOutcomes.keys.toList(growable: false)..sort();
    final clusters = <_OutcomeCluster>[];

    for (final key in sortedKeys) {
      final outcomes = groupedOutcomes[key]!;
      final existingCluster = clusters.firstWhere(
        (cluster) =>
            _shouldMergeNormalizedLabels(cluster.canonicalNormalizedLabel, key),
        orElse: () => _OutcomeCluster.empty(),
      );

      if (existingCluster.isEmpty) {
        clusters.add(_OutcomeCluster.fromOutcomes(outcomes));
        continue;
      }

      existingCluster.absorb(outcomes);
    }

    for (final cluster in clusters) {
      cluster.finalizeCanonicalLabel();
    }

    clusters.sort(
      (left, right) => left.canonicalNormalizedLabel.compareTo(
        right.canonicalNormalizedLabel,
      ),
    );
    return clusters;
  }

  bool _shouldMergeNormalizedLabels(String left, String right) {
    if (left == right) {
      return true;
    }

    final leftTokens = left.split(' ');
    final rightTokens = right.split(' ');
    if (leftTokens.length != rightTokens.length || leftTokens.length != 1) {
      return false;
    }

    final leftToken = leftTokens.single;
    final rightToken = rightTokens.single;
    if (leftToken.length < 6 ||
        rightToken.length < 6 ||
        leftToken[0] != rightToken[0]) {
      return false;
    }

    final distance = _levenshteinDistance(leftToken, rightToken);
    final allowedDistance = math.max(leftToken.length, rightToken.length) >= 8
        ? 2
        : 1;
    return distance <= allowedDistance;
  }

  int _levenshteinDistance(String left, String right) {
    if (left == right) {
      return 0;
    }
    if (left.isEmpty) {
      return right.length;
    }
    if (right.isEmpty) {
      return left.length;
    }

    final previous = List<int>.generate(right.length + 1, (index) => index);
    final current = List<int>.filled(right.length + 1, 0);

    for (var leftIndex = 0; leftIndex < left.length; leftIndex += 1) {
      current[0] = leftIndex + 1;
      for (var rightIndex = 0; rightIndex < right.length; rightIndex += 1) {
        final substitutionCost = left[leftIndex] == right[rightIndex] ? 0 : 1;
        current[rightIndex + 1] = math.min(
          math.min(current[rightIndex] + 1, previous[rightIndex + 1] + 1),
          previous[rightIndex] + substitutionCost,
        );
      }
      for (var index = 0; index < current.length; index += 1) {
        previous[index] = current[index];
      }
    }

    return previous.last;
  }

  CharacterIdentityProfile _extractIdentityProfileForCluster({
    required SpeechDocument speechDocument,
    required List<String> aliases,
  }) {
    final normalizedAliases = aliases
        .map((alias) => alias.trim().toLowerCase())
        .where((alias) => alias.isNotEmpty)
        .toSet();
    if (normalizedAliases.isEmpty) {
      return const CharacterIdentityProfile.unknown();
    }

    final identityCandidates = <_IdentityCandidate>[];
    final pronounCounts = <String, int>{};
    final pronounEvidenceSpans = <CharacterIdentityEvidenceSpan>[];

    for (final segment in speechDocument.segments) {
      final segmentText = segment.normalizedText;
      final lowerSegmentText = segmentText.toLowerCase();
      for (final alias in normalizedAliases) {
        final aliasPattern = RegExp(
          '\\b${RegExp.escape(alias)}\\b',
          caseSensitive: false,
        );
        final aliasMatches = aliasPattern
            .allMatches(segmentText)
            .toList(growable: false);
        if (aliasMatches.isEmpty) {
          continue;
        }
        identityCandidates.addAll(
          _extractExplicitIdentityCandidates(
            segment: segment,
            text: segmentText,
            alias: alias,
          ),
        );
        identityCandidates.addAll(
          _extractExplicitAppositionCandidates(
            segment: segment,
            text: segmentText,
            alias: alias,
          ),
        );
        identityCandidates.addAll(
          _extractDescriptorCandidates(
            segment: segment,
            text: segmentText,
            alias: alias,
          ),
        );
        _collectPronounProfileEvidence(
          aliasMatches: aliasMatches,
          segment: segment,
          segmentText: segmentText,
          lowerSegmentText: lowerSegmentText,
          pronounCounts: pronounCounts,
          pronounEvidenceSpans: pronounEvidenceSpans,
        );
      }
    }

    final pronounProfile = CharacterPronounProfile(counts: pronounCounts);
    final explicitResolution = _resolveIdentityCandidates(
      identityCandidates.where((candidate) => candidate.isExplicit).toList(),
      pronounProfile: pronounProfile,
    );
    if (explicitResolution != null) {
      return explicitResolution;
    }

    final descriptorResolution = _resolveIdentityCandidates(
      identityCandidates
          .where(
            (candidate) =>
                candidate.source == CharacterGenderEvidenceSource.descriptor,
          )
          .toList(),
      pronounProfile: pronounProfile,
    );
    if (descriptorResolution != null) {
      return descriptorResolution;
    }

    return _resolvePronounIdentity(
      pronounProfile: pronounProfile,
      pronounEvidenceSpans: pronounEvidenceSpans,
    );
  }

  List<_IdentityCandidate> _extractExplicitIdentityCandidates({
    required SpeechSegment segment,
    required String text,
    required String alias,
  }) {
    final candidates = <_IdentityCandidate>[];
    for (final entry in _explicitIdentityPhraseMap.entries) {
      final pattern = RegExp(
        '\\b${RegExp.escape(alias)}\\b\\s+'
        '(?:is|was|seems|seemed|identified\\s+as|identifies\\s+as)\\s+'
        '(?:a|an)?\\s*${entry.key}\\b',
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(text)) {
        candidates.add(
          _IdentityCandidate(
            label: entry.value,
            confidence: 0.96,
            source: CharacterGenderEvidenceSource.explicitIdentity,
            evidenceSpan: CharacterIdentityEvidenceSpan(
              segmentId: segment.segmentId,
              startUtf16: match.start,
              endUtf16: match.end,
              text: match.group(0)!,
            ),
          ),
        );
      }
    }
    return candidates;
  }

  List<_IdentityCandidate> _extractExplicitAppositionCandidates({
    required SpeechSegment segment,
    required String text,
    required String alias,
  }) {
    final candidates = <_IdentityCandidate>[];
    for (final entry in _explicitIdentityPhraseMap.entries) {
      final pattern = RegExp(
        '\\b${RegExp.escape(alias)}\\b,\\s+(?:a|an)\\s+${entry.key}\\b',
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(text)) {
        candidates.add(
          _IdentityCandidate(
            label: entry.value,
            confidence: 0.92,
            source: CharacterGenderEvidenceSource.explicitApposition,
            evidenceSpan: CharacterIdentityEvidenceSpan(
              segmentId: segment.segmentId,
              startUtf16: match.start,
              endUtf16: match.end,
              text: match.group(0)!,
            ),
          ),
        );
      }
    }
    return candidates;
  }

  List<_IdentityCandidate> _extractDescriptorCandidates({
    required SpeechSegment segment,
    required String text,
    required String alias,
  }) {
    final candidates = <_IdentityCandidate>[];
    for (final entry in _descriptorPhraseMap.entries) {
      final narrativePattern = RegExp(
        '\\b${RegExp.escape(alias)}\\b\\s+'
        '(?:is|was|became|remained)?\\s*(?:a|an|the)?\\s*${entry.key}\\b',
        caseSensitive: false,
      );
      for (final match in narrativePattern.allMatches(text)) {
        candidates.add(
          _IdentityCandidate(
            label: entry.value,
            confidence: 0.78,
            source: CharacterGenderEvidenceSource.descriptor,
            evidenceSpan: CharacterIdentityEvidenceSpan(
              segmentId: segment.segmentId,
              startUtf16: match.start,
              endUtf16: match.end,
              text: match.group(0)!,
            ),
          ),
        );
      }

      final appositionPattern = RegExp(
        '\\b${RegExp.escape(alias)}\\b,\\s+(?:the\\s+)?${entry.key}\\b',
        caseSensitive: false,
      );
      for (final match in appositionPattern.allMatches(text)) {
        candidates.add(
          _IdentityCandidate(
            label: entry.value,
            confidence: 0.8,
            source: CharacterGenderEvidenceSource.descriptor,
            evidenceSpan: CharacterIdentityEvidenceSpan(
              segmentId: segment.segmentId,
              startUtf16: match.start,
              endUtf16: match.end,
              text: match.group(0)!,
            ),
          ),
        );
      }
    }
    return candidates;
  }

  void _collectPronounProfileEvidence({
    required List<RegExpMatch> aliasMatches,
    required SpeechSegment segment,
    required String segmentText,
    required String lowerSegmentText,
    required Map<String, int> pronounCounts,
    required List<CharacterIdentityEvidenceSpan> pronounEvidenceSpans,
  }) {
    for (final aliasMatch in aliasMatches) {
      final windowStart = aliasMatch.start;
      final hardWindowEnd = math.min(
        aliasMatch.end + 96,
        lowerSegmentText.length,
      );
      var windowEnd = hardWindowEnd;
      for (var index = aliasMatch.end; index < hardWindowEnd; index += 1) {
        final codeUnit = segmentText.codeUnitAt(index);
        if (codeUnit == 10 ||
            codeUnit == 33 ||
            codeUnit == 46 ||
            codeUnit == 63) {
          windowEnd = index + 1;
          break;
        }
      }
      final trailingText = segmentText.substring(aliasMatch.end, windowEnd);
      final nextCapitalizedToken = RegExp(
        r"\b[A-Z][A-Za-z'’-]+\b",
      ).firstMatch(trailingText);
      if (nextCapitalizedToken != null) {
        windowEnd = aliasMatch.end + nextCapitalizedToken.start;
      }
      if (windowEnd <= windowStart) {
        continue;
      }
      final window = lowerSegmentText.substring(windowStart, windowEnd);
      for (final entry in _pronounPatternByToken.entries) {
        for (final match in entry.value.allMatches(window)) {
          pronounCounts[entry.key] = (pronounCounts[entry.key] ?? 0) + 1;
          final absoluteStart = windowStart + match.start;
          final absoluteEnd = windowStart + match.end;
          pronounEvidenceSpans.add(
            CharacterIdentityEvidenceSpan(
              segmentId: segment.segmentId,
              startUtf16: absoluteStart,
              endUtf16: absoluteEnd,
              text: segment.normalizedText.substring(
                absoluteStart,
                absoluteEnd,
              ),
            ),
          );
        }
      }
    }
  }

  CharacterIdentityProfile? _resolveIdentityCandidates(
    List<_IdentityCandidate> candidates, {
    required CharacterPronounProfile pronounProfile,
  }) {
    if (candidates.isEmpty) {
      return null;
    }

    final topSourcePriority = candidates
        .map((candidate) => _sourcePriority(candidate.source))
        .reduce(math.max);
    final topSourceCandidates = candidates
        .where(
          (candidate) => _sourcePriority(candidate.source) == topSourcePriority,
        )
        .toList(growable: false);
    final topSpecificity = topSourceCandidates
        .map((candidate) => _labelSpecificity(candidate.label))
        .reduce(math.max);
    final strongestCandidates = topSourceCandidates
        .where(
          (candidate) => _labelSpecificity(candidate.label) == topSpecificity,
        )
        .toList(growable: false);

    final normalizedLabels = strongestCandidates
        .map((candidate) => candidate.label)
        .toSet();
    final hasConflict =
        normalizedLabels.length > 1 &&
        !_labelsAreMutuallyCompatible(normalizedLabels);
    if (hasConflict) {
      return CharacterIdentityProfile(
        genderIdentityLabel: CharacterGenderIdentityLabel.unknown,
        genderConfidence: 0.0,
        genderSource: strongestCandidates.first.source,
        pronounProfile: pronounProfile,
        evidenceSpans: strongestCandidates
            .map((candidate) => candidate.evidenceSpan)
            .toList(growable: false),
        conflictFlag: true,
      );
    }

    final winner = strongestCandidates.first;
    return CharacterIdentityProfile(
      genderIdentityLabel: winner.label,
      genderConfidence: winner.confidence,
      genderSource: winner.source,
      pronounProfile: pronounProfile,
      evidenceSpans: strongestCandidates
          .map((candidate) => candidate.evidenceSpan)
          .toList(growable: false),
      conflictFlag: false,
    );
  }

  CharacterIdentityProfile _resolvePronounIdentity({
    required CharacterPronounProfile pronounProfile,
    required List<CharacterIdentityEvidenceSpan> pronounEvidenceSpans,
  }) {
    final heCount =
        pronounProfile.countFor('he') +
        pronounProfile.countFor('him') +
        pronounProfile.countFor('his');
    final sheCount =
        pronounProfile.countFor('she') +
        pronounProfile.countFor('her') +
        pronounProfile.countFor('hers');
    final hasOnlyNeutralPronouns =
        pronounProfile.countFor('they') +
                pronounProfile.countFor('them') +
                pronounProfile.countFor('theirs') >
            0 &&
        heCount == 0 &&
        sheCount == 0;

    if (heCount > 0 && sheCount == 0) {
      return CharacterIdentityProfile(
        genderIdentityLabel: CharacterGenderIdentityLabel.male,
        genderConfidence: math.min(0.85, 0.5 + (heCount * 0.1)),
        genderSource: CharacterGenderEvidenceSource.pronoun,
        pronounProfile: pronounProfile,
        evidenceSpans: pronounEvidenceSpans,
      );
    }
    if (sheCount > 0 && heCount == 0) {
      return CharacterIdentityProfile(
        genderIdentityLabel: CharacterGenderIdentityLabel.female,
        genderConfidence: math.min(0.85, 0.5 + (sheCount * 0.1)),
        genderSource: CharacterGenderEvidenceSource.pronoun,
        pronounProfile: pronounProfile,
        evidenceSpans: pronounEvidenceSpans,
      );
    }
    if (heCount >= 2 && heCount >= sheCount * 2) {
      return CharacterIdentityProfile(
        genderIdentityLabel: CharacterGenderIdentityLabel.male,
        genderConfidence: math.min(0.8, 0.45 + (heCount * 0.08)),
        genderSource: CharacterGenderEvidenceSource.pronoun,
        pronounProfile: pronounProfile,
        evidenceSpans: pronounEvidenceSpans,
      );
    }
    if (sheCount >= 2 && sheCount >= heCount * 2) {
      return CharacterIdentityProfile(
        genderIdentityLabel: CharacterGenderIdentityLabel.female,
        genderConfidence: math.min(0.8, 0.45 + (sheCount * 0.08)),
        genderSource: CharacterGenderEvidenceSource.pronoun,
        pronounProfile: pronounProfile,
        evidenceSpans: pronounEvidenceSpans,
      );
    }

    return CharacterIdentityProfile(
      genderIdentityLabel: CharacterGenderIdentityLabel.unknown,
      genderConfidence: 0.0,
      genderSource: CharacterGenderEvidenceSource.unknown,
      pronounProfile: pronounProfile,
      evidenceSpans: pronounEvidenceSpans,
      conflictFlag: heCount > 0 && sheCount > 0 && !hasOnlyNeutralPronouns,
    );
  }

  int _sourcePriority(CharacterGenderEvidenceSource source) {
    return switch (source) {
      CharacterGenderEvidenceSource.explicitIdentity => 4,
      CharacterGenderEvidenceSource.explicitApposition => 3,
      CharacterGenderEvidenceSource.descriptor => 2,
      CharacterGenderEvidenceSource.pronoun => 1,
      CharacterGenderEvidenceSource.unknown => 0,
    };
  }

  int _labelSpecificity(CharacterGenderIdentityLabel label) {
    return switch (label) {
      CharacterGenderIdentityLabel.transMale ||
      CharacterGenderIdentityLabel.transFemale ||
      CharacterGenderIdentityLabel.cisMale ||
      CharacterGenderIdentityLabel.cisFemale ||
      CharacterGenderIdentityLabel.genderqueer ||
      CharacterGenderIdentityLabel.nonbinary => 3,
      CharacterGenderIdentityLabel.transgender => 2,
      CharacterGenderIdentityLabel.male ||
      CharacterGenderIdentityLabel.female => 1,
      CharacterGenderIdentityLabel.unknown => 0,
    };
  }

  bool _labelsAreMutuallyCompatible(Set<CharacterGenderIdentityLabel> labels) {
    final baseLabels = labels.map(_baseLabelFor).toSet();
    return baseLabels.length <= 1;
  }

  CharacterGenderIdentityLabel _baseLabelFor(
    CharacterGenderIdentityLabel label,
  ) {
    return switch (label) {
      CharacterGenderIdentityLabel.cisMale ||
      CharacterGenderIdentityLabel.transMale =>
        CharacterGenderIdentityLabel.male,
      CharacterGenderIdentityLabel.cisFemale ||
      CharacterGenderIdentityLabel.transFemale =>
        CharacterGenderIdentityLabel.female,
      _ => label,
    };
  }

  static const Map<String, CharacterGenderIdentityLabel>
  _explicitIdentityPhraseMap = <String, CharacterGenderIdentityLabel>{
    'cisgender\\s+man': CharacterGenderIdentityLabel.cisMale,
    'cis\\s+man': CharacterGenderIdentityLabel.cisMale,
    'cis\\s+male': CharacterGenderIdentityLabel.cisMale,
    'cisgender\\s+woman': CharacterGenderIdentityLabel.cisFemale,
    'cis\\s+woman': CharacterGenderIdentityLabel.cisFemale,
    'cis\\s+female': CharacterGenderIdentityLabel.cisFemale,
    'transgender\\s+man': CharacterGenderIdentityLabel.transMale,
    'trans\\s+man': CharacterGenderIdentityLabel.transMale,
    'transgender\\s+woman': CharacterGenderIdentityLabel.transFemale,
    'trans\\s+woman': CharacterGenderIdentityLabel.transFemale,
    'genderqueer': CharacterGenderIdentityLabel.genderqueer,
    'nonbinary': CharacterGenderIdentityLabel.nonbinary,
    'non-binary': CharacterGenderIdentityLabel.nonbinary,
    'transgender': CharacterGenderIdentityLabel.transgender,
    'trans': CharacterGenderIdentityLabel.transgender,
    'man': CharacterGenderIdentityLabel.male,
    'male': CharacterGenderIdentityLabel.male,
    'woman': CharacterGenderIdentityLabel.female,
    'female': CharacterGenderIdentityLabel.female,
  };

  static const Map<String, CharacterGenderIdentityLabel> _descriptorPhraseMap =
      <String, CharacterGenderIdentityLabel>{
        'man': CharacterGenderIdentityLabel.male,
        'boy': CharacterGenderIdentityLabel.male,
        'brother': CharacterGenderIdentityLabel.male,
        'father': CharacterGenderIdentityLabel.male,
        'woman': CharacterGenderIdentityLabel.female,
        'girl': CharacterGenderIdentityLabel.female,
        'sister': CharacterGenderIdentityLabel.female,
        'mother': CharacterGenderIdentityLabel.female,
      };

  static final Map<String, RegExp> _pronounPatternByToken = <String, RegExp>{
    'he': RegExp(r'\bhe\b'),
    'him': RegExp(r'\bhim\b'),
    'his': RegExp(r'\bhis\b'),
    'she': RegExp(r'\bshe\b'),
    'her': RegExp(r'\bher\b'),
    'hers': RegExp(r'\bhers\b'),
    'they': RegExp(r'\bthey\b'),
    'them': RegExp(r'\bthem\b'),
    'theirs': RegExp(r'\btheirs\b'),
    'xe': RegExp(r'\bxe\b'),
    'xem': RegExp(r'\bxem\b'),
    'xyr': RegExp(r'\bxyr\b'),
    'ze': RegExp(r'\bze\b'),
    'zir': RegExp(r'\bzir\b'),
    'hir': RegExp(r'\bhir\b'),
    'fae': RegExp(r'\bfae\b'),
    'faer': RegExp(r'\bfaer\b'),
    'ey': RegExp(r'\bey\b'),
    'em': RegExp(r'\bem\b'),
    'eir': RegExp(r'\beir\b'),
  };
}

class _OutcomeCluster {
  _OutcomeCluster({
    required this.outcomes,
    required this.aliasCounts,
    required this.canonicalNormalizedLabel,
    required this.displayLabel,
  });

  factory _OutcomeCluster.fromOutcomes(
    List<DialogueAttributionOutcome> outcomes,
  ) {
    final aliasCounts = <String, int>{};
    for (final outcome in outcomes) {
      final label = outcome.speakerReference!.displayLabel.trim();
      aliasCounts[label] = (aliasCounts[label] ?? 0) + 1;
    }
    final displayLabel = _chooseDisplayLabel(
      outcomes: outcomes,
      aliasCounts: aliasCounts,
    );
    return _OutcomeCluster(
      outcomes: List<DialogueAttributionOutcome>.from(outcomes),
      aliasCounts: aliasCounts,
      canonicalNormalizedLabel: _normalizeDisplayLabel(displayLabel),
      displayLabel: displayLabel,
    );
  }

  factory _OutcomeCluster.empty() => _OutcomeCluster(
    outcomes: <DialogueAttributionOutcome>[],
    aliasCounts: <String, int>{},
    canonicalNormalizedLabel: '',
    displayLabel: '',
  );

  final List<DialogueAttributionOutcome> outcomes;
  final Map<String, int> aliasCounts;
  String canonicalNormalizedLabel;
  String displayLabel;

  bool get isEmpty => outcomes.isEmpty;

  DialogueAttributionOutcome get primaryOutcome => outcomes.first;

  Set<String> get aliases => aliasCounts.keys.toSet();

  List<String> get attributionIds =>
      outcomes.map((outcome) => outcome.attributionId).toList(growable: false);

  double get averageConfidence =>
      outcomes.fold<double>(0.0, (sum, outcome) => sum + outcome.confidence) /
      outcomes.length;

  void absorb(List<DialogueAttributionOutcome> additionalOutcomes) {
    outcomes.addAll(additionalOutcomes);
    for (final outcome in additionalOutcomes) {
      final label = outcome.speakerReference!.displayLabel.trim();
      aliasCounts[label] = (aliasCounts[label] ?? 0) + 1;
    }
  }

  void finalizeCanonicalLabel() {
    displayLabel = _chooseDisplayLabel(
      outcomes: outcomes,
      aliasCounts: aliasCounts,
    );
    canonicalNormalizedLabel = _normalizeDisplayLabel(displayLabel);
  }

  static String _chooseDisplayLabel({
    required List<DialogueAttributionOutcome> outcomes,
    required Map<String, int> aliasCounts,
  }) {
    final scoreByAlias = <String, double>{};
    for (final outcome in outcomes) {
      final label = outcome.speakerReference!.displayLabel.trim();
      scoreByAlias[label] =
          (scoreByAlias[label] ?? 0.0) +
          outcome.confidence +
          (label.length / 100);
    }

    final aliases = scoreByAlias.keys.toList(growable: false)
      ..sort((left, right) {
        final scoreComparison = scoreByAlias[right]!.compareTo(
          scoreByAlias[left]!,
        );
        if (scoreComparison != 0) {
          return scoreComparison;
        }
        final countComparison = (aliasCounts[right] ?? 0).compareTo(
          aliasCounts[left] ?? 0,
        );
        if (countComparison != 0) {
          return countComparison;
        }
        final lengthComparison = right.length.compareTo(left.length);
        if (lengthComparison != 0) {
          return lengthComparison;
        }
        return left.compareTo(right);
      });
    return aliases.first;
  }

  static String _normalizeDisplayLabel(String label) {
    return label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _IdentityCandidate {
  const _IdentityCandidate({
    required this.label,
    required this.confidence,
    required this.source,
    required this.evidenceSpan,
  });

  final CharacterGenderIdentityLabel label;
  final double confidence;
  final CharacterGenderEvidenceSource source;
  final CharacterIdentityEvidenceSpan evidenceSpan;

  bool get isExplicit =>
      source == CharacterGenderEvidenceSource.explicitIdentity ||
      source == CharacterGenderEvidenceSource.explicitApposition;
}
