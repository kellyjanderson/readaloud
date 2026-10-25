# Playback Orchestration and Synthesis Boundaries

Reconciled: October 25, 2026; P4 source e18c81d (default runtime behavior through 843f6b5)
Status: Bounded P4 automated native cases accepted; active-export input, listening and integrated acceptance remain open

## Implemented structure and limitations

The controller captures an immutable planning context and asks a resident pure Dart planning worker for an initial three-chunk window. The worker retains the prepared document, cast routes, offsets and routing indexes once per context identity. Refill requests carry scalar epoch/sequence/cursor/window size, and the engine keeps only the current planning window. Realization covers every segment in the returned window. Main-isolate state changes require current document and binding intent; no native handles enter the graph.

Text-only `TtsSpeakRequest` compatibility retains its legacy token metadata preparation, then admits only a three-chunk startup prefix. Its remaining prepared metadata feeds a separate count/time-gated producer rather than synchronously filling the entire native pipeline before first audio. The engine owns both startup drivers and refill/tail futures; pause and stop invalidate identities, wake credit waiters, cancel pure workers and await producer drain. Shutdown cancels export and stops playback before closing runtime owners. The native probe separately checks a text-only request larger than pipeline capacity, position advancement and cancellation with no remaining producer.

Separate playback/export tokenization supervisors retain initialized tokenizer, dictionary and capability state in pure Dart isolates. The main platform bridge reads raw asset strings; JSON decoding, dictionary growth, CMU conversion and fallback G2P initialization run in the worker. This avoids a pinned dependency's lazy root-bundle access inside a pure isolate. Cold-worker fidelity tests run before caller-side expected values can warm that dependency. Each owner has one active task and one latest pending task; superseded pending tasks terminate explicitly. Cancellation kills only pure workers, waits for exit, and rejects stale results. Translation and tokenization preserve explicit IPA, CMU backstop and suffix behavior; warm refills reuse worker state.

Playback uses contiguous source-order audio only. Startup requires at least two chunks totaling four seconds, eight seconds regardless of count, or all remaining audio for a short document. The five-second deadline fails startup explicitly; it never silently starts below target. Refill uses low four/high eight seconds with hysteresis, and a 64-chunk bound covering pending, staged and future native sources. Independent player speed divides PCM lead; synthesis rate is already reflected in emitted duration. A pathological startup needing more than 64 chunks to reach four seconds fails explicitly rather than waiting for impossible playback credit. This is a documented capacity limitation, not universal short-document acceptance.

Native playback appends later contiguous sources. Serialized history pruning removes completed predecessors while preserving the current source and native position, including after underrun seek recovery. Failed native playlist mutations have an owned terminal error and cleanup route; the serial drain remains usable for reset/replay. Initial `setAudioSources` remains the sole full source installation. Native traces must verify playlist/index behavior; source code alone cannot establish gapless output. Generated cache files have independent retention and are not bounded by this playlist policy. Playback pins are owned by generation and chunk, acquired on corrected-artifact acceptance and released from captured ownership snapshots only after native removal/clear acknowledgment. Late release cannot consume a newer generation's pin even when the content path is reused.

Playback and export lease one prioritized synthesis admission owner: one native operation, at most three pending requests, playback before export. Export admission waits until playback has at least the low-water lead or no active generation. Runtime completion acknowledgment retains each pipeline slot through boundary correction, preserving predecessor order with no extra correction queue. Native inference drain/quarantine from P2 remains mandatory. Resource replacement cancels and drains export from its initial ownership stage, before changing the resident document; supplied resource references must match resident identity. Rate changes stop the old generation before changing rate and restart playing or buffering through the controller. P4 captures assignment revision and expected resource identity before asynchronous planning/tokenization. User edits during active playback remain pending, retaining transport-effective context. Explicit Apply stops/rebuffers from the current source chunk start; paused pending Play uses the saved chunk-start anchor unless newer navigation explicitly replaces it. Initial buffering supersedes older starts automatically. The serialized initial source-install slot rejects stale completion and owns cleanup before another install. Native seamless tail replacement is not claimed.

The native slot rechecks current effective playback lead before each admitted playback operation; enqueue-time credit alone cannot constrain an existing backlog. A synchronous completion hook reserves raw WAV duration before releasing the native permit. That conservative admission credit remains while boundary correction and playlist publication are pending, then the published corrected duration replaces it without double counting. The initial playlist counts during source installation before the playback token is active. This produced-audio budget is distinct from contiguous playable lead used to decide startup and safe export. High/low hysteresis gates actual playback inference, while resource-control operations and cancellation bypass the playback gate. Safe export work may use a slot while playback is gated. One operation already admitted can overshoot the high watermark by that chunk's duration; the high value is an admission threshold rather than a hard sample truncation boundary.

Kokoro constructs its native player with eager source preparation because the application already bounds the playlist. A pinned-backend native trace exposed duplicate `AVPlayerItem` insertion from lazy queue rebuilding during prefix removal. Eager preparation removes that lazy treadmill path; acceptance still requires the current running-bundle queue and audio evidence recorded in P3. Injected players used by probes must use the same preparation setting.

Lease cancellation removes queued native admission even when the export lead gate is closed; already active native calls drain before their cancelled terminal. Pause signals admission after generation state settles. Natural document completion defers release while an export lease is active, then releases only if its resource and playback epochs remain current; pause, a replacement document and replay cannot inherit that release debt. The controller normalizes Kokoro intent into the supported 0.7–1.4 range before planning, and direct incompatible prepared plans are rejected. Cache plan identity, export and inference therefore use the same effective rate; independent player speed affects only playable wall-time lead.

When synthesis fails with an unplanned suffix, the engine terminates that session with an error rather than rebuilding only admitted chunks and silently truncating the document. Existing bounded fallback recovery remains available only after the entire suffix has been materialized. Policy constants and transport traces are not perceptual continuity guarantees; measured evidence and limitations are recorded in [P3](https://github.com/kellyjanderson/readaloud/issues/52).

Ordinary no-edit Play rebuilds the saved-word tail: the controller captures the current word offset and calls `engine.speak`, which stops the prior generation. This differs from applying pending choices at the retained chunk-start anchor. Native supplemental evidence retained word 293 while replacing the source/resetting player position. The [baseline source comparison](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396190387) found the same word-tail/stop behavior at `694e1c3`; this is not sample-continuous resume proof or a new native baseline comparison.

The [assignment295 prefix](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395976458) observed unchanged current source/hash after editing, first replacement playback at word 8 before acknowledgment, latest-only initial A/B/C success and pause-retained/stop-cleared pins. Its later listening timeout failed the overall run, with final resource cleanup recorded separately. The [e18c81d supplement](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396165816) passed paused pending Play at anchor 292, injected pre-ack failure retaining effective Heart and pending Bella followed by successful retry, and obsolete startup failure leaving latest C effective. Held-export cancellation drained before replacement playback; final sessions/tensors/sources/pins/tasks were zero. These bounded automated cases do not establish human listening, sample continuity or input during active export; the latter had zero actual UI actions.

## Source and tests

- [kokoro_tts_engine.dart](../../lib/src/services/kokoro_tts_engine.dart)
- [kokoro_playback_coordination.dart](../../lib/src/services/kokoro_playback_coordination.dart)
- [synthesis_boundary_policy.dart](../../lib/src/services/synthesis_boundary_policy.dart)
- [speech_runtime.dart](../../lib/src/services/speech_runtime.dart)
- [kokoro_playback_coordination_test.dart](../../test/kokoro_playback_coordination_test.dart)
- [synthesis_boundary_policy_test.dart](../../test/synthesis_boundary_policy_test.dart)
- [reader_controller_playback_test.dart](../../test/reader_controller_playback_test.dart)

P3 also adds admission, resident-planning, tokenizer and export-revision regressions. Use the pinned native arm64 SDK in development guidance. Source tests, native queue observations and acoustic evidence remain distinct acceptance layers.

## Design and remaining acceptance

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
