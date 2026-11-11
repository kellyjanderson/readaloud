# Engine Pronunciation Expression and Capability Adaptation

Reconciled: November 4, 2026
Status: Current source architecture; bounded pronunciation regressions in #58 and #120; Fish acoustic acceptance remains open

## Implemented structure and limitations

`EngineCapabilityProfile` declares direct and approximable representation types and plain-text fallback. Kokoro translation consumes app-owned pronunciation artifacts and produces direct, approximated or deferred outcomes and engine payload units. Canonical IPA adaptation occurs at the Kokoro boundary.

Translation retains one payload slot per original word while applying explicit pronunciation artifacts and dictionary backstops, then flattens the slots for the engine. Punctuation or whitespace expansion cannot shift a later word's replacement index; multiword replacements empty their consumed slots without renumbering later words. [Issue #58](https://github.com/kellyjanderson/readaloud/issues/58) records the preceding defect: explicit phonemes for `John` followed by dictionary `said` produced both phoneme and plain-text copies of `said`. Regression tests cover that mixed path, quoted punctuation, and a multiword approximation followed by a dictionary word.

Translation details contribute to runtime cache signatures. Prepared resource references separately validate model/voice content fingerprints, and raw audio identity also includes the exact effective rate, tokens, pronunciation realization and tokenizer/profile identity; see [artifact identity](audio-artifact-identity-and-lifetime.md). Capability declarations describe the supported representation path, not universal acoustic correctness.

`SpeechAdjustmentContext` distinguishes explicitly declared document content intent from a versioned engine/model adjustment reference. Missing context is unresolved, never implicitly portable. Canonical IPA, linguistic normalization and explicit document pronunciation requests carry content provenance. A model workaround belongs in `SpeechAdjustmentRegistry`: its record contains ID/revision, domain, source reference, rationale, originating context, explicit permitted target contexts and payload. Matching requires exact engine, model, model revision, capability-policy version and payload/domain agreement. Model families and precision variants do not inherit each other's recipes. Missing model identity, unknown/duplicate definitions, revision mismatch and incomplete provenance defer the adjustment while retaining original intent.

The initial registered recipe is `kokoro.for-respelling` revision `1`, restricted to the declared bundled `kokoro-v1.0.onnx` revision 1.0 / policy v1 context. It replaces the R6 inline `lex_for_spoken` check. Context references are stored in pronunciation representations and survive `.radoc` serialization and range-ID renumbering. A bounded legacy inventory recognizes known canonical producers and the old Kokoro recipe; unknown historical overrides remain unresolved. No model-specific recipe is registered for MLX. Its profile therefore leaves model identity unknown unless explicitly supplied, and cannot acquire an adaptation through an engine name alone. Policy model declarations do not verify arbitrary substituted model files; existing prepared-resource digests remain the authority for actual bytes and audio cache identity.

Both production playback and export tokenization owners now receive the selected capability profile explicitly. Worker construction and translation require it; neither silently defaults to Kokoro. Dictionary phoneme backstops and suffix payloads also require the relevant capability. Translation diagnostics carry the adjustment reference, provenance, requested model context and match/defer reason, which participate in translated runtime/raw-audio identity. Unchanged canonical payloads retain their existing identity; existing audio is never purged by this migration.

The same registry domains cover delivery, inflection, emphasis and boundary adaptations. Explicit performance requests remain document intent with their original source/annotation references. No delivery/emotion recipe is currently enabled: realization retains these requests as unsupported with `engine_default` fallback, without inserting another model's control tags. General segmentation and playback boundary handling remain separate application policies; this change does not qualify model-specific expressive behavior. Source and resident-worker tests establish applicability and engine input, not perceived pronunciation quality or native app acceptance.

Current adapter work is centered on Kokoro with generic fallback capability behavior. Adding another engine requires explicit adaptation and tests; it must not silently reinterpret canonical pronunciation intent.

### Fish checkpoint declarations

`FishDramaCatalog` in [speech_engine_catalog.dart](../../lib/src/models/speech_engine_catalog.dart)
provides an additive, immutable Dart view of the existing
[Fish variant catalog](../../assets/fish_drama_models.json), which remains shared
with the Python model owner. Saved engine IDs and labels are
unchanged. Asset loading belongs to the caller; parsing has no I/O, scheduling or
download side effects. The model catalog requires a
pinned commit and the fixed `mlx-community` Hugging Face repository policy,
validates safe required-file names and core model artifacts, and rejects unknown
IDs, checkpoint precision inconsistent with a saved ID, duplicate checkpoint
identities and malformed/incomplete checksum data.

The bundled [checksum manifests](../../assets/fish_drama_model_checksums.json)
use schema version 2, keyed by the three saved Fish engine IDs. Each attaches
only to its exact repository/revision and covers every required artifact. The
parser also accepts the prior single-manifest schema for compatibility. The
nested bf16 manifest is unchanged, preserving existing stat-bound verification
receipt identity. Quantized manifests come from their immutable upstream tree
metadata; their differing source lineage is not a matched quality comparison.
A descriptor declares expected file sizes and digests; parsing does not hash or
qualify installed model bytes. Existing
`estimatedPeakBytes` values remain estimates, not measured memory envelopes or
admission evidence. Descriptors do not confer native-scene, expressive, runtime
compatibility or acoustic qualification.

This implements the catalog and managed-acquisition boundary for
[ACD-M1 R1 / #112](https://github.com/kellyjanderson/readaloud/issues/112#acd-m1--verified-model-assets-and-live-engine-sessions).
The MLX resource owner uses the typed descriptor for installed-file requirements
and the expected pinned identity. Managed Hub cache roots, including older
app-support locations, go to the existing Python acquisition owner rather than
being passed as explicit model folders: direct passthrough would bypass its
corrupt-file repair on retry. The same Hugging Face downloader checks accessible
caches offline first, verifies required bytes, repairs only corrupt owned files
and resumes missing files in one chosen cache. It publishes atomic stat-bound
verification receipts after complete validation. Other variants and partials
are retained. Legacy unpacked folders are read-only candidates; invalid bytes
fail verification rather than authorizing arbitrary-folder repair. Explicit
developer overrides retain their existing provenance and qualification checks.

The main-isolate processor owns its frozen catalog/load specification. One
Python protocol request owns hashing and the maintained Hub transfer workers;
no new acquisition scheduler or queue is introduced. Existing cancellation
retires the helper out of band and joins it before reuse, retaining resumable
files. The Dart exchange requires verified bytes and the exact pinned reply
before publishing a normal managed model, including automatic reload after
cancellation. Missing or mismatched verification poisons and reaps that child.
The existing request/child identities still reject stale progress and results.

Hub 2.4 rejects incomplete local snapshots before returning their path. The
application therefore inventories only safely owned exact pins after that
exception, verifies their required files, and selects the candidate with the
most stable verified bytes. A failed attempt retains that one destination.
Hub still owns transfer, locks, resumable partials and atomic publication; a
missing file cannot redirect Retry into a second full model download.

Focused [catalog fixtures](../../test/speech_engine_catalog_test.dart),
[real-child protocol tests](../../test/mlx_python_process_test.dart) and
[tiny real-hash acquisition fixtures](../../tools/mlx_tts_worker_test.py)
cover declaration, offline reuse, selective repair, interrupted retry, receipt
ownership and rejected/reloaded child paths. They do not alone establish
complete-model transfer performance, emitted speech, live-session switching or
memory qualification. Bounded native observations and failed controls are
recorded in [M5 resource evidence](../test-artifacts/s7-m5-r2-20261111/README.md)
and [subsequent native evidence](../test-artifacts/s7-m5-r3-20261111/README.md).
Physical M3 qualification remains open; listening/usability is collected for
S11. Software captures do not establish physical-speaker or human acceptance.

## Source and tests

- [engine_capability.dart](../../lib/src/models/engine_capability.dart)
- [speech_engine_catalog.dart](../../lib/src/models/speech_engine_catalog.dart)
- [speech_engine_catalog_test.dart](../../test/speech_engine_catalog_test.dart)
- [speech_adjustment_context.dart](../../lib/src/models/speech_adjustment_context.dart)
- [speech_adjustment_registry.dart](../../lib/src/services/speech_adjustment_registry.dart)
- [legacy_pronunciation_context.dart](../../lib/src/services/legacy_pronunciation_context.dart)
- [kokoro_pronunciation_translation_service.dart](../../lib/src/services/kokoro_pronunciation_translation_service.dart)
- [kokoro_ipa_adapter.dart](../../lib/src/services/kokoro_ipa_adapter.dart)
- [kokoro_tts_engine.dart](../../lib/src/services/kokoro_tts_engine.dart)
- [engine_capability_registry_test.dart](../../test/engine_capability_registry_test.dart)
- [kokoro_pronunciation_translation_service_test.dart](../../test/kokoro_pronunciation_translation_service_test.dart)
- [engine_pronunciation_scope_test.dart](../../test/engine_pronunciation_scope_test.dart)
- [speech_adjustment_registry_test.dart](../../test/speech_adjustment_registry_test.dart)
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

## Model resource admission and catalog lifetime

[Fish catalog storage](../../lib/src/services/fish_drama_catalog_store.dart) loads
validated last-valid data above the bundled version floor. One session freezes
its descriptor, checksums and helper path; a bounded fixed-origin data-only
refresh can affect a later session. Terminal shutdown cancels/drains its HTTP
owner. Document resource release retains the session catalog. Profile metadata
does not enter the legacy generated-audio content identity or confer native
scene qualification on new weights.

[Memory policy](../../lib/src/services/runtime_memory_policy.dart) combines
native app/descendant enumeration with fresh, lifetime-fenced child self samples
through the [registry](../../lib/src/services/runtime_memory_registry.dart).
macOS permits the BSD process table where sandboxed libproc enumeration is
denied. Unknown descendants and stale/missing coverage fail closed. Sampling is
utility-queue owned; the main isolate admits at most one sample per owner.
Physical footprint already includes charged native/Metal/audio allocations;
MLX allocator counters are not added again. Reclaimable-cache headroom uses
Mach free minus speculative plus file-backed pages, with a reserve of the larger
of 2 GB or 5% of RAM and normal kernel pressure. A 1 GB guard precedes the
100,000,000,000-byte ceiling. Neither periodic samples nor allocator limits prove
all between-sample maxima.

[Qualified selection](../../lib/src/services/qualified_engine_selection_service.dart)
runs only for an unset choice. It uses the current offline catalog and exact
checkpoint/runtime/device receipts, ordered bf16, 8bit, 4bit. Explicit and unknown
saved choices remain intent. Unknown envelopes do not become defaults from
estimates. Reviewed [M5 resource observations](../test-artifacts/s7-m5-r2-20261111/memory-qualification.json)
supply conservative additional admission budgets: observed whole-tree peaks
plus 25%, rounded up to decimal GB. Actual load/reload reapplies the same exact
receipt and current headroom. A deliberate unqualified choice remains clearly
monitored qualification. M3 has no reviewed record. Human listening and release
qualification remain separate gates in issue #112 and S11.
