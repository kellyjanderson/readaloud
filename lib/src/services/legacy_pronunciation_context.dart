import '../models/pronunciation_artifact.dart';
import 'pronunciation_lexical_resources.dart';
import 'document_time_pronunciation_planner_service.dart';

/// Compatibility is a bounded, audited inventory, not permission inferred from
/// missing metadata. Range assembly historically prefixed representation IDs.
SpeechAdjustmentContext legacyPronunciationContext(
  Map<String, dynamic> representation,
  String source,
) {
  final id = (representation['representationId'] as String).replaceFirst(
    RegExp(r'^(?:range\d+:)+'),
    '',
  );
  final type = representation['representationType'];
  final value = representation['representationValue'];
  if (source == 'appLexicon') {
    for (final entries in defaultPronunciationResourceLayers.values) {
      for (final candidates in entries.values) {
        for (final candidate in candidates) {
          if (candidate.representationId == id &&
              candidate.representationType == type &&
              candidate.representationValue == value &&
              candidate.accentFamily == representation['accentFamily']) {
            return candidate.context;
          }
        }
      }
    }
  }
  if (source == 'ruleBasedInference' &&
      ((id.startsWith('rule_number_') &&
              type == 'normalized_spoken_text' &&
              value is String &&
              value ==
                  spokenNumberForToken(id.substring('rule_number_'.length))) ||
          (id == 'rule_bow_weapon_phoneme' &&
              type == 'phoneme_string' &&
              value == 'bˈoʊ') ||
          (id.startsWith('english_suffix_allomorph_') &&
              type == 'explicit_suffix_phoneme' &&
              const ['s', 'z', 'ɪz'].contains(value)))) {
    return const SpeechAdjustmentContext.content(
      'legacy:canonical-linguistic-rules:v1',
    );
  }
  if (source == 'userOverride' &&
      id.startsWith('explicit_suffix_') &&
      type == 'explicit_suffix_phoneme') {
    return const SpeechAdjustmentContext.content(
      'legacy:explicit-suffix-ipa:v1',
    );
  }
  return const SpeechAdjustmentContext.unresolved();
}
