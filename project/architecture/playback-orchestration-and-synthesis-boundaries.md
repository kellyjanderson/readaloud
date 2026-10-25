# Playback Orchestration and Synthesis Boundaries

Reconciled: October 24, 2026
Status: P3 bounded scheduling source; native acceptance is recorded in issue #52

## Implemented structure and limitations

The controller captures an immutable planning context and asks a resident pure Dart planning worker for an initial three-chunk window. The worker retains the prepared document, cast routes, offsets and routing indexes once per context identity. Refill requests carry scalar epoch/sequence/cursor/window size, and the engine keeps only the current planning window. Realization covers every segment in the returned window. Main-isolate state changes require current document and binding intent; no native handles enter the graph.

Separate playback/export tokenization supervisors retain initialized tokenizer, dictionary and capability state in pure Dart isolates. The main platform bridge reads raw asset strings; JSON decoding, dictionary growth, CMU conversion and fallback G2P initialization run in the worker. This avoids a pinned dependency's lazy root-bundle access inside a pure isolate. Cold-worker fidelity tests run before caller-side expected values can warm that dependency. Each owner has one active task and one latest pending task; superseded pending tasks terminate explicitly. Cancellation kills only pure workers, waits for exit, and rejects stale results. Translation and tokenization preserve explicit IPA, CMU backstop and suffix behavior; warm refills reuse worker state.

Playback uses contiguous source-order audio only. Startup requires at least two chunks totaling four seconds, eight seconds regardless of count, or all remaining audio for a short document. The five-second deadline fails startup explicitly; it never silently starts below target. Refill uses low four/high eight seconds with hysteresis, and a 64-chunk bound covering pending, staged and future native sources. Independent player speed divides PCM lead; synthesis rate is already reflected in emitted duration. A pathological startup needing more than 64 chunks to reach four seconds fails explicitly rather than waiting for impossible playback credit. This is a documented capacity limitation, not universal short-document acceptance.

Native playback appends later contiguous sources. Serialized history pruning removes completed predecessors while preserving the current source and native position, including after underrun seek recovery. Failed native playlist mutations have an owned terminal error and cleanup route; the serial drain remains usable for reset/replay. Initial `setAudioSources` remains the sole full source installation. Native traces must verify playlist/index behavior; source code alone cannot establish gapless output. Generated cache files have independent retention and are not bounded by this playlist policy.

Playback and export lease one prioritized synthesis admission owner: one native operation, at most three pending requests, playback before export. Export admission waits until playback has at least the low-water lead or no active generation. Runtime completion acknowledgment retains each pipeline slot through boundary correction, preserving predecessor order with no extra correction queue. Native inference drain/quarantine from P2 remains mandatory. Resource replacement cancels and drains export from its initial ownership stage, before changing the resident document; supplied resource references must match resident identity. Rate changes stop the old generation before changing rate and restart playing or buffering through the controller. User assignment safe-boundary commits remain P4 work.

Lease cancellation removes queued native admission even when the export lead gate is closed; already active native calls drain before their cancelled terminal. Pause signals admission after generation state settles. Natural document completion defers release while an export lease is active, then releases only if its resource and playback epochs remain current; pause, a replacement document and replay cannot inherit that release debt. The controller normalizes Kokoro intent into the supported 0.7–1.4 range before planning, and direct incompatible prepared plans are rejected. Cache plan identity, export and inference therefore use the same effective rate; independent player speed affects only playable wall-time lead.

When synthesis fails with an unplanned suffix, the engine terminates that session with an error rather than rebuilding only admitted chunks and silently truncating the document. Existing bounded fallback recovery remains available only after the entire suffix has been materialized. Policy constants and transport traces are not perceptual continuity guarantees; measured evidence and limitations are recorded in [P3](https://github.com/kellyjanderson/readaloud/issues/52).

## Source and tests

- [kokoro_tts_engine.dart](../../lib/src/services/kokoro_tts_engine.dart)
- [kokoro_playback_coordination.dart](../../lib/src/services/kokoro_playback_coordination.dart)
- [synthesis_boundary_policy.dart](../../lib/src/services/synthesis_boundary_policy.dart)
- [speech_runtime.dart](../../lib/src/services/speech_runtime.dart)
- [kokoro_playback_coordination_test.dart](../../test/kokoro_playback_coordination_test.dart)
- [synthesis_boundary_policy_test.dart](../../test/synthesis_boundary_policy_test.dart)
- [reader_controller_playback_test.dart](../../test/reader_controller_playback_test.dart)

P3 also adds admission, resident-planning, tokenizer and export-revision regressions. Use the pinned native arm64 SDK in development guidance. Source tests, native queue observations and acoustic evidence remain distinct acceptance layers.

## Proposed changes

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/playback-orchestration-and-synthesis-boundaries.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [append only forward playback queue](../specifications/append-only-forward-playback-queue.md)
- [boundary candidate metadata contract](../specifications/boundary-candidate-metadata-contract.md)
- [boundary corrected chunk output and reuse](../specifications/boundary-corrected-chunk-output-and-reuse.md)
- [boundary intent realization](../specifications/boundary-intent-realization.md)
- [boundary silence thresholds](../specifications/boundary-silence-thresholds.md)
- [buffered lead time and underrun policy](../specifications/buffered-lead-time-and-underrun-policy.md)
- [chunk planning](../specifications/chunk-planning.md)
- [document replacement playback reset and stale event rejection](../specifications/document-replacement-playback-reset-and-stale-event-rejection.md)
- [emphasis intent realization](../specifications/emphasis-intent-realization.md)
- [engine intent translation policy](../specifications/engine-intent-translation-policy.md)
- [file backed document restore and directory continuity](../specifications/file-backed-document-restore-and-directory-continuity.md)
- [first chunk startup contract](../specifications/first-chunk-startup-contract.md)
- [follower progress coalescing and drift resynchronization](../specifications/follower-progress-coalescing-and-drift-resynchronization.md)
- [generated audio cache](../specifications/generated-audio-cache.md)
- [imported playback responsiveness policy](../specifications/imported-playback-responsiveness-policy.md)
- [initial and resumed boundary handling](../specifications/initial-and-resumed-boundary-handling.md)
- [narration state](../specifications/narration-state.md)
- [playback coordination](../specifications/playback-coordination.md)
- [playback progress and jump mapping](../specifications/playback-progress-and-jump-mapping.md)
- [playback quality instrumentation](../specifications/playback-quality-instrumentation.md)
- [pronunciation realization precedence](../specifications/pronunciation-realization-precedence.md)
- [reading focus follow policy](../specifications/reading-focus-follow-policy.md)
- [realization window policy](../specifications/realization-window-policy.md)
- [remembered reading position and startup resume](../specifications/remembered-reading-position-and-startup-resume.md)
- [running app uninterrupted speech under follow along load](../specifications/running-app-uninterrupted-speech-under-follow-along-load.md)
- [speech worker pipeline](../specifications/speech-worker-pipeline.md)
- [spoken text selection and display mapping](../specifications/spoken-text-selection-and-display-mapping.md)
- [trim and cap join correction](../specifications/trim-and-cap-join-correction.md)
- [uninterrupted audio primary channel](../specifications/uninterrupted-audio-primary-channel.md)
- [voice session realization envelope](../specifications/voice-session-realization-envelope.md)
- [watched file session refresh](../specifications/watched-file-session-refresh.md)
