# Prepared Document and Buffered Playback

Date: October 24, 2026
Status: Required verification; not executed

## Paired Feature Specification

[Prepared Document and Buffered Playback](../specifications/prepared-document-and-buffered-playback.md)

## Supporting Contracts

- [Document Preparation and Execution Contexts](../acd/prepared-document-runtime.acd)
- [Character Cast Registry Model](../specifications/character-cast-registry-model.md)
- [Playback Coordination](../specifications/playback-coordination.md)
- [Speech Runtime Lifecycle and Ownership](../specifications/speech-runtime-lifecycle-and-ownership.md)
- [Speech Worker Pipeline](../specifications/speech-worker-pipeline.md)
- [Generated Audio Cache](../specifications/generated-audio-cache.md)

## Scenarios

| Scenario | Required evidence |
| --- | --- |
| Whole-document preparation | Display may be ready early, but speech is gated until every range has narration, attributed character or explicit unresolved ownership, plus completed delivery/pronunciation analysis |
| Normal A/B/A dialogue | Resident voice resources reused; ordered audio carries intended voices; no stop/seek/source rebuild at character changes; verify audible output as well as command trace |
| Startup and refill | Configured contiguous startup/low/high lead thresholds respected; a later ready chunk beyond a hole does not count as playable lead; short-document all-ready exception works |
| Slow renderer | Queue and memory remain bounded; measured lead decreases; explicit rebuffering preserves position if lead is exhausted; no silent transport restart loop |
| Assignment edit with full buffer | Old current chunk continues; pending binding becomes effective only at a safe boundary with prepared replacement lead; unaffected audio is preserved |
| Assignment edit during startup | Delayed generation for A followed by B then C results in only the latest accepted revision starting; stale success/failure cannot replace C |
| Source reload overlap | Two edits, then document replacement or live-mode cancellation; stale completion and finally cleanup cannot replace the document or clear new progress |
| UI responsiveness | Exercise input/scroll/menus during long import, analysis, planning and export; inspect frame timing and worker/native queues, not merely method declarations |
| Native lifetime | Hundreds of uncached chunks, repeated A/B/A routing, pause/resume and document replacement show bounded session/tensor counts and stable memory after warmup |
| Failure and shutdown | Unexpected worker exit, startup error and hung inference produce owned terminal results; drain/cancel semantics and resource cleanup are demonstrated |
| Cache identity | Same voice id with changed asset bytes or model digest misses old audio; unchanged fingerprints can reuse; incomplete publication is rejected |
| Artifact round trip | Character bindings, uncertainty, span-level delivery/pronunciation and source mappings survive instrumented-document serialization without native handles |

## Proof Boundaries

Deterministic tests should use controllable completion barriers rather than sleep-based timing. Run native integration tests for model/session lifetime and queue behavior. Running-app audio and responsiveness evidence is required before marking the visible feature complete. Record fixture revisions, engine/model/voice fingerprints, effective buffer policy and measured results with the run.
