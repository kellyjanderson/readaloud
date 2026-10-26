import 'dart:math' as math;

import '../models/character_cast_registry.dart';
import '../models/dialogue_attribution.dart';
import '../models/speech_document.dart';

class CharacterCastRegistryService {
  const CharacterCastRegistryService();

  static const registryVersion = 'read-aloud-character-cast-registry-v3';

  CharacterCastRegistry build({
    required DialogueAttributionSet dialogueAttributions,
    required SpeechDocument speechDocument,
    CharacterCastRegistry? previousRegistry,
    List<SpeechSegment> contextSegments = const [],
    List<SpeechSegment> followingContextSegments = const [],
  }) {
    if (contextSegments.length > 12 || followingContextSegments.length > 12) {
      throw ArgumentError(
        "Cast evidence halos must contain at most 12 segments each.",
      );
    }
    final allSegments = <String, SpeechSegment>{
      for (final segment in [
        ...contextSegments,
        ...speechDocument.segments,
        ...followingContextSegments,
      ])
        segment.segmentId: segment,
    }.values.toList();
    final identityDocument = SpeechDocument(
      documentId: speechDocument.documentId,
      sourceType: speechDocument.sourceType,
      languageTag: speechDocument.languageTag,
      normalizationVersion: speechDocument.normalizationVersion,
      segments: allSegments,
      segmentIndexById: {
        for (var index = 0; index < allSegments.length; index++)
          allSegments[index].segmentId: index,
      },
      totalWordCount: allSegments.fold<int>(
        0,
        (count, segment) => count + segment.wordCount,
      ),
    );
    final entries = <CastEntry>[
      CastEntry(
        castId: 'cast_narrator',
        roleKind: CastEntryRoleKind.narrator,
        displayLabel: 'Narrator',
        confidence: 1.0,
        provenance: CastEntryProvenance.syntheticNarrator,
      ),
    ];

    final redirects = <String, String>{...?previousRegistry?.castIdRedirects};
    final previous =
        previousRegistry?.characterEntries.toList() ?? <CastEntry>[];
    final declaredAliases = <String, Set<String>>{};
    for (final segment in identityDocument.segments) {
      final narrative = segment.normalizedText.replaceAllMapped(
        RegExp(r'"[^"\n]*"|“[^”\n]*”'),
        (match) => ' ' * match.group(0)!.length,
      );
      for (final match in RegExp(
        r"\b([A-Z][A-Za-z'’-]+),\s+(?:also\s+)?known\s+as\s+([A-Z][A-Za-z'’-]+)\b",
      ).allMatches(narrative)) {
        final group = <String>{match.group(1)!, match.group(2)!};
        for (final alias in group) {
          declaredAliases[alias.toLowerCase()] = group;
        }
      }
    }
    final groupedOutcomes = <String, List<DialogueAttributionOutcome>>{};
    for (final outcome in dialogueAttributions.outcomes) {
      if (outcome.resolution !=
              DialogueAttributionResolution.attributedSpeaker ||
          outcome.speakerReference == null) {
        continue;
      }
      final normalized = outcome.speakerReference!.normalizedLabel;
      final key =
          declaredAliases[normalized]?.first.toLowerCase() ?? normalized;
      groupedOutcomes
          .putIfAbsent(key, () => <DialogueAttributionOutcome>[])
          .add(outcome);
    }

    final consolidated = _consolidateGroupedOutcomes(groupedOutcomes);
    for (final cluster in consolidated) {
      final aliases = <String>{
        ...cluster.aliases,
        for (final alias in cluster.aliases)
          ...?declaredAliases[alias.toLowerCase()],
      }.toList()..sort();
      final attributionIds = cluster.attributionIds.toList(growable: false)
        ..sort();
      final confidence = cluster.averageConfidence;
      final priorMatches = previous
          .where(
            (entry) => entry.observedAliases.any(
              (alias) => aliases.any(
                (current) => _shouldMergeNormalizedLabels(
                  alias.toLowerCase(),
                  current.toLowerCase(),
                ),
              ),
            ),
          )
          .toList();
      final prior = priorMatches.isEmpty ? null : priorMatches.first;
      for (final retired in priorMatches.skip(1)) {
        redirects[retired.castId] = prior!.castId;
      }
      final identityProfile = inferIdentity(
        speechDocument: priorMatches.isEmpty
            ? identityDocument
            : speechDocument,
        aliases: aliases,
        previousProfile: _mergeProfiles(
          priorMatches
              .map((entry) => entry.identityProfile)
              .whereType<CharacterIdentityProfile>()
              .toList(),
        ),
      );
      entries.add(
        CastEntry(
          castId:
              prior?.castId ??
              _castIdForNormalizedLabel(
                cluster.primaryOutcome.speakerReference!.normalizedLabel,
              ),
          roleKind: CastEntryRoleKind.character,
          displayLabel: cluster.displayLabel,
          confidence: confidence,
          provenance: castEntryProvenanceForAttribution(
            cluster.primaryOutcome.provenance,
          ),
          observedAliases: <String>{
            ...priorMatches.expand((entry) => entry.observedAliases),
            ...aliases,
          }.toList(),
          attributionIds: <String>{
            ...priorMatches
                .expand((entry) => entry.attributionIds)
                .toList()
                .reversed
                .take(32)
                .toList()
                .reversed,
            ...attributionIds,
          }.toList(),
          identityProfile: identityProfile,
        ),
      );
    }

    final presentIds = entries.map((entry) => entry.castId).toSet();
    for (final entry in previous) {
      if (!presentIds.contains(entry.castId) &&
          !redirects.containsKey(entry.castId)) {
        entries.add(
          CastEntry(
            castId: entry.castId,
            roleKind: entry.roleKind,
            displayLabel: entry.displayLabel,
            confidence: entry.confidence,
            provenance: entry.provenance,
            observedAliases: entry.observedAliases,
            attributionIds: entry.attributionIds,
            identityProfile: inferIdentity(
              speechDocument: speechDocument,
              aliases: entry.observedAliases,
              previousProfile: entry.identityProfile,
            ),
          ),
        );
      }
    }
    // Retain encounter order even when a later fragment mentions only a later
    // character. It determines the surviving ID if evidence merges identities.
    final remaining = {for (final entry in entries) entry.castId: entry};
    final ordered = <CastEntry>[remaining.remove('cast_narrator')!];
    for (final entry in previous) {
      final retained = remaining.remove(entry.castId);
      if (retained != null) ordered.add(retained);
    }
    ordered.addAll(remaining.values);
    for (final key in redirects.keys.toList()) {
      final seen = <String>{key};
      var target = redirects[key]!;
      while (redirects.containsKey(target) && seen.add(target)) {
        target = redirects[target]!;
      }
      redirects[key] = target;
    }
    return CharacterCastRegistry(
      documentId: dialogueAttributions.documentId,
      registryVersion: registryVersion,
      castIdRedirects: redirects,
      entries: ordered,
    );
  }

  String _castIdForNormalizedLabel(String normalizedLabel) {
    final slug = normalizedLabel
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'cast_character_${slug.isEmpty ? 'unknown' : slug}';
  }

  CharacterIdentityProfile? _mergeProfiles(
    List<CharacterIdentityProfile> profiles,
  ) {
    if (profiles.isEmpty) return null;
    if (profiles.length == 1) return profiles.single;
    final counts = <String, int>{};
    for (final profile in profiles) {
      for (final entry in profile.pronounProfile.counts.entries) {
        counts[entry.key] = (counts[entry.key] ?? 0) + entry.value;
      }
    }
    return CharacterIdentityProfile(
      genderIdentityLabel: CharacterGenderIdentityLabel.unknown,
      genderConfidence: 0,
      genderSource: counts.isEmpty
          ? CharacterGenderEvidenceSource.unknown
          : CharacterGenderEvidenceSource.pronoun,
      pronounProfile: CharacterPronounProfile(counts: counts),
      evidenceSpans: profiles
          .expand((profile) => profile.evidenceSpans)
          .toList(),
      conflictFlag: profiles.any((profile) => profile.conflictFlag),
      countedSegmentIds: profiles
          .expand((profile) => profile.countedSegmentIds)
          .toList(),
    );
  }

  List<_OutcomeCluster> _consolidateGroupedOutcomes(
    Map<String, List<DialogueAttributionOutcome>> groupedOutcomes,
  ) {
    final sortedKeys = groupedOutcomes.keys.toList(growable: false);
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

    return clusters;
  }

  bool _shouldMergeNormalizedLabels(String left, String right) => left == right;

  /// Analyzes only the supplied bounded fragment; callers retain the returned
  /// registry rather than retaining or reanalyzing a growing text prefix.
  CharacterIdentityProfile inferIdentity({
    required SpeechDocument speechDocument,
    required List<String> aliases,
    CharacterIdentityProfile? previousProfile,
  }) {
    final normalizedAliases = aliases
        .map((alias) => alias.trim().toLowerCase())
        .where((alias) => alias.isNotEmpty)
        .toSet();
    if (normalizedAliases.isEmpty) {
      return const CharacterIdentityProfile.unknown();
    }

    final identityCandidates = <_IdentityCandidate>[
      for (final span
          in previousProfile?.evidenceSpans ??
              <CharacterIdentityEvidenceSpan>[])
        if (span.source != CharacterGenderEvidenceSource.pronoun &&
            span.genderIdentityLabel != null)
          _IdentityCandidate(
            label: span.genderIdentityLabel!,
            confidence: 0.78,
            source: span.source,
            evidenceSpan: span,
          ),
    ];
    final pronounCounts = <String, int>{
      ...?previousProfile?.pronounProfile.counts,
    };
    final pronounEvidenceSpans = <CharacterIdentityEvidenceSpan>[];
    final countedSegments =
        previousProfile?.countedSegmentIds.toSet() ?? <String>{};
    final seenPronounEvidence = <String>{
      for (final span
          in previousProfile?.evidenceSpans ??
              <CharacterIdentityEvidenceSpan>[])
        if (span.source == CharacterGenderEvidenceSource.pronoun ||
            RegExp(
              r'^(he|she|they|his|her|their|himself|herself|themself|themselves)$',
              caseSensitive: false,
            ).hasMatch(span.text))
          '${span.segmentId}:${span.startUtf16}:${span.endUtf16}',
    };

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
          seenPronounEvidence: seenPronounEvidence,
          countedSegments: countedSegments,
        );
      }
    }

    for (var index = 1; index < speechDocument.segments.length; index++) {
      final segment = speechDocument.segments[index];
      if (countedSegments.contains(segment.segmentId)) continue;
      final previous = speechDocument.segments[index - 1];
      if (segment.paragraphIndex != previous.paragraphIndex ||
          segment.blockId != previous.blockId) {
        continue;
      }
      final match = RegExp(
        r'^\s*(He|She|They)\b',
      ).firstMatch(segment.normalizedText);
      if (match == null) continue;
      final names = RegExp(r"\b[A-Z][A-Za-z'’-]+\b")
          .allMatches(previous.normalizedText)
          .map((match) => match.group(0)!.toLowerCase())
          .where(
            (name) => !<String>{
              'the',
              'a',
              'an',
              'he',
              'she',
              'they',
              'i',
              'we',
              'near',
              'before',
              'after',
              'shortly',
              'later',
              'then',
              'outside',
              'inside',
              'by',
              'at',
              'for',
              'in',
              'on',
            }.contains(name),
          )
          .toSet();
      if (names.length != 1 || !normalizedAliases.contains(names.single)) {
        continue;
      }
      final token = match.group(1)!;
      final start = match.end - token.length;
      if (!seenPronounEvidence.add(
        '${segment.segmentId}:$start:${match.end}',
      )) {
        continue;
      }
      pronounCounts[token.toLowerCase()] =
          (pronounCounts[token.toLowerCase()] ?? 0) + 1;
      pronounEvidenceSpans.add(
        CharacterIdentityEvidenceSpan(
          segmentId: segment.segmentId,
          startUtf16: start,
          endUtf16: match.end,
          text: token,
          source: CharacterGenderEvidenceSource.pronoun,
        ),
      );
    }
    final pronounProfile = CharacterPronounProfile(counts: pronounCounts);
    CharacterIdentityProfile finish(CharacterIdentityProfile profile) {
      final newlyCounted = pronounEvidenceSpans
          .map((span) => span.segmentId)
          .toSet();
      return CharacterIdentityProfile(
        genderIdentityLabel: profile.genderIdentityLabel,
        genderConfidence: profile.genderConfidence,
        genderSource: profile.genderSource,
        pronounProfile: profile.pronounProfile,
        evidenceSpans: profile.evidenceSpans,
        conflictFlag: profile.conflictFlag,
        countedSegmentIds: [
          ...?previousProfile?.countedSegmentIds,
          for (final segment in speechDocument.segments)
            if (newlyCounted.contains(segment.segmentId)) segment.segmentId,
        ],
      );
    }

    final pronoun = _resolvePronounIdentity(
      pronounProfile: pronounProfile,
      pronounEvidenceSpans: <CharacterIdentityEvidenceSpan>[
        ...?previousProfile?.evidenceSpans.where(
          (span) =>
              span.source == CharacterGenderEvidenceSource.pronoun ||
              (span.source == CharacterGenderEvidenceSource.unknown &&
                  RegExp(
                    r'^(he|she|they|his|her|their|himself|herself|themself|themselves)$',
                    caseSensitive: false,
                  ).hasMatch(span.text)),
        ),
        ...pronounEvidenceSpans,
      ],
    );
    final contextual =
        _resolveIdentityCandidates(
          identityCandidates,
          pronounProfile: pronounProfile,
        ) ??
        (previousProfile?.genderSource !=
                    CharacterGenderEvidenceSource.pronoun &&
                previousProfile?.genderSource !=
                    CharacterGenderEvidenceSource.unknown
            ? previousProfile
            : null);
    if (pronoun.genderSource == CharacterGenderEvidenceSource.pronoun ||
        pronoun.conflictFlag) {
      final conflict =
          pronoun.conflictFlag ||
          (contextual?.conflictFlag ?? false) ||
          (contextual != null &&
              contextual.preferredVoiceGender != null &&
              contextual.preferredVoiceGender != pronoun.preferredVoiceGender);
      return finish(
        CharacterIdentityProfile(
          genderIdentityLabel: pronoun.genderIdentityLabel,
          genderConfidence: pronoun.genderConfidence,
          genderSource: CharacterGenderEvidenceSource.pronoun,
          pronounProfile: pronounProfile,
          evidenceSpans: <CharacterIdentityEvidenceSpan>[
            ...pronoun.evidenceSpans,
            ...?contextual?.evidenceSpans,
          ],
          conflictFlag: conflict || (previousProfile?.conflictFlag ?? false),
        ),
      );
    }
    return finish(contextual ?? pronoun);
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
              source: CharacterGenderEvidenceSource.explicitIdentity,
              genderIdentityLabel: entry.value,
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
              source: CharacterGenderEvidenceSource.explicitApposition,
              genderIdentityLabel: entry.value,
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
              source: CharacterGenderEvidenceSource.descriptor,
              genderIdentityLabel: entry.value,
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
              source: CharacterGenderEvidenceSource.descriptor,
              genderIdentityLabel: entry.value,
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
    required Set<String> seenPronounEvidence,
    required Set<String> countedSegments,
  }) {
    if (countedSegments.contains(segment.segmentId)) return;
    for (final aliasMatch in aliasMatches) {
      // A competing name or conjunction makes within-clause coreference weak.
      final tail = segmentText.substring(aliasMatch.end);
      final competing = RegExp(
        r"\b[A-Z][A-Za-z'’-]+\b|\b(?:and|but)\b",
      ).firstMatch(tail);
      var end = competing == null
          ? segmentText.length
          : aliasMatch.end + competing.start;
      final sentenceEnd = RegExp(r'[.!?]').firstMatch(tail);
      if (sentenceEnd != null) {
        end = math.min(end, aliasMatch.end + sentenceEnd.end);
      }
      final local = segmentText.substring(aliasMatch.end, end);
      final possessive = RegExp(
        r'\b(his|her|their)\s+(?:[a-z]+\s+)?(?:coat|voice|chest|heel|sleeves|arm|arms|hand|hands|head|sleeve|wrist|eyes|pocket|face|shoulder|shoulders|hat|bag|boots|gloves)\b|\b(himself|herself|themself|themselves)\b',
        caseSensitive: false,
      );
      void add(String token, int start, int finish) {
        if (!seenPronounEvidence.add('${segment.segmentId}:$start:$finish')) {
          return;
        }
        final normalized = switch (token.toLowerCase()) {
          'himself' => 'he',
          'herself' => 'she',
          'themself' || 'themselves' => 'they',
          'their' => 'theirs',
          _ => token.toLowerCase(),
        };
        pronounCounts[normalized] = (pronounCounts[normalized] ?? 0) + 1;
        pronounEvidenceSpans.add(
          CharacterIdentityEvidenceSpan(
            segmentId: segment.segmentId,
            startUtf16: start,
            endUtf16: finish,
            text: segmentText.substring(start, finish),
            source: CharacterGenderEvidenceSource.pronoun,
          ),
        );
      }

      for (final match in possessive.allMatches(local)) {
        final token = match.group(1) ?? match.group(2)!;
        final offset = match.group(0)!.indexOf(token);
        add(
          token,
          aliasMatch.end + match.start + offset,
          aliasMatch.end + match.start + offset + token.length,
        );
      }
      // Subject pronouns in the immediately following segment are admitted only
      // by inferIdentity's explicit unique-subject pass below, not nearest name.
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
}
