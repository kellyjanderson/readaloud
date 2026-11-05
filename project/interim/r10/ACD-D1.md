## ACD-D1 — Consolidation through narrow shared contracts

> Fixed published R1 snapshot, captured November 4, 2026 Pacific.
> [Source design/plan](https://github.com/kellyjanderson/readaloud/issues/114#acd-d1--consolidation-through-narrow-shared-contracts) · [package provenance](README.md) · [lifecycle](../README.md).
> GitHub owns current execution state; this snapshot is not an implementation or acceptance claim.

Design revision R1, November 4, 2026 Pacific; base `1f605cfa74bc4374ffc278cb9ccb67218efe6cc4`. The [C01–C09 inventory](https://github.com/kellyjanderson/readaloud/issues/114#consolidation-inventory-r8) is the diagnosis and source/test index; do not repeat that scan. This ACD defines implementation boundaries under [plan R10](https://github.com/kellyjanderson/readaloud/issues/110#implementation-plan-r10).

### Scope and ownership
C01 engine descriptors belongs to ACD-M1/S1; C02 neutral session ownership belongs to ACD-R1. Implement each once. This issue owns C03–C07 and conditional C08/C09 after a stable Drama comparison. No whole-app state-management rewrite, new database, custom general-purpose scheduler or new player follows from consolidation.

| Slice | Shared contract and consumers | Preserve / remove |
| --- | --- | --- |
| D1.1 / C03 | `PcmFormat`, bounded RIFF chunk walker and header writer for byte buffers and random-access files; consumed by artifact validation, WAV analysis, boundary correction, export and Kokoro encoding | Remove repeated RIFF offsets/header logic. Keep canonical-artifact, analysis, trimming and export compatibility policies separate. Validate chunk bounds/padding/frame alignment; retain native rates/channels supported by each consumer. Never coerce all consumers to the narrowest format. |
| D1.2 / C04 | Per-format import adapter emits source-located metadata/block/diagnostic events; interactive preparation consumes bounded events, whole-file API explicitly collects the same events | DOCX then EPUB, then HTML/text policy parity. Preserve title, headings/lists, image placeholders, Unicode/source offsets and malformed-member semantics. Keep shared RTF decoder and pdfrx. No full-DOM/full-book gate introduced for first speech. |
| D1.3 / C05 | Data-only document-envelope encoder with explicit schema and inclusion options, used by `.radoc` and inspection encoders | Remove JSON encode→decode and unnecessary PDF base64 work. Keep restoration validation, immutable worker snapshots, repository generations and inspection/reopen formats distinct. Coordinate with C1 schema; never silently accept future versions. |
| D1.4 / C07 | Production JSON-lines client and descriptor access for model probes; shared headless controller setup/options/disposal | Remove private model-global mutation and duplicate engine/reference lists. Keep benchmark workloads, authoring tools and evidence policies distinct. Offline voice authoring must consume complete requested output before any deliberate asset regeneration. |
| D1.5 / C06/C08/C09 | Optional adjacency utility, isolate lifetime handle, native bookmark grant/lease helpers | Extract only if the specific patch removes duplicate mechanics without growing policy surface. Keep cast merge predicates, worker queue/epoch rules and file/directory permission semantics with their owners. |

### Library choices and concurrency
Retain mlx-audio/Hugging Face/just_audio, archive/xml/html/pdfrx and existing range rendering for their established work. Before adopting a new RIFF, async, pool or persistence package, test the actual required subset: random-access/streaming, bounded memory, offline/native packaging, cancellation semantics and notices. Record the candidate/version and removed implementation in the slice receipt. If no maintained package meets a concrete requirement, a small shared module is justified; duplication alone is not proof a large dependency helps.

D1.1 I/O and audio work stays on existing admitted workers. D1.2 decoding/event production stays in preparation workers with eight-credit publication and explicit source/analysis revision; no shared mutable parser across documents. D1.3 encoding/persistence retains its repository writer, stale-write rejection and atomic publication. D1.4 client owns one child/request stream and verifies shutdown; it cannot bypass production admission. Cancellation releases only owned buffers/temp files. No new asynchronous owner is introduced by utility extraction.

### Migration and acceptance
Land one consumer group at a time, with compatibility adapters until parity passes; remove the replaced implementation in the same completed slice. Compare fixtures/semantics, not only text length or hashes. D1.1: 24/44.1/48 kHz, metadata/odd chunks, malformed/truncated RIFF, decoded sample/duration equivalence and bounded export memory. D1.2: split/whole parity across formats, richer metadata, EOF, corrupt input, mapping and first-publication/memory bounds. D1.3: v1/v2 plus new C1 migration fixtures, directions, assignments, PDF omission, corrupt checkpoints and stale writes. D1.4: real production protocol, full piece/final/cancel flow and one real model/app scenario. Optional native bookmark/lifecycle extraction needs actual macOS permission/exit evidence.

Use each C03–C09 test list already published in the inventory. Reconcile audio-artifact/export, normalized content/document pipeline and runtime architecture per landed slice. C05 follows C1 schema integration; C07 follows stable M1/S1 descriptors/protocol. Independent small utilities must not delay first audible Drama. Rollback remains per slice with serialized formats and private user assets preserved.

### Source and reconciliation anchors

Pinned existing owners, not implementation of this ACD. Additional exact locations and test matrices remain in the linked review findings.

- [lib/src/services/audio_artifact_store.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/services/audio_artifact_store.dart)
- [lib/src/services/document_import_service.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/services/document_import_service.dart)
- [lib/src/services/reader_document_serialization_service.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/services/reader_document_serialization_service.dart)
- [project/architecture/normalized-content-and-position-mapping.md](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/project/architecture/normalized-content-and-position-mapping.md)
