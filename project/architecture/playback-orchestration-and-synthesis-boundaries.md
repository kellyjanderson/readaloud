# Playback Orchestration and Synthesis Boundaries

Reconciled: October 24, 2026
Status: Current source architecture; runtime validation not refreshed

## Implemented structure and limitations

Kokoro playback builds a routed chunk plan, requests generation, stages ready chunks and primes the player with an initial queue. Startup already has warmup: target lead is eight seconds; low/critical thresholds are four/two seconds; startup also accepts at least two chunks totaling four seconds, or no remaining work. Warmup has a five-second timeout that can permit earlier start. These are code constants, not measured continuity guarantees.

Later chunks append to the active source queue. Current underrun recovery seeks to the next buffered queue index and resumes; it does not rebuild the entire source list in that recovery method. The sole `setAudioSources` call is initial queue setup. Earlier architecture claims about routine rebuilding were stale.

Boundary policy trims/caps silence and treats initial/resumed chunks specially. Its async wrapper invokes synchronous correction, so the call boundary is not proof of CPU offload. Finalized audio and metadata are cached; sidecars validate logical keys, not model/voice byte digests. Model setup accepts a nonempty existing file. Cache retention is independent of pausing.

User voice selection currently restarts when playing, but does not handle initial buffering identically. Safe future assignment revision commits, persistent voice contexts and strict contiguous bounded lead guarantees remain ACD work. Ordinary routed character transitions are not user setVoice events.

## Source and tests

- [kokoro_tts_engine.dart](../../lib/src/services/kokoro_tts_engine.dart)
- [kokoro_playback_coordination.dart](../../lib/src/services/kokoro_playback_coordination.dart)
- [synthesis_boundary_policy.dart](../../lib/src/services/synthesis_boundary_policy.dart)
- [speech_runtime.dart](../../lib/src/services/speech_runtime.dart)
- [kokoro_playback_coordination_test.dart](../../test/kokoro_playback_coordination_test.dart)
- [synthesis_boundary_policy_test.dart](../../test/synthesis_boundary_policy_test.dart)
- [reader_controller_playback_test.dart](../../test/reader_controller_playback_test.dart)

Tests listed here are existing evidence locations, not a claim that they passed in this review. The bundled Intel Dart executable cannot run in the current Apple Silicon execution environment.

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
