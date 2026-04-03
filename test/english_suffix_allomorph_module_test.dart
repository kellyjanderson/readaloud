import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/english_pronunciation_profile.dart';
import 'package:read_aloud/src/services/english_suffix_allomorph_module.dart';
import 'package:read_aloud/src/services/pronunciation_resource_layering_service.dart';
import 'package:read_aloud/src/services/pronunciation_rule_module.dart';

void main() {
  group('EnglishSuffixAllomorphModule', () {
    const module = EnglishSuffixAllomorphModule();
    const emptyResources = MergedPronunciationResources.empty();

    PronunciationRuleModuleDecision applyTo(String surfaceText) {
      return module.apply(
        const PronunciationRuleModuleContext(
          segmentId: 's0',
          segmentText: '',
          tokenIndex: 0,
          surfaceText: 'placeholder',
          normalizedSurfaceText: 'placeholder',
          selectedProfile: EnglishPronunciationProfileRegistry.enUsCore,
          mergedResources: emptyResources,
        ).copyWithPlaceholder(surfaceText),
      );
    }

    test('selects voiced z allomorph by default for possessives', () {
      final decision = applyTo("John's");
      expect(decision.kind, PronunciationRuleModuleDecisionKind.resolved);
      expect(
        decision.representations.map(
          (representation) => representation.representationType,
        ),
        contains('explicit_suffix_phoneme'),
      );
      expect(
        decision.representations.map(
          (representation) => representation.representationValue,
        ),
        contains('z'),
      );
    });

    test('defaults non-sibilant possessives to voiced z allomorph', () {
      final decision = applyTo("cat's");
      expect(decision.representations.first.representationValue, 'z');
    });

    test('selects extra syllable allomorph after sibilants', () {
      final decision = applyTo("bus's");
      expect(decision.representations.first.representationValue, 'ɪz');
    });

    test('does not rewrite contractions', () {
      final decision = applyTo("it's");
      expect(decision.kind, PronunciationRuleModuleDecisionKind.noDecision);
    });

    test('exposes structured english s-class realization for engine use', () {
      final realization = englishSClassRealizationForToken("\"John's,\"");
      expect(realization, isNotNull);
      expect(realization!.baseSurfaceText, 'John');
      expect(realization.allomorph, EnglishPossessiveAllomorph.z);
      expect(
        englishSClassSuffixPhoneme(realization.allomorph),
        'z',
      );
    });

    test('ignores punctuation-only tokens safely', () {
      final realization = englishSClassRealizationForToken('”...’');
      expect(realization, isNull);
    });
  });
}

extension on PronunciationRuleModuleContext {
  PronunciationRuleModuleContext copyWithPlaceholder(String surfaceText) {
    return PronunciationRuleModuleContext(
      segmentId: segmentId,
      segmentText: segmentText,
      tokenIndex: tokenIndex,
      surfaceText: surfaceText,
      normalizedSurfaceText: surfaceText.toLowerCase(),
      selectedProfile: selectedProfile,
      mergedResources: mergedResources,
      previousToken: previousToken,
      nextToken: nextToken,
    );
  }
}
