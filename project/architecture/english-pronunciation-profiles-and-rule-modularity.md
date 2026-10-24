# English Pronunciation Profiles and Rule Modularity

Reconciled: October 24, 2026
Status: Current source architecture; runtime validation not refreshed

## Implemented structure and limitations

The registry defines US, GB, AU and a US German-accented profile. The selector considers an explicit profile request, voice metadata and locale before fallback. Resource layering and rule-module contracts are explicit services rather than engine-private decisions. The English suffix allomorph module implements productive suffix behavior.

A registered profile is not a claim of complete accent modeling or validated naturalness. Profile-aware planning/realization uses the available lexical resources and modules; engine inventory adaptation remains downstream. Expanded stress, reduction and delivery coverage should be proposed as bounded ACD changes with representative audio evaluation.

## Source and tests

- [english_pronunciation_profile.dart](../../lib/src/models/english_pronunciation_profile.dart)
- [english_pronunciation_profile_selector.dart](../../lib/src/services/english_pronunciation_profile_selector.dart)
- [pronunciation_resource_layering_service.dart](../../lib/src/services/pronunciation_resource_layering_service.dart)
- [english_suffix_allomorph_module.dart](../../lib/src/services/english_suffix_allomorph_module.dart)
- [english_pronunciation_profile_selector_test.dart](../../test/english_pronunciation_profile_selector_test.dart)
- [pronunciation_resource_layering_service_test.dart](../../test/pronunciation_resource_layering_service_test.dart)
- [english_suffix_allomorph_module_test.dart](../../test/english_suffix_allomorph_module_test.dart)

Tests listed here are existing evidence locations, not a claim that they passed in this review. The bundled Intel Dart executable cannot run in the current Apple Silicon execution environment.

## Proposed changes

See [prepared document runtime ACD](../acd/prepared-document-runtime.acd) and its [implementation plan](../planning/prepared-document-runtime.plan). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/english-pronunciation-profiles-and-rule-modularity.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use an ACD and plan.

- [document time profile aware pronunciation planning](../specifications/document-time-profile-aware-pronunciation-planning.md)
- [english pronunciation profile model](../specifications/english-pronunciation-profile-model.md)
- [english pronunciation profile selection policy](../specifications/english-pronunciation-profile-selection-policy.md)
- [english suffix allomorph module](../specifications/english-suffix-allomorph-module.md)
- [pronunciation resource layering policy](../specifications/pronunciation-resource-layering-policy.md)
- [pronunciation rule module contract](../specifications/pronunciation-rule-module-contract.md)
- [voice session profile aware pronunciation realization](../specifications/voice-session-profile-aware-pronunciation-realization.md)
