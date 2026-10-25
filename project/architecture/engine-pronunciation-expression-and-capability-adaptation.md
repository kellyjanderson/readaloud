# Engine Pronunciation Expression and Capability Adaptation

Reconciled: October 24, 2026
Status: Current source architecture; runtime validation not refreshed

## Implemented structure and limitations

`EngineCapabilityProfile` declares direct and approximable representation types and plain-text fallback. Kokoro translation consumes app-owned pronunciation artifacts and produces direct, approximated or deferred outcomes and engine payload units. Canonical IPA adaptation occurs at the Kokoro boundary.

Translation details contribute to runtime cache signatures. This is distinct from model-file and voice-file content fingerprints, which are not currently validated as part of character bindings. Capability declarations describe the supported representation path, not universal acoustic correctness.

Current adapter work is centered on Kokoro with generic fallback capability behavior. Adding another engine requires explicit adaptation and tests; it must not silently reinterpret canonical pronunciation intent.

## Source and tests

- [engine_capability.dart](../../lib/src/models/engine_capability.dart)
- [kokoro_pronunciation_translation_service.dart](../../lib/src/services/kokoro_pronunciation_translation_service.dart)
- [kokoro_ipa_adapter.dart](../../lib/src/services/kokoro_ipa_adapter.dart)
- [kokoro_tts_engine.dart](../../lib/src/services/kokoro_tts_engine.dart)
- [engine_capability_registry_test.dart](../../test/engine_capability_registry_test.dart)
- [kokoro_pronunciation_translation_service_test.dart](../../test/kokoro_pronunciation_translation_service_test.dart)
- [kokoro_ipa_adapter_test.dart](../../test/kokoro_ipa_adapter_test.dart)

Tests listed here are existing evidence locations, not a claim that they passed in this review. The bundled Intel Dart executable cannot run in the current Apple Silicon execution environment.

## Proposed changes

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
