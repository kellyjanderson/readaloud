<!-- Historical snapshot; not current authority. -->

# Document Preparation and Execution Contexts

Last updated: October 24, 2026
Status: Accepted target architecture; implementation and runtime verification pending

## Contract

The whole document is analyzed before speech playback is eligible. Preparation produces an instrumented document with stable characters, resolved voice bindings, speaker-tagged dialogue, narration ranges, delivery and inflection intent, pronunciation artifacts, and source mappings. Unknown attribution remains explicit; readiness does not require pretending every ambiguity is solved.

The reading surface may become viewable before preparation completes. Display readiness, document preparation readiness, and audio readiness are separate states. A visible document must not imply that its speech preparation is complete.

Whole-document analysis does not require whole-document waveform generation before playback. Audio is rendered substantially ahead of the playhead into a bounded buffer. Playback consumes finalized audio; it does not infer speakers or wait for voice setup at an ordinary character boundary.

This contract refines the existing document-time/voice-time split. Document semantics are prepared globally; engine-specific realization and audio generation may remain windowed, provided they stay ahead of playback and never reinterpret speaker identity or pronunciation policy on the playhead.

## Instrumented Document

An immutable prepared revision contains:

- document identity, source fingerprint, normalization and analysis versions;
- stable narrator and character ids, names, aliases, descriptions and evidence;
- optional text-supported presented-gender information, separately retained pronouns, uncertainty and conflicting evidence; absence of sufficient evidence remains unknown;
- character-owned voice bindings, including automatic choice, user override, effective choice and binding revision;
- ordered speech spans referencing a character id or explicit unresolved fallback, with evidence and attribution provenance;
- span-level pronunciation, pause, emphasis, inflection and delivery intent, plus source/display mappings;
- analysis diagnostics and completion state.

Character defaults and passage-specific delivery are distinct. A whispered line does not change the character's persistent voice identity. Canonical intent is preserved even when the selected engine cannot express it; capability fallback must be recorded rather than silently claiming delivery support.

No neural provider is selected by this contract. Heuristic and neural providers must produce the same inspectable artifact. Whole-document processing supplies context but does not by itself guarantee correct attribution; provider evaluation remains necessary.

## Character Voice Binding and Runtime Lifetime

Each character construct owns or references a typed voice binding with voice id, voice-asset digest, model-manifest reference/digest, engine compatibility, pronunciation-profile identity and binding revision. Assignment provenance and overrides remain distinguishable from character identity evidence. Shared manifests are referenced, not duplicated for every character.

The document runtime resolves and validates all required bindings during preparation and loads the required voice vectors before playback. Voice resources remain resident through ordinary character changes, pause/resume, and jumps within the document. End-of-document/replacement/shutdown releases them after in-flight work drains; replay reestablishes the context before audio resumes.

One shared engine/model session can serve many character voices. The synthesis worker selects the prepared character voice vector and span delivery context for each chunk. It must not recreate a model session or reload a voice file at every character boundary. Native handles belong to the runtime, never to serialized character records or UI state. Per-inference tensors have bounded lifetimes and are released on success and failure.

The character binding is the source of voice/model identity for cache derivation. Cache files, atomic writes, retention, disk budgets and cleanup are runtime/cache-service responsibilities, not methods on character entities. A model or voice replacement changes the binding fingerprint; old audio must not match the new identity.

## Audio Lead and Playback

The scheduler measures contiguous finalized playable seconds ahead of the playhead, accounting for effective playback speed. Completed audio beyond a missing chunk does not count toward contiguous lead. A configurable startup target, refill low watermark, and high watermark define buffer policy, with low < high and startup <= high. Values must be selected from measured synthesis latency, throughput and memory on supported hardware; no universal numeric guarantee is asserted here.

Playback starts after document readiness and startup audio lead are satisfied, or after all remaining audio is prepared for a short document. Refill begins before lead reaches the low watermark and pauses at the high watermark. The queue and in-flight work are bounded. Export or speculative work cannot starve active playback refill.

Normal narrator/character transitions keep the same playback session and append finalized chunks in source order. Arrival of rendered audio does not stop, seek or rebuild the active player. Later completed chunks wait for missing predecessors.

If sustained rendering is slower than consumption, any finite buffer eventually empties. The runtime reports the shortfall, preserves correct position and uses explicit rebuffering when necessary; it must not hide failure through repeated transport restarts. Metrics include playable lead, minimum lead, real-time factor, refill latency, underruns, resident resources and first-audio latency.

## Assignment Edits and Source Changes

An automatic change of speaker is a prepared route change, not a user `setVoice` action. A user changing a character's assignment after audio is rendered invalidates affected future audio even when the buffer is full.

During playback, an assignment edit prepares a new binding revision and replacement audio off-thread. The coordinator commits it at a future safe chunk boundary only when the replacement contiguous lead is ready. Existing valid audio continues until that boundary; the UI distinguishes pending from effective assignment. Preserve the current chunk, discard only superseded future routes, and reject stale replacement results. A backend unable to replace a future queue tail safely must expose deferred application or an explicit rebuffering action; it must not restart on every normal speaker change.

During initial buffering, only the latest requested binding revision may start playback. Before document readiness, edits are incorporated into the prepared revision. Immediate restart is a separate user transport intent, not the default meaning of an assignment change. Source edits require a new prepared document revision before their audio can replace the active revision.

## Execution Context Inventory

These are ownership lanes, not a requirement for one OS thread per row. Workers may share infrastructure only if priority and backpressure preserve the audio deadline. An `async` method or `Future.delayed(Duration.zero)` does not offload CPU work.

| Lane and owner | Work and placement | Queue and handoff |
| --- | --- | --- |
| UI/controller | Widget state, user intent, bounded view updates, accepting prepared revisions; main Flutter isolate | Typed requests out; accept matching revision results only; coalesce progress |
| Document preparation supervisor | Decode/decompress, parse, normalize, map positions, analyze characters/dialogue/delivery, pronunciation planning, serialization; background isolate/process | One active revision plus coalesced latest replacement; progress, ready, failure/cancel events |
| Document voice context | Validate manifests and load voice assets; synthesis runtime worker/native resource owner | Prepare all document bindings before readiness; reuse resources for document lifetime |
| Realization and planning | Voice-specific pronunciation adaptation, chunk planning, route derivation, buffer scheduling; speech runtime worker | Bounded contiguous lookahead; high priority for refill; never controller callbacks |
| Inference | Model session and tensors; long-lived worker plus native serial background queue | One inference owner initially; native callbacks return through typed handoff; no main-thread inference |
| Audio transport | Append/commit finalized queue entries, player commands and native audio callbacks; platform-required player context | Short control operations only; no analysis, file decoding or inference in audio callbacks |
| Storage and export | Hashing, WAV assembly, cache writes/validation, artifact export; background I/O/CPU lane | Atomic publish; bounded lower priority export; pins protect queued audio from cleanup |
| Watcher and preferences | Coalesce file events; serialized durable snapshots; background I/O with platform-required calls bridged | Latest-revision reload; stale saves cannot overwrite newer preferences |
| Diagnostics and UI followers | Aggregate metrics, batch trace writes off-thread; bounded highlight/layout updates on UI | Drop/coalesce obsolete visual progress; diagnostics cannot block audio |

Platform APIs that require main-thread access remain behind small bridges: obtain file access or assets there if necessary, then transfer paths or immutable data. Never move heavy work back to the UI merely because a plugin requires a platform channel. Native handlers need their own background queue policy. Large display preparation belongs off-thread; framework layout stays on the UI/render lane and must use bounded visible content.

## Concurrency Contract for Every Producer

Each architecture/specification change that introduces work must state its owner, execution context, bounded queue policy, cancellation/timeout, shutdown, failure route and proof scenario. Missing declarations are an architectural gap, not an implementation detail to leave to the agent.

Commands/events carry operation kind, owner/request id, document revision and, where applicable, binding revision, playback session, generation and chunk identity. Receivers validate identity before accepting success, failure, cancellation or cleanup. Old completion/finally callbacks cannot clear newer loading state. Payloads are immutable DTOs, file references or transferable data, not controllers, closures or native handles.

Cancellation removes queued work and suppresses stale results. In-flight native work is drained or cancelled according to documented adapter capability; killing a Dart isolate does not establish native resource cleanup. Supervisors handle unexpected worker exit, timeout and malformed results and emit a terminal outcome. Shutdown stops intake, invalidates outstanding requests, drains/cancels work, releases tensors then sessions/voices, and completes before disposal is reported.

## Review Findings and Acceptance

The October 24 source review found that existing documents already prescribe a long-lived speech worker, but do not consistently locate all document preparation and planning work. Some startup and voice-change rules contradict the intended prepared-buffer model. The following remain implementation gaps, not completed features:

- `DocumentImportService._buildReaderDocument` performs full analysis synchronously on its caller; `_setDocumentLoadStage` only yields briefly.
- `ReaderController._refreshRealizationWindow` and `_refreshChunkPlan` perform realization/planning synchronously in controller paths.
- `KokoroSpeechWorkerChunkProcessor.process` creates an isolate per chunk; the worker creates a model session and loads a voice per uncached chunk.
- `KokoroModelRunner` skips macOS session closure and does not dispose inference tensors; native dictionaries retain those objects.
- `selectVoiceById` tests playing but not initial buffering; watched-file reload lacks revision-guarded publication.

Acceptance requires integrated tests for full-document readiness, no inference during playback routing, resident voice reuse, A/B/A character boundaries without transport restart, contiguous buffer thresholds and short documents, assignment edits with a full buffer and during startup, stale import success/failure, UI input during long preparation/export, worker failure/timeout, and bounded native resources over long sessions. Audio continuity and responsiveness require running-app evidence in addition to unit tests.

See [implementation alignment plan](../../../planning/archive/document-preparation-runtime-alignment.md) for the code locations and verification work.
