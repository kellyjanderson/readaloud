## ACD-R1 — Bounded reading and single-owner runtime lifecycle

> Fixed published R1 snapshot, captured November 4, 2026 Pacific.
> [Source design/plan](https://github.com/kellyjanderson/readaloud/issues/113#acd-r1--bounded-reading-and-single-owner-runtime-lifecycle) · [package provenance](README.md) · [lifecycle](../README.md).
> GitHub owns current execution state; this snapshot is not an implementation or acceptance claim.

Design revision R1, November 4, 2026 Pacific; base `1f605cfa74bc4374ffc278cb9ccb67218efe6cc4`. Basis: ownership/proof sections above and #114 C02/C08. Proposed delta under [plan R10](https://github.com/kellyjanderson/readaloud/issues/110#implementation-plan-r10); existing child disposal, generation checks and admission are retained.

### Architectural delta
Replace `ReaderController`'s MLX `maxChunks: 1000000` planning path with a bounded demand window. Start with the existing three-chunk planning batch, request the next batch as validated audio lead falls below the configured target, and retain both a chunk-count cap and an audio-duration/byte cap. Provider-specific token limits further restrict each chunk/scene. Measure and tune these explicit limits; do not make them proportional to book length. Separate display demand, semantic read-ahead and waveform lead so large-document display never drains the entire book into synthesis.

Use one neutral engine-session owner around the existing player/runtime and provider processor. Avoid eager default-engine construction before preferences are known; preserve injected test engines. A model session may outlive a document, while its document/assignment binding snapshots cannot. Renaming `KokoroTtsEngine` alone is not the fix; extraction must remove backend branches while preserving just_audio, shared admission, artifacts and export.

### Concurrency contract
| Producer/state | Owner and context | Bound and identity | Cancel, failure and shutdown |
| --- | --- | --- | --- |
| Input/preparation | Existing supervisor + worker | Eight publication credits; work/source/analysis revision | Invalidate on replacement; stale result/error/checkpoint rejected; close worker/ports |
| Scene planning | Existing planner worker | One active plus latest replaceable demand; three-chunk initial batch | Planning epoch + assignment revision; cancel unneeded future work; no stale error overwrites |
| Playback/export inference | Existing admission owner and pipeline | Preserve three pending admissions and eight pipeline pending plus one active; queue nesting is not permission to preload all batches | Lease/session/generation; playback priority; cancelled exports cannot publish or delete successor artifacts |
| MLX load/inference | One child owned by processor/session | One active command; request ID + child generation + exact model identity | Out-of-band terminate/reap on uncooperative cancel; late stdout/stderr/exit ignored by successor |
| Model selection | Main-isolate session owner | One active transition + replaceable desired selection | ACD-M1 state machine; Quit wins |
| Validation/artifact assembly | Existing I/O/CPU workers | Bounded admitted operation; request-scoped temporary paths | Publish atomically only for valid lease; stale cleanup touches only owned paths |
| UI/player | Flutter main isolate / native player | Bounded lead; epoch-checked callbacks | UI cancel returns promptly, before background drain; no obsolete autoplay |

Logical cancellation, cooperative stop, process exit and native memory release are separate states. Use existing process/isolate/platform facilities; reject a generic pool/event bus as a substitute for ownership. Operation deadlines are stage-specific: silent/stalled work surfaces a recoverable state, not invented progress. Termination timeout escalates through supported process termination, verifies exit and reports a blocker if reaping fails; never launch an overlapping large replacement to mask an orphan.

### Migration and code ownership
Change controller demand/continuation, `speech_planning_supervisor.dart`, `speech_runtime.dart`, `speech_worker_pipeline.dart`, `synthesis_admission_owner.dart`, MLX processor and the neutral extraction from `kokoro_tts_engine.dart`. Carry immutable typed identities across every boundary. Preserve #120 audio retention, first-Play recovery and empty final events. Land demand repair before optional lifecycle helper consolidation; C08 remains conditional, not a new framework prerequisite. No persisted document schema change is required here.

### Proof and reconciliation
Exercise cancellation during spawn/load/inference, late success/failure/exit, slow child termination, repeated shutdown, simultaneous playback/export/preview, document replacement and seek. Record maximum queues/retained ranges/audio bytes against increasing book sizes. In the real app measure launch-to-first-audible-output from app opening, input response, underruns and process-tree release. The two-second product requirement remains unchanged; inability to meet it is a reported acceptance gap, not a shifted timer. Qualified long reading and native child exit are required beyond unit tests.

Reconcile playback, runtime messaging, document pipeline and artifact-lifetime architecture. Depends on the current baseline and captured short Drama comparison; fixes blocking that comparison may land first. Roll back individual extraction commits, not previously preserved lifecycle/audio fixes.

### Source and reconciliation anchors

Pinned existing owners, not implementation of this ACD. Additional exact locations and test matrices remain in the linked review findings.

- [lib/src/services/speech_runtime.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/services/speech_runtime.dart)
- [lib/src/services/speech_worker_pipeline.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/services/speech_worker_pipeline.dart)
- [lib/src/services/synthesis_admission_owner.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/services/synthesis_admission_owner.dart)
- [project/architecture/playback-orchestration-and-synthesis-boundaries.md](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/project/architecture/playback-orchestration-and-synthesis-boundaries.md)
