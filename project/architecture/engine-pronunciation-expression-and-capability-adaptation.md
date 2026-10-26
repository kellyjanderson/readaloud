# Engine Pronunciation Expression and Capability Adaptation

Reconciled: October 24, 2026
Status: Current source architecture; bounded pronunciation regression checked in #58

## Implemented structure and limitations

`EngineCapabilityProfile` declares direct and approximable representation types and plain-text fallback. Kokoro translation consumes app-owned pronunciation artifacts and produces direct, approximated or deferred outcomes and engine payload units. Canonical IPA adaptation occurs at the Kokoro boundary.

Translation retains one payload slot per original word while applying explicit pronunciation artifacts and dictionary backstops, then flattens the slots for the engine. Punctuation or whitespace expansion cannot shift a later word's replacement index; multiword replacements empty their consumed slots without renumbering later words. [Issue #58](https://github.com/kellyjanderson/readaloud/issues/58) records the preceding defect: explicit phonemes for `John` followed by dictionary `said` produced both phoneme and plain-text copies of `said`. Regression tests cover that mixed path, quoted punctuation, and a multiword approximation followed by a dictionary word.

Translation details contribute to runtime cache signatures. Prepared resource references separately validate model/voice content fingerprints, and raw audio identity also includes the exact effective rate, tokens, pronunciation realization and tokenizer/profile identity; see [artifact identity](audio-artifact-identity-and-lifetime.md). Capability declarations describe the supported representation path, not universal acoustic correctness.

Current adapter work is centered on Kokoro with generic fallback capability behavior. Adding another engine requires explicit adaptation and tests; it must not silently reinterpret canonical pronunciation intent.

## Source and tests

- [engine_capability.dart](../../lib/src/models/engine_capability.dart)
- [kokoro_pronunciation_translation_service.dart](../../lib/src/services/kokoro_pronunciation_translation_service.dart)
- [kokoro_ipa_adapter.dart](../../lib/src/services/kokoro_ipa_adapter.dart)
- [kokoro_tts_engine.dart](../../lib/src/services/kokoro_tts_engine.dart)
- [engine_capability_registry_test.dart](../../test/engine_capability_registry_test.dart)
- [kokoro_pronunciation_translation_service_test.dart](../../test/kokoro_pronunciation_translation_service_test.dart)
- [kokoro_ipa_adapter_test.dart](../../test/kokoro_ipa_adapter_test.dart)

The #58 translation, tokenizer, realization and boundary checks passed 30 tests on native arm64 Flutter 3.41.5 / Dart 3.11.3. A fresh three-chunk native export used matching fixture/model/voice fingerprints; only the affected first chunk's PCM changed, while the other two chunks remained identical. Local ASR changed from `John said said` to `John said`, corroborating the payload correction; it is not human listening. Agent-driven playback transitioned Play → Pause → Play, and its runtime trace contained one `said`. These bounded checks do not establish general pronunciation quality or prepared-runtime acceptance. Detailed evidence and limits are recorded in #58.

## Design and remaining acceptance

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/engine-pronunciation-expression-and-capability-adaptation.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [engine adapter translation boundary](../specifications/engine-adapter-translation-boundary.md)
- [engine capability model](../specifications/engine-capability-model.md)
- [engine intent translation policy](../specifications/engine-intent-translation-policy.md)
- [engine pronunciation translation policy](../specifications/engine-pronunciation-translation-policy.md)
- [kokoro phoneme inventory adaptation](../specifications/kokoro-phoneme-inventory-adaptation.md)
- [platform capability and fallback policy](../specifications/platform-capability-and-fallback-policy.md)
- [pronunciation fallback and traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [tts runtime chunk request derivation](../specifications/tts-runtime-chunk-request-derivation.md)
