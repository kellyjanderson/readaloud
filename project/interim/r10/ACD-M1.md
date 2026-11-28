## ACD-M1 — Verified model assets and live engine sessions

> Fixed published R1 snapshot, captured November 4, 2026 Pacific.
> [Source design/plan](https://github.com/kellyjanderson/readaloud/issues/112#acd-m1--verified-model-assets-and-live-engine-sessions) · [package provenance](README.md) · [lifecycle](../README.md).
> GitHub owns current execution state; this snapshot is not an implementation or acceptance claim.

Design revision R1, November 4, 2026 Pacific; base `1f605cfa74bc4374ffc278cb9ccb67218efe6cc4`. Basis: confirmed selection, catalog, hardware and transition contracts above; #114 C01. Proposed implementation delta under [plan R10](https://github.com/kellyjanderson/readaloud/issues/110#implementation-plan-r10).

### Catalog and acquisition decisions
Separate engine family, checkpoint variant and runtime identity. A versioned descriptor contains stable IDs/legacy aliases, pinned repository revision, complete required-file manifest/digests, quantization layout, codec/native formats, runtime compatibility, qualified capabilities, disk estimate, measured memory envelope, notices and qualification state. The catalog is the common input for settings, factory, downloader and probes. Preserve all saved engine IDs via aliases; unknown or incompatible variants remain visible as unavailable with a reason.

The bundled catalog is the trusted fallback. Any refresh is validated data only, with fixed provider/host policy and schema/runtime checks; downloaded configuration cannot enable arbitrary Python execution. Do not select a mutable upstream branch as runtime provenance. Refresh failure preserves the last valid catalog. New architectures requiring executable dependencies need an explicit runtime/app update.

Extend the existing app-owned Hugging Face downloader and stable Application Support store; do not create another downloader. Per-variant acquisition is single-flight, resumable and separately cancellable from document work. A file is reusable only when its required identity/integrity is valid; publish a complete-snapshot marker atomically after every required artifact validates. Cached complete snapshots load before any network request. Development rebuilds and supported app identities resolve the documented persistent store; isolated QA profiles remain isolated. Cancellation preserves verified files/partials for resume and never deletes another installed variant. Surface actual bytes/file counts and final validation through ACD-F1.

### Selection and session state
Default policy selects the highest-quality supported candidate that fits the smaller of the user's 100,000,000,000-byte total-runtime ceiling and measured device headroom. Count app, TTS child, attribution child, GPU/native allocations and queued audio; estimates/admission are not proof of hard peak bounds. Unknown envelopes require qualification, not optimistic admission. Retain explicit user choices and disclose any unavailable candidate/fallback. M5/128 GB is primary; actual M3 chip/RAM must be recorded before certification. Download prequantized 8-bit/4-bit variants directly; never load bf16 just to quantize on a smaller Mac. Compare matched source lineage or report the confound.

Main-isolate `EngineSession` publishes selected identity separately from active identity. Transition: `active → stopping → unloading → acquiring → loading → validating → active`, with explicit cancelled/failed states. One transition plus one replaceable desired selection. Capture reading anchor and voice intent; stop playback/preview and visibly cancel an active export before retiring its engine. Cancel pending Play on replacement; no automatic speech after cancellation. Worker release/reap must complete before loading another large model unless an independently measured overlap budget permits it.

Every progress/result/error carries transition epoch and child generation. Publish active identity atomically after model/reference/format validation. A→B→C cannot install late B. On failure retain desired choice and last-working descriptor; returning to it is an honest reload if its child was released. Quit invalidates all transitions and reaps the owned child. Restarting a helper is permitted; restarting the application or rebuilding for a supported variant is not required.

### Changes, migration and proof
Owners: `speech_engine_catalog.dart`, `assets/fish_drama_models.json`, factory/controller settings, MLX processor/worker and probes. ACD-S1 owns synthesis capability semantics; M1 owns descriptor identity/acquisition/selection. ACD-R1 owns process cancellation. Preserve existing on-disk snapshots and preference aliases; invalidate only incompatible derived bindings/audio, not weights or work characters.

Require complete-model offline reopen, interrupted resume, corrupt-file repair, failed retry, two dev build paths without completed-file retransfers; A/B/A and rapid A/B/C during synthesis/download/preview/export; no orphan/overlapping large child, preserved anchor/intent, accurate selected/active UI and memory measurements on each actual target. No restart/rebuild for installed compatible variants. Reconcile runtime messaging, engine capability, reader session state and model setup/support matrix. Package/notices remain #122/#55 gates; missing M3 evidence is explicit, not inferred from M5 tests.

### Source and reconciliation anchors

Pinned existing owners, not implementation of this ACD. Additional exact locations and test matrices remain in the linked review findings.

- [lib/src/models/speech_engine_catalog.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/models/speech_engine_catalog.dart)
- [assets/fish_drama_models.json](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/assets/fish_drama_models.json)
- [lib/src/services/mlx_speech_worker_processor.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/services/mlx_speech_worker_processor.dart)
- [docs/mlx-tts-engines.md](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/docs/mlx-tts-engines.md)
