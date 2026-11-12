# Playback Orchestration and Synthesis Boundaries

Reconciled: October 25, 2026; P4 source e18c81d (default runtime behavior through 843f6b5)
Status: Bounded P4 automated native cases accepted; active-export input, listening and integrated acceptance remain open

## Implemented structure and limitations

The controller captures an immutable planning context and asks a resident pure Dart planning worker for an initial three-chunk window. The worker retains the prepared document, cast routes, offsets and routing indexes once per context identity. Refill requests carry scalar epoch/sequence/cursor/window size, and the engine keeps only the current planning window. Realization covers every segment in the returned window. Main-isolate state changes require current document and binding intent; no native handles enter the graph.

Text-only `TtsSpeakRequest` compatibility retains its legacy token metadata preparation, then admits only a three-chunk startup prefix. Its remaining prepared metadata feeds a separate count/time-gated producer rather than synchronously filling the entire native pipeline before first audio. The engine owns both startup drivers and refill/tail futures; pause and stop invalidate identities, wake credit waiters, cancel pure workers and await producer drain. Shutdown cancels export and stops playback before closing runtime owners. The native probe separately checks a text-only request larger than pipeline capacity, position advancement and cancellation with no remaining producer.

Synthesis failure with an unprepared suffix cancels the active session, including continuation and admission waits, before resetting the player and reporting the failure. Cancelling only the synthesis generation leaves other producers waiting and can obstruct the next attempt's drain. Player reset releases queue ownership; it does not delete completed artifacts or retained incomplete MLX audio.

Separate playback/export tokenization supervisors retain initialized tokenizer, dictionary and capability state in pure Dart isolates. The main platform bridge reads raw asset strings; JSON decoding, dictionary growth, CMU conversion and fallback G2P initialization run in the worker. This avoids a pinned dependency's lazy root-bundle access inside a pure isolate. Cold-worker fidelity tests run before caller-side expected values can warm that dependency. Each owner has one active task and one latest pending task; superseded pending tasks terminate explicitly. Cancellation kills only pure workers, waits for exit, and rejects stale results. Translation and tokenization preserve explicit IPA, CMU backstop and suffix behavior; warm refills reuse worker state.

Playback uses contiguous source-order audio only. Startup requires at least two chunks totaling four seconds, eight seconds regardless of count, or all remaining audio for a short document. The five-second deadline fails startup explicitly; it never silently starts below target. Refill uses low four/high eight seconds with hysteresis, and a 64-chunk bound covering pending, staged and future native sources. Independent player speed divides PCM lead; synthesis rate is already reflected in emitted duration. A pathological startup needing more than 64 chunks to reach four seconds fails explicitly rather than waiting for impossible playback credit. This is a documented capacity limitation, not universal short-document acceptance.

Native playback appends later contiguous sources. Serialized history pruning removes completed predecessors while preserving the current source and native position, including after underrun seek recovery. Failed native playlist mutations have an owned terminal error and cleanup route; the serial drain remains usable for reset/replay. Initial `setAudioSources` remains the sole full source installation. Native traces must verify playlist/index behavior; source code alone cannot establish gapless output. Generated cache files have independent retention and are not bounded by this playlist policy. Playback pins are owned by generation and chunk, acquired on corrected-artifact acceptance and released from captured ownership snapshots only after native removal/clear acknowledgment. Late release cannot consume a newer generation's pin even when the content path is reused.

Playback and export lease one prioritized synthesis admission owner: one native operation, at most three pending requests, playback before export. Export admission waits until playback has at least the low-water lead or no active generation. Runtime completion acknowledgment retains each pipeline slot through boundary correction, preserving predecessor order with no extra correction queue. Native inference drain/quarantine from P2 remains mandatory. Resource replacement cancels and drains export from its initial ownership stage, before changing the resident document; supplied resource references must match resident identity. Rate changes stop the old generation before changing rate and restart playing or buffering through the controller. P4 captures assignment revision and expected resource identity before asynchronous planning/tokenization. User edits retain their previous effective snapshot until current acknowledgment. Active edits automatically stop/rebuffer from the current source chunk start; paused pending Play uses the saved chunk-start anchor unless newer navigation explicitly replaces it. Initial buffering supersedes older starts automatically. The serialized initial source-install slot rejects stale completion and owns cleanup before another install. Native seamless tail replacement is not claimed.

The native slot rechecks current effective playback lead before each admitted playback operation; enqueue-time credit alone cannot constrain an existing backlog. A synchronous completion hook reserves raw WAV duration before releasing the native permit. That conservative admission credit remains while boundary correction and playlist publication are pending, then the published corrected duration replaces it without double counting. The initial playlist counts during source installation before the playback token is active. This produced-audio budget is distinct from contiguous playable lead used to decide startup and safe export. High/low hysteresis gates actual playback inference, while resource-control operations and cancellation bypass the playback gate. Safe export work may use a slot while playback is gated. One operation already admitted can overshoot the high watermark by that chunk's duration; the high value is an admission threshold rather than a hard sample truncation boundary.

Kokoro constructs its native player with eager source preparation because the application already bounds the playlist. A pinned-backend native trace exposed duplicate `AVPlayerItem` insertion from lazy queue rebuilding during prefix removal. Eager preparation removes that lazy treadmill path; acceptance still requires the current running-bundle queue and audio evidence recorded in P3. Injected players used by probes must use the same preparation setting.

The vendored just_audio 0.10.5 Darwin adapter preserves pointer-identical buffered
queue prefixes during sequential append and pruning. It computes the desired
queue with upstream order and per-source lazy preparation rules, then appends only
missing items. Loading, seeking, looping, replacement and non-prefix changes retain
the upstream rebuild. This removes repeated successor removal that coincided with
short pauses inside current speech. No new scheduling owner is introduced; native
callbacks, cancellation and disposal remain upstream-owned. See the [patch rationale
and native regression checks](../../third_party/just_audio/README.local.md); running-app
acoustic and transport qualification remains recorded in S6 [#137](https://github.com/kellyjanderson/readaloud/issues/137).

Lease cancellation removes queued native admission even when the export lead gate is closed; already active native calls drain before their cancelled terminal. Pause signals admission after generation state settles. Natural document completion defers release while an export lease is active, then releases only if its resource and playback epochs remain current; pause, a replacement document and replay cannot inherit that release debt. The controller normalizes Kokoro intent into the supported 0.7–1.4 range before planning, and direct incompatible prepared plans are rejected. Cache plan identity, export and inference therefore use the same effective rate; independent player speed affects only playable wall-time lead.

When synthesis fails with an unplanned suffix, the engine terminates that session with an error rather than rebuilding only admitted chunks and silently truncating the document. Existing bounded fallback recovery remains available only after the entire suffix has been materialized. Policy constants and transport traces are not perceptual continuity guarantees; measured evidence and limitations are recorded in [P3](https://github.com/kellyjanderson/readaloud/issues/52).

Ordinary no-edit Play rebuilds the saved-word tail: the controller captures the current word offset and calls `engine.speak`, which stops the prior generation. This differs from applying pending choices at the retained chunk-start anchor. Native supplemental evidence retained word 293 while replacing the source/resetting player position. The [baseline source comparison](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396190387) found the same word-tail/stop behavior at `694e1c3`; this is not sample-continuous resume proof or a new native baseline comparison.

The [assignment295 prefix](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395976458) observed unchanged current source/hash after editing, first replacement playback at word 8 before acknowledgment, latest-only initial A/B/C success and pause-retained/stop-cleared pins. Its later listening timeout failed the overall run, with final resource cleanup recorded separately. The [e18c81d supplement](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396165816) passed paused pending Play at anchor 292, injected pre-ack failure retaining effective Heart and pending Bella followed by successful retry, and obsolete startup failure leaving latest C effective. Held-export cancellation drained before replacement playback; final sessions/tensors/sources/pins/tasks were zero. These bounded automated cases do not establish human listening, sample continuity or input during active export; the latter had zero actual UI actions.

## Packet traversal and native pruning

Incremental Drama playback gives each immutable packet a native queue identity
while retaining its complete scene's source identity. Its 300 ms startup lead is
separate from the complete-chunk policies above; steady-state admission remains
time/count bounded. See [runtime messaging](speech-runtime-messaging-boundary.md)
and [artifact ownership](audio-artifact-identity-and-lifetime.md).

The pinned Darwin player reindexes prefix removal against the actual surviving
`AVQueuePlayer.currentItem`. Its fallback counts removals against one immutable
old index when that current item itself was removed. Comparing removals against
a repeatedly decremented index skipped a remaining item when several predecessors
were pruned together. The native recording-queue regression covers batch removal,
advancement during mutation, removed-current, shuffle, seek, load and loop paths.
Append and removal explicitly request preservation of surviving playback. Their
fast path derives both its head and future-prefix comparison from one native
queue snapshot, then appends only the missing suffix. Natural advancement can
remove a prefix of that snapshot without forcing a rebuild. Separate live reads
previously raced and fell through to destructive queue reconstruction. Explicit
seek, load, loop and incompatible reorder paths retain their existing behavior.
The application retains one completed predecessor until a following source
completes: the backend can report the next logical index before the native queue
head has advanced. Immediate removal could therefore remove the native head and
interrupt its transition. This one-source ownership fence is separate from the
future-audio admission cap and playable lead. Retained pins release only after
native removal acknowledgment; stop/reset drains the remaining queue ownership.
This test does not prove actual emitted endings or continuity; current signed-app
captures remain required. iOS shares the source but is not qualified here.

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

## Finite local speech queue ownership on macOS

The internally owned `KokoroTtsEngine` player opts into the vendored player's
immutable `readAloudFiniteLocalWavQueue` contract on macOS. Injected players keep
their caller's choice; generic players and other platforms keep legacy behavior.
The existing player-init request carries the choice before loading. Application
artifact validation owns finite WAV provenance. Dart shape/URI preflight runs
before logical playlist mutation; native admission independently checks plain
local AVURLAsset identity and queue/source membership before changing its tree.
Neither layer guesses media format from a suffix or reads contents on the UI
thread. Unsupported sources are rejected; no new playback scheduler is added.

For opted-in loop-off playback, the actual native current item owns the logical
index. A future item's end notification cannot advance its predecessor. Final
completion separately requires positive finite duration and exact numeric EOF;
one weak final-item witness is rechecked by existing head/Pause callbacks. This
also covers a notification just before the head's final sample. Seek, accepted
load, loop-mode change and disposal clear the witness. Both loop modes retain
upstream completion behavior. Full details, library rationale and native fixture
limits are in the [local adaptation](../../third_party/just_audio/README.local.md).

For that macOS finite-queue loop-off path, Play samples the existing real
paused or pending-seek position before activating the native rate. This avoids
the direct post-activation AVPlayerItem.currentTime query found in the matched
native trace. Position and timestamp remain paired; no synthetic position,
extra scheduler or GPU policy is introduced. Generic players, other platforms
and both loop modes retain the prior ordering. Existing status/KVO callbacks
can still read position, so this is not a universal AVFoundation latency claim.
The [position verification](../test-artifacts/s7-play-position-20261111/README.md)
retains real-reader native negative controls and exact-candidate running-app
results, including their snapshot and capture limits.

The environment-driven physical-head experiment remains a separate diagnostic
override. Earlier flagged acoustic passes do not qualify this production opt-in.
[S7](https://github.com/kellyjanderson/readaloud/issues/112) owns final-source
emitted-audio, responsiveness and cancellation evidence; M3 and human listening
remain separate gates. The dated natural-EOF and replay diagnostics preserve
both passing component observations and capture failures.

The production-policy v77/v78 book checks cover 197 words and all six
complete saved scene waveforms, with maximum external joins of .01ms. First-load
playback reached natural EOF, persisted the complete book and peaked at 30ms
native response; its model-forbidden reopen, Save/reopen, cancellation and
restart peaked at 66ms, with every native sample foreground in both runs. These
bounded checks verify the opted-in production queue without its experimental
override. First-load post-startup speech took 2099.705ms; reusable loading took
525.851ms. Total launch took 6317.906ms and 801.514ms respectively: the first
misses the 2s goal even though both load hard limits pass. See the
[position verification](../test-artifacts/s7-play-position-20261111/README.md).
Its earlier, mostly background v76 case retains colder startup and all waveform
matches, but receives no foreground responsiveness credit. Installed assets and
OS caches remain distinct from fresh private target raw-audio stores. Earlier
274ms/349ms failures remain preserved in the
[preceding controls](../test-artifacts/s7-final-native-20261111/README.md).
The exact-candidate 4bit/8bit/A-B-A checks pass the unchanged 250ms gate; a separate
180s run passes waveform and native components while retaining its diagnostic
overall verdict. None establishes a universal AVFoundation cure, arbitrary-book
performance, physical output, human listening or M3 qualification.
