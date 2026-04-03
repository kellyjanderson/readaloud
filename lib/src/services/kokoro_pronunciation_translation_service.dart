import 'dart:convert';

import '../models/engine_capability.dart';
import '../models/tts_artifact.dart';
import 'english_pronunciation_dictionary_service.dart';
import 'english_speech_preprocessor.dart';
import 'explicit_phoneme_override.dart';
import 'english_suffix_allomorph_module.dart';

enum KokoroPronunciationTranslationOutcome { direct, approximated, deferred }

enum KokoroEnginePayloadUnitKind {
  plainText,
  phonemeString,
  englishSClassAllomorph,
  explicitSuffixPhoneme,
}

class KokoroEnginePayloadUnit {
  const KokoroEnginePayloadUnit({
    required this.kind,
    required this.value,
    this.artifactIds = const <String>[],
  });

  final KokoroEnginePayloadUnitKind kind;
  final String value;
  final List<String> artifactIds;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'kind': kind.name,
      'value': value,
      'artifactIds': artifactIds,
    };
  }
}

class KokoroTranslatedPronunciationArtifact {
  const KokoroTranslatedPronunciationArtifact({
    required this.artifactId,
    required this.segmentId,
    required this.startWord,
    required this.endWord,
    required this.resolutionClass,
    required this.translationIntent,
    required this.translationOutcome,
    this.representationType,
    this.representationValue,
    this.diagnosticCodes = const <String>[],
  });

  final String artifactId;
  final String segmentId;
  final int startWord;
  final int endWord;
  final String resolutionClass;
  final String translationIntent;
  final KokoroPronunciationTranslationOutcome translationOutcome;
  final String? representationType;
  final String? representationValue;
  final List<String> diagnosticCodes;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'artifactId': artifactId,
      'segmentId': segmentId,
      'startWord': startWord,
      'endWord': endWord,
      'resolutionClass': resolutionClass,
      'translationIntent': translationIntent,
      'translationOutcome': translationOutcome.name,
      'representationType': representationType,
      'representationValue': representationValue,
      'diagnosticCodes': diagnosticCodes,
    };
  }

  factory KokoroTranslatedPronunciationArtifact.fromMap(
    Map<String, Object?> map,
  ) {
    return KokoroTranslatedPronunciationArtifact(
      artifactId: map['artifactId']! as String,
      segmentId: map['segmentId']! as String,
      startWord: (map['startWord']! as num).toInt(),
      endWord: (map['endWord']! as num).toInt(),
      resolutionClass: map['resolutionClass']! as String,
      translationIntent: map['translationIntent']! as String,
      translationOutcome: KokoroPronunciationTranslationOutcome.values.byName(
        map['translationOutcome']! as String,
      ),
      representationType: map['representationType'] as String?,
      representationValue: map['representationValue'] as String?,
      diagnosticCodes: List<String>.from(
        map['diagnosticCodes'] as List<Object?>? ?? const <Object?>[],
      ),
    );
  }
}

class KokoroTranslatedChunk {
  const KokoroTranslatedChunk({
    required this.chunkId,
    required this.capabilityProfileId,
    required this.speakText,
    required this.payloadUnits,
    required this.pronunciationArtifacts,
    required this.missingFallbackWordCount,
  });

  final String chunkId;
  final String capabilityProfileId;
  final String speakText;
  final List<KokoroEnginePayloadUnit> payloadUnits;
  final List<KokoroTranslatedPronunciationArtifact> pronunciationArtifacts;
  final int missingFallbackWordCount;
}

class KokoroPronunciationTranslationService {
  const KokoroPronunciationTranslationService({
    EngineCapabilityRegistry capabilityRegistry =
        const EngineCapabilityRegistry(),
  }) : _capabilityRegistry = capabilityRegistry;

  final EngineCapabilityRegistry _capabilityRegistry;

  KokoroTranslatedChunk translate({
    required String chunkId,
    required List<TtsArtifactSegment> segments,
    EngineCapabilityProfile? capabilityProfile,
  }) {
    final activeCapability =
        capabilityProfile ?? _capabilityRegistry.lookup(engineId: 'kokoro');
    if (segments.isEmpty) {
      return KokoroTranslatedChunk(
        chunkId: chunkId,
        capabilityProfileId: activeCapability.capabilityProfileId,
        speakText: '',
        payloadUnits: const <KokoroEnginePayloadUnit>[],
        pronunciationArtifacts: <KokoroTranslatedPronunciationArtifact>[],
        missingFallbackWordCount: 0,
      );
    }

    final translatedSegments = <String>[];
    final payloadUnits = <KokoroEnginePayloadUnit>[];
    final translatedArtifacts = <KokoroTranslatedPronunciationArtifact>[];
    var missingFallbackWordCount = 0;

    for (var index = 0; index < segments.length; index += 1) {
      final segment = segments[index];
      final translation = _translateSegment(
        segment,
        capabilityProfile: activeCapability,
      );
      if (index > 0 && translation.payloadUnits.isNotEmpty) {
        payloadUnits.add(
          const KokoroEnginePayloadUnit(
            kind: KokoroEnginePayloadUnitKind.plainText,
            value: ' ',
          ),
        );
      }
      translatedSegments.add(translation.speakText);
      payloadUnits.addAll(translation.payloadUnits);
      translatedArtifacts.addAll(translation.pronunciationArtifacts);
      missingFallbackWordCount += translation.missingFallbackWordCount;
    }

    return KokoroTranslatedChunk(
      chunkId: chunkId,
      capabilityProfileId: activeCapability.capabilityProfileId,
      speakText: translatedSegments.join(' ').trim(),
      payloadUnits: payloadUnits,
      pronunciationArtifacts: translatedArtifacts,
      missingFallbackWordCount: missingFallbackWordCount,
    );
  }
}

class _TranslatedSegment {
  const _TranslatedSegment({
    required this.speakText,
    required this.payloadUnits,
    required this.pronunciationArtifacts,
    required this.missingFallbackWordCount,
  });

  final String speakText;
  final List<KokoroEnginePayloadUnit> payloadUnits;
  final List<KokoroTranslatedPronunciationArtifact> pronunciationArtifacts;
  final int missingFallbackWordCount;
}

_TranslatedSegment _translateSegment(
  TtsArtifactSegment segment, {
  required EngineCapabilityProfile capabilityProfile,
}) {
  final tokenMatches = RegExp(
    r'\S+\s*',
  ).allMatches(segment.speakText).toList(growable: false);
  final traceUnits = tokenMatches
      .map((match) => segment.speakText.substring(match.start, match.end))
      .toList(growable: true);
  final payloadUnits = traceUnits
      .map(
        (unit) => KokoroEnginePayloadUnit(
          kind: KokoroEnginePayloadUnitKind.plainText,
          value: unit,
        ),
      )
      .toList(growable: true);
  final coveredWordIndexes = <int>{};
  final translatedArtifacts = <KokoroTranslatedPronunciationArtifact>[];

  final artifacts = segment.pronunciationArtifacts.toList(growable: false)
    ..sort((left, right) => right.startWord.compareTo(left.startWord));

  for (final artifact in artifacts) {
    for (var index = artifact.startWord; index < artifact.endWord; index += 1) {
      coveredWordIndexes.add(index);
    }

    final selectedRepresentation = artifact.selectedRepresentation;
    KokoroPronunciationTranslationOutcome translationOutcome;
    if (_isEnglishSClassAllomorphArtifact(artifact) &&
        selectedRepresentation?.representationType != 'phoneme_string' &&
        selectedRepresentation?.representationType != 'explicit_suffix_phoneme') {
        translationOutcome = KokoroPronunciationTranslationOutcome.direct;
      final clampedEnd = artifact.endWord > payloadUnits.length
          ? payloadUnits.length
          : artifact.endWord;
      payloadUnits.replaceRange(
        artifact.startWord,
        clampedEnd,
        _buildEnglishSClassPayloadUnits(
          units: traceUnits,
          startWord: artifact.startWord,
          endWord: artifact.endWord,
          artifactId: artifact.artifactId,
        ),
      );
    } else if (selectedRepresentation == null) {
      translationOutcome = KokoroPronunciationTranslationOutcome.deferred;
      } else if (capabilityProfile.supportsDirectRepresentation(
        selectedRepresentation.representationType,
      )) {
        translationOutcome = KokoroPronunciationTranslationOutcome.direct;
        if (selectedRepresentation.representationType == 'phoneme_string') {
        final clampedEnd = artifact.endWord > payloadUnits.length
            ? payloadUnits.length
            : artifact.endWord;
        payloadUnits.replaceRange(
          artifact.startWord,
          clampedEnd,
          _buildDirectPhonemePayloadUnits(
            units: traceUnits,
            startWord: artifact.startWord,
            endWord: artifact.endWord,
            phonemeString: selectedRepresentation.representationValue,
            artifactId: artifact.artifactId,
            ),
          );
        } else if (selectedRepresentation.representationType ==
            'explicit_suffix_phoneme') {
          final clampedEnd = artifact.endWord > payloadUnits.length
              ? payloadUnits.length
              : artifact.endWord;
          payloadUnits.replaceRange(
            artifact.startWord,
            clampedEnd,
            _buildExplicitSuffixPayloadUnits(
              units: traceUnits,
              startWord: artifact.startWord,
              endWord: artifact.endWord,
              suffixPhoneme: selectedRepresentation.representationValue,
              artifactId: artifact.artifactId,
            ),
          );
        } else {
          final replacementUnit = _buildReplacementUnit(
            units: traceUnits,
          startWord: artifact.startWord,
          endWord: artifact.endWord,
          replacement: selectedRepresentation.representationValue,
        );
        final clampedEnd = artifact.endWord > traceUnits.length
            ? traceUnits.length
            : artifact.endWord;
        traceUnits.replaceRange(artifact.startWord, clampedEnd, <String>[
          replacementUnit,
        ]);
        payloadUnits.replaceRange(
          artifact.startWord,
          clampedEnd,
          <KokoroEnginePayloadUnit>[
            KokoroEnginePayloadUnit(
              kind: KokoroEnginePayloadUnitKind.plainText,
              value: replacementUnit,
              artifactIds: <String>[artifact.artifactId],
            ),
          ],
        );
      }
    } else if (capabilityProfile.supportsApproximation(
      selectedRepresentation.representationType,
    )) {
      translationOutcome = KokoroPronunciationTranslationOutcome.approximated;
      final replacementUnit = _buildReplacementUnit(
        units: traceUnits,
        startWord: artifact.startWord,
        endWord: artifact.endWord,
        replacement: selectedRepresentation.representationValue,
      );
      final clampedEnd = artifact.endWord > traceUnits.length
          ? traceUnits.length
          : artifact.endWord;
      traceUnits.replaceRange(artifact.startWord, clampedEnd, <String>[
        replacementUnit,
      ]);
      payloadUnits.replaceRange(
        artifact.startWord,
        clampedEnd,
        <KokoroEnginePayloadUnit>[
          KokoroEnginePayloadUnit(
            kind: KokoroEnginePayloadUnitKind.plainText,
            value: replacementUnit,
            artifactIds: <String>[artifact.artifactId],
          ),
        ],
      );
    } else {
      translationOutcome = capabilityProfile.supportsPlainTextFallback
          ? KokoroPronunciationTranslationOutcome.deferred
          : KokoroPronunciationTranslationOutcome.deferred;
    }

    translatedArtifacts.add(
      KokoroTranslatedPronunciationArtifact(
        artifactId: artifact.artifactId,
        segmentId: artifact.segmentId,
        startWord: artifact.startWord,
        endWord: artifact.endWord,
        resolutionClass: artifact.resolutionClass,
        translationIntent: artifact.translationIntent,
        translationOutcome: translationOutcome,
        representationType: selectedRepresentation?.representationType,
        representationValue: selectedRepresentation?.representationValue,
        diagnosticCodes: artifact.diagnosticCodes,
      ),
    );
  }

  for (var index = tokenMatches.length - 1; index >= 0; index -= 1) {
    if (coveredWordIndexes.contains(index)) {
      continue;
    }

    final tokenBackstop = _dictionaryBackstopForUnit(traceUnits[index]);
    if (tokenBackstop == null) {
      continue;
    }

    final clampedEnd = index + 1 > payloadUnits.length ? payloadUnits.length : index + 1;
    payloadUnits.replaceRange(
      index,
      clampedEnd,
      _buildDirectPhonemePayloadUnits(
        units: traceUnits,
        startWord: index,
        endWord: index + 1,
        phonemeString: tokenBackstop.phonemeString,
        artifactId: tokenBackstop.artifactId,
      ),
    );
    coveredWordIndexes.add(index);
    translatedArtifacts.add(
      KokoroTranslatedPronunciationArtifact(
        artifactId: tokenBackstop.artifactId,
        segmentId: segment.segmentId,
        startWord: index,
        endWord: index + 1,
        resolutionClass: 'dictionary_backstop',
        translationIntent: 'phoneme_string',
        translationOutcome: KokoroPronunciationTranslationOutcome.direct,
        representationType: 'phoneme_string',
        representationValue: tokenBackstop.phonemeString,
        diagnosticCodes: const <String>[
          'pronunciation.resolved.cmudict_backstop',
        ],
      ),
    );
  }

  final missingFallbackWordCount =
      tokenMatches.length - coveredWordIndexes.length;

  return _TranslatedSegment(
    speakText: traceUnits.join().trim(),
    payloadUnits: payloadUnits,
    pronunciationArtifacts: translatedArtifacts.reversed.toList(
      growable: false,
    ),
    missingFallbackWordCount: missingFallbackWordCount < 0
        ? 0
        : missingFallbackWordCount,
  );
}

bool _isEnglishSClassAllomorphArtifact(RealizedPronunciationArtifact artifact) {
  return artifact.diagnosticCodes.contains(
    'pronunciation.resolved.possessive_allomorph',
  );
}

String _buildReplacementUnit({
  required List<String> units,
  required int startWord,
  required int endWord,
  required String replacement,
}) {
  if (units.isEmpty || startWord < 0 || endWord <= startWord) {
    return replacement;
  }
  if (startWord >= units.length) {
    return replacement;
  }

  final clampedEnd = endWord > units.length ? units.length : endWord;
  final firstToken = _splitTrailingWhitespace(units[startWord]).token;
  final lastUnitParts = _splitTrailingWhitespace(units[clampedEnd - 1]);
  final lastToken = lastUnitParts.token;
  final leading = _leadingPunctuation(firstToken);
  final trailing = _trailingPunctuation(lastToken);
  final trailingWhitespace = lastUnitParts.trailingWhitespace;

  return '$leading$replacement$trailing$trailingWhitespace';
}

List<KokoroEnginePayloadUnit> _buildDirectPhonemePayloadUnits({
  required List<String> units,
  required int startWord,
  required int endWord,
  required String phonemeString,
  required String artifactId,
}) {
  if (units.isEmpty || startWord < 0 || endWord <= startWord) {
    return const <KokoroEnginePayloadUnit>[];
  }
  if (startWord >= units.length) {
    return const <KokoroEnginePayloadUnit>[];
  }

  final clampedEnd = endWord > units.length ? units.length : endWord;
  final firstToken = _splitTrailingWhitespace(units[startWord]).token;
  final lastUnitParts = _splitTrailingWhitespace(units[clampedEnd - 1]);
  final lastToken = lastUnitParts.token;
  final leading = _leadingPunctuation(firstToken);
  final trailing = _trailingPunctuation(lastToken);
  final trailingWhitespace = lastUnitParts.trailingWhitespace;

  final replacementUnits = <KokoroEnginePayloadUnit>[];
  if (leading.isNotEmpty) {
    replacementUnits.add(
      KokoroEnginePayloadUnit(
        kind: KokoroEnginePayloadUnitKind.plainText,
        value: leading,
      ),
    );
  }
  replacementUnits.add(
    KokoroEnginePayloadUnit(
      kind: KokoroEnginePayloadUnitKind.phonemeString,
      value: phonemeString,
      artifactIds: <String>[artifactId],
    ),
  );
  if (trailing.isNotEmpty || trailingWhitespace.isNotEmpty) {
    replacementUnits.add(
      KokoroEnginePayloadUnit(
        kind: KokoroEnginePayloadUnitKind.plainText,
        value: '$trailing$trailingWhitespace',
      ),
    );
  }
  return replacementUnits;
}

List<KokoroEnginePayloadUnit> _buildExplicitSuffixPayloadUnits({
  required List<String> units,
  required int startWord,
  required int endWord,
  required String suffixPhoneme,
  required String artifactId,
}) {
  if (units.isEmpty || startWord < 0 || endWord <= startWord) {
    return const <KokoroEnginePayloadUnit>[];
  }
  if (startWord >= units.length) {
    return const <KokoroEnginePayloadUnit>[];
  }

  final clampedEnd = endWord > units.length ? units.length : endWord;
  final lastUnitParts = _splitTrailingWhitespace(units[clampedEnd - 1]);
  final trailingWhitespace = lastUnitParts.trailingWhitespace;
  final tokenValue = units.sublist(startWord, clampedEnd).join().trim();
  final explicitOverride = parseExplicitPhonemeSuffixOverride(tokenValue);
  final leadingPunctuation =
      explicitOverride?.leadingPunctuation ??
      _leadingPunctuation(_splitTrailingWhitespace(units[startWord]).token);
  final baseSurfaceText =
      explicitOverride?.baseSurfaceText ??
      englishSClassRealizationForToken(tokenValue)?.baseSurfaceText;
  final trailingPunctuation =
      explicitOverride?.trailingPunctuation ??
      _trailingPunctuation(lastUnitParts.token);
  if (baseSurfaceText == null || baseSurfaceText.trim().isEmpty) {
    return <KokoroEnginePayloadUnit>[
      KokoroEnginePayloadUnit(
        kind: KokoroEnginePayloadUnitKind.plainText,
        value: units.sublist(startWord, clampedEnd).join(),
      ),
    ];
  }

  final replacementUnits = <KokoroEnginePayloadUnit>[];
  if (leadingPunctuation.isNotEmpty) {
    replacementUnits.add(
      KokoroEnginePayloadUnit(
        kind: KokoroEnginePayloadUnitKind.plainText,
        value: leadingPunctuation,
      ),
    );
  }
  replacementUnits.add(
    KokoroEnginePayloadUnit(
      kind: KokoroEnginePayloadUnitKind.explicitSuffixPhoneme,
      value: jsonEncode(<String, String>{
        'baseSurfaceText': baseSurfaceText,
        'suffixPhoneme': suffixPhoneme,
      }),
      artifactIds: <String>[artifactId],
    ),
  );
  if (trailingPunctuation.isNotEmpty || trailingWhitespace.isNotEmpty) {
    replacementUnits.add(
      KokoroEnginePayloadUnit(
        kind: KokoroEnginePayloadUnitKind.plainText,
        value: '$trailingPunctuation$trailingWhitespace',
      ),
    );
  }
  return replacementUnits;
}

List<KokoroEnginePayloadUnit> _buildEnglishSClassPayloadUnits({
  required List<String> units,
  required int startWord,
  required int endWord,
  required String artifactId,
}) {
  if (units.isEmpty || startWord < 0 || endWord <= startWord) {
    return const <KokoroEnginePayloadUnit>[];
  }
  if (startWord >= units.length) {
    return const <KokoroEnginePayloadUnit>[];
  }

  final clampedEnd = endWord > units.length ? units.length : endWord;
  final firstToken = _splitTrailingWhitespace(units[startWord]).token;
  final lastUnitParts = _splitTrailingWhitespace(units[clampedEnd - 1]);
  final lastToken = lastUnitParts.token;
  final leading = _leadingPunctuation(firstToken);
  final trailing = _trailingPunctuation(lastToken);
  final trailingWhitespace = lastUnitParts.trailingWhitespace;
  final tokenValue = units.sublist(startWord, clampedEnd).join().trim();

  final replacementUnits = <KokoroEnginePayloadUnit>[];
  if (leading.isNotEmpty) {
    replacementUnits.add(
      KokoroEnginePayloadUnit(
        kind: KokoroEnginePayloadUnitKind.plainText,
        value: leading,
      ),
    );
  }
  replacementUnits.add(
    KokoroEnginePayloadUnit(
      kind: KokoroEnginePayloadUnitKind.englishSClassAllomorph,
      value: tokenValue,
      artifactIds: <String>[artifactId],
    ),
  );
  if (trailing.isNotEmpty || trailingWhitespace.isNotEmpty) {
    replacementUnits.add(
      KokoroEnginePayloadUnit(
        kind: KokoroEnginePayloadUnitKind.plainText,
        value: '$trailing$trailingWhitespace',
      ),
    );
  }
  return replacementUnits;
}

String _leadingPunctuation(String token) {
  final match = RegExp(r'^[^A-Za-z0-9]+').firstMatch(token);
  return match?.group(0) ?? '';
}

String _trailingPunctuation(String token) {
  final match = RegExp(r'[^A-Za-z0-9]+$').firstMatch(token);
  return match?.group(0) ?? '';
}

_TokenWithTrailingWhitespace _splitTrailingWhitespace(String unit) {
  final match = RegExp(r'(\s*)$').firstMatch(unit);
  final trailingWhitespace = match?.group(1) ?? '';
  final token = trailingWhitespace.isEmpty
      ? unit
      : unit.substring(0, unit.length - trailingWhitespace.length);
  return _TokenWithTrailingWhitespace(
    token: token,
    trailingWhitespace: trailingWhitespace,
  );
}

class _TokenWithTrailingWhitespace {
  const _TokenWithTrailingWhitespace({
    required this.token,
    required this.trailingWhitespace,
  });

  final String token;
  final String trailingWhitespace;
}

class _DictionaryBackstop {
  const _DictionaryBackstop({
    required this.artifactId,
    required this.phonemeString,
  });

  final String artifactId;
  final String phonemeString;
}

const Set<String> _reductionSensitiveFunctionWords = <String>{
  'a',
  'an',
  'and',
  'are',
  'as',
  'at',
  'be',
  'been',
  'being',
  'but',
  'by',
  'from',
  'had',
  'has',
  'have',
  'he',
  'her',
  'him',
  'his',
  'i',
  'in',
  'is',
  'it',
  'me',
  'my',
  'of',
  'on',
  'or',
  'our',
  'she',
  'that',
  'the',
  'their',
  'them',
  'there',
  'they',
  'this',
  'those',
  'to',
  'us',
  'was',
  'we',
  'were',
  'what',
  'when',
  'where',
  'who',
  'why',
  'with',
  'would',
  'you',
  'your',
};

_DictionaryBackstop? _dictionaryBackstopForUnit(String unit) {
  final token = _splitTrailingWhitespace(unit).token;
  if (token.trim().isEmpty) {
    return null;
  }

  final normalizedToken = normalizeEnglishSpeechText(
    token
      .replaceAll(RegExp(r"^[^A-Za-z0-9']+|[^A-Za-z0-9']+$"), '')
      .trim(),
  ).toLowerCase();
  if (normalizedToken.isEmpty) {
    return null;
  }
  if (!normalizedToken.contains("'") &&
      _reductionSensitiveFunctionWords.contains(normalizedToken)) {
    return null;
  }

  final phonemeString = EnglishPronunciationDictionaryService.instance.lookup(
    normalizedToken,
  );
  if (phonemeString == null || phonemeString.trim().isEmpty) {
    return null;
  }

  return _DictionaryBackstop(
    artifactId: 'dict_$normalizedToken',
    phonemeString: phonemeString,
  );
}
