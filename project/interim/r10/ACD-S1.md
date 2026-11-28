## ACD-S1 — Portable speech scenes with native Fish realization

> Fixed published R1 snapshot, captured November 4, 2026 Pacific.
> [Source design/plan](https://github.com/kellyjanderson/readaloud/issues/111#acd-s1--portable-speech-scenes-with-native-fish-realization) · [package provenance](README.md) · [lifecycle](../README.md).
> GitHub owns current execution state; this snapshot is not an implementation or acceptance claim.

Design revision R1, November 4, 2026 Pacific; base `1f605cfa74bc4374ffc278cb9ccb67218efe6cc4`. Basis: this issue's minimum change/fiction acceptance, [#124 V1/P1](https://github.com/kellyjanderson/readaloud/issues/124#p1--fish-concepts-worth-promoting-into-shared-read-aloud-structures), #120's exact-model adjustment guards and #114 C01/C02/C07. Proposed architecture under [plan R10](https://github.com/kellyjanderson/readaloud/issues/110#implementation-plan-r10).

### Decision and preserved implementation
One persistent casting authority, one bounded speech runtime and one player serve every engine. Fish receives native ordered multi-reference scenes when supported; Kokoro and other engines lower the same turns to their supported request form. Retain existing complete generator consumption, empty final-marker handling, native sample rates, audio retention, artifact identity, admission and export. First qualify the current single-voice Drama path before requiring this generalization.

### Request, capability and output contracts
Extend `CastAwareSpeechRoute`, `ChunkPlan` and `TtsSpeakRequest` with an immutable scene view: `{sceneId, workId, sourceRevision, assignmentRevision, engineEpoch, turns[], contextDescriptor}`. A turn carries stable character ID, source spans, canonical text, prepared voice binding reference and canonical direction references. Scene length is bounded by the planning budget and the provider's supported byte/token/speaker limits, not a chapter or whole document. A provider limit splits scenes at structural boundaries; it never drops a character or coerces every backend to Fish's current limits.

Extend `EngineCapabilityProfile`/catalog with typed support for reference form/count, scene mode, continuation context, incremental output, native audio formats, alignment quality and delivery/rate controls. Capabilities are qualified for an exact model/runtime revision. Preserve `SpeechAdjustmentContext`/registry scoping: canonical content and annotations remain unchanged, while each adapter reports supported/approximated/unsupported/deferred realization. Kokoro-specific pronunciation recipes cannot leak into Fish/Qwen input.

Extend `PreparedVoiceBinding` identities with reference audio/transcript digest, model/codec/runtime/precision identity and conditioning policy version. The speech worker owns actual reference encodings, prompt-prefix/KV resources and bounded caches; Dart receives identities and metrics, never native handles. A resident reference-set key uses ordered voice identities plus prompt policy. Automatic character changes select prepared bindings and do not initiate model replacement. Explicit edits create a new assignment revision and invalidate only uncommitted future speech; preserve the existing disclosed Apply/replay behavior until seamless replacement is proven.

Emit ordered pieces `{requestId, epoch, pieceIndex, sourceSpan, audioArtifact, format, alignmentKind, final}`. A final event may carry no PCM. Duplicate/out-of-order/late pieces cannot be admitted twice. A scene with no native turn alignment reports scene-level alignment; do not fabricate word timestamps. If exact turn mapping is required for highlighting/seek, lower to per-turn requests until measured alignment supports the richer mode. Preserve native 44.1 kHz; format conversion occurs only for a documented destination requirement.

Continuation context has a versioned identity and a bounded provider-owned state. Seek, source/assignment revision and model replacement invalidate incompatible history. Cache identities include actual conditioning/context digest and synthesis settings; identical text with different history must not reuse incompatible audio. Track model, prepared-reference, prefix/history and queued-audio residency separately where measurable.

### Ownership, migration and library boundary
Existing planning supervisor owns scenes; `speech_worker_pipeline.dart` and admission owner enforce ACD-R1 bounds; Python MLX worker owns model-specific lowering and resources. Backpressure pauses production when admitted audio is sufficient. Cancellation invalidates both success and failure publication and follows the child lifecycle contract. Fish tags/tokenization, speaker slots, prompt layout, sampling and native cache internals remain adapter-specific. Reuse mlx-audio and just_audio; no new voice manager or player.

Migrate per-turn requests through a compatibility adapter first. Implement Fish end to end, then demonstrate Kokoro or Qwen Base using the same scene/binding/output contract. Existing saved engine IDs and voice intent remain readable. Default to the proven per-turn route when a capability is unqualified; disclose loss of scene realization rather than claiming equivalent expressiveness.

### Acceptance and reconciliation
Short private City narrator/A/B/A scenes and ending; >=5 installed, previewable, distinct usable choices per character; repeated voice identity; no spoken tags, missing/repeated pieces or artificial gaps. Measure repeated-reference cache hits, latency and memory against the existing per-turn baseline using identical model/settings. Test reference changes, cancelled scenes, unsupported directions, native-rate playback/export, and real second-engine reuse. Then 30-minute continuity and normal Quit/reaped worker evidence. Source tests alone do not qualify this design.

Dependencies: ACD-A1/C1 for final character identity, ACD-R1 for bounded ownership, and ACD-M1's descriptor identity contract; no circular requirement to finish every model-switch qualification first. Reconcile engine capability, speech enrichment, character casting, playback/runtime and artifact/export architecture. Keep public fixtures synthetic and City text/audio private.

### Source and reconciliation anchors

Pinned existing owners, not implementation of this ACD. Additional exact locations and test matrices remain in the linked review findings.

- [lib/src/models/prepared_voice_binding.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/models/prepared_voice_binding.dart)
- [lib/src/services/tts_engine.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/services/tts_engine.dart)
- [assets/mlx_tts_worker.py](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/assets/mlx_tts_worker.py)
- [project/architecture/engine-pronunciation-expression-and-capability-adaptation.md](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/project/architecture/engine-pronunciation-expression-and-capability-adaptation.md)
- [test/mlx_synthesis_attempt_test.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/test/mlx_synthesis_attempt_test.dart)
