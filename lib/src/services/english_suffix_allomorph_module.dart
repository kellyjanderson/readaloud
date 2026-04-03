import '../models/pronunciation_artifact.dart';
import 'pronunciation_rule_module.dart';

class EnglishSuffixAllomorphModule extends PronunciationRuleModule {
  const EnglishSuffixAllomorphModule();

  static const moduleIdValue = 'english_suffix_allomorph';

  @override
  String get moduleId => moduleIdValue;

  @override
  bool get supportsDocumentTime => true;

  @override
  bool get supportsSessionTime => false;

  @override
  PronunciationRuleModuleDecision apply(PronunciationRuleModuleContext context) {
    final realization = englishSClassRealizationForToken(context.surfaceText);
    if (realization == null) {
      return const PronunciationRuleModuleDecision.noDecision();
    }
    final spokenPossessive = switch (realization.allomorph) {
      EnglishPossessiveAllomorph.iz => '${realization.baseSurfaceText}es',
      EnglishPossessiveAllomorph.s => '${realization.baseSurfaceText}s',
      EnglishPossessiveAllomorph.z => '${realization.baseSurfaceText}z',
    };
    final representations = <PronunciationRepresentation>[];
    representations.add(
      PronunciationRepresentation(
        representationId:
            '${moduleId}_${context.selectedProfile.profileId}_${context.normalizedSurfaceText}_suffix',
        representationType: 'explicit_suffix_phoneme',
        representationValue: englishSClassSuffixPhoneme(realization.allomorph),
        accentFamily: context.selectedProfile.accentFamily,
        priority: 110,
      ),
    );
    representations.add(
      PronunciationRepresentation(
        representationId:
            '${moduleId}_${context.selectedProfile.profileId}_${context.normalizedSurfaceText}',
        representationType: 'normalized_spoken_text',
        representationValue: spokenPossessive,
        accentFamily: context.selectedProfile.accentFamily,
        priority: 82,
      ),
    );
    return PronunciationRuleModuleDecision(
      kind: PronunciationRuleModuleDecisionKind.resolved,
      representations: representations,
      diagnosticCodes: const <String>[
        'pronunciation.resolved.rule_based',
        'pronunciation.resolved.possessive_allomorph',
      ],
      confidence: 0.91,
    );
  }
}

class EnglishSClassRealization {
  const EnglishSClassRealization({
    required this.surfaceText,
    required this.baseSurfaceText,
    required this.allomorph,
  });

  final String surfaceText;
  final String baseSurfaceText;
  final EnglishPossessiveAllomorph allomorph;
}

String? spokenPossessiveForEnglishToken(String surfaceText) {
  final realization = englishSClassRealizationForToken(surfaceText);
  if (realization == null) {
    return null;
  }
  return switch (realization.allomorph) {
    EnglishPossessiveAllomorph.iz => '${realization.baseSurfaceText}es',
    EnglishPossessiveAllomorph.s => '${realization.baseSurfaceText}s',
    EnglishPossessiveAllomorph.z => '${realization.baseSurfaceText}z',
  };
}

EnglishSClassRealization? englishSClassRealizationForToken(String surfaceText) {
  final trimmed = surfaceText.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final leadingPunctuation =
      RegExp(r'^[^A-Za-z]+').firstMatch(trimmed)?.group(0) ?? '';
  final trailingPunctuation =
      RegExp(r'[^A-Za-z]+$').firstMatch(trimmed)?.group(0) ?? '';
  final coreStart = leadingPunctuation.length;
  final coreEnd = trimmed.length - trailingPunctuation.length;
  if (coreStart >= coreEnd) {
    return null;
  }
  final core = trimmed.substring(coreStart, coreEnd).trim();
  if (core.isEmpty) {
    return null;
  }

  final match = RegExp(
    r"^([A-Za-z][A-Za-z-]*)(['’]s)$",
  ).firstMatch(core);
  if (match == null) {
    return null;
  }
  final base = match.group(1)!;
  final loweredBase = base.toLowerCase();
  if (loweredBase.length < 2) {
    return null;
  }
  if (_apostropheSPreserveSurfaceForms.contains(loweredBase)) {
    return null;
  }
  return EnglishSClassRealization(
    surfaceText: core,
    baseSurfaceText: base,
    allomorph: _selectEnglishPossessiveAllomorph(loweredBase),
  );
}

String englishSClassSuffixPhoneme(EnglishPossessiveAllomorph allomorph) {
  return switch (allomorph) {
    EnglishPossessiveAllomorph.s => 's',
    EnglishPossessiveAllomorph.z => 'z',
    EnglishPossessiveAllomorph.iz => 'ɪz',
  };
}

const Set<String> _apostropheSPreserveSurfaceForms = <String>{
  'he',
  'here',
  'how',
  'it',
  'let',
  'she',
  'that',
  'there',
  'what',
  'when',
  'where',
  'who',
  'why',
};

enum EnglishPossessiveAllomorph { s, z, iz }

EnglishPossessiveAllomorph _selectEnglishPossessiveAllomorph(String base) {
  if (_endsWithSibilant(base)) {
    return EnglishPossessiveAllomorph.iz;
  }
  return EnglishPossessiveAllomorph.z;
}

bool _endsWithSibilant(String base) {
  return base.endsWith('s') ||
      base.endsWith('x') ||
      base.endsWith('z') ||
      base.endsWith('sh') ||
      base.endsWith('ch') ||
      base.endsWith('ge') ||
      base.endsWith('dge');
}
