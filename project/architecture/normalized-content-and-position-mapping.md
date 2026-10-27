# Normalized Content and Position Mapping

Reconciled: October 26, 2026; RC2 implementation through feature head 2734b47
Status: Current source architecture with incremental range publication and automatic checkpoints

## Implemented structure and limitations

Import produces a normalized result envelope, `DisplayDocument`, `SpeechDocument` and `PositionMap` sharing document identity. Display blocks retain structure; speech segments carry normalized text, paragraph/sentence positions and word spans. Mapping entries bridge display blocks to speech ranges and carry confidence and recovery metadata.

`ReaderDocument` also exposes HTML/plain-text compatibility views used by current consumers. They coexist with the structured model; they are not evidence that every caller operates exclusively on normalized DTOs. Imported diagnostics retain parsing and recovery limitations. Quote segmentation separates mixed narration/dialogue before document voice ranges are materialized.

Source-native mapping quality varies by importer. PDF text extraction and line-wrap/paragraph recovery are heuristic. A successful import or a mapping fixture does not prove perfect reading order for arbitrary documents. Source bytes are acquired separately from these normalized representations.

Interactive preparation freezes each normalized range on the worker before transfer. Display blocks/inlines/assets/metadata, speech segments/index/word spans, position entries, diagnostics, pronunciation artifacts and cast alias/id arrays are unmodifiable. Existing immutable annotation/attribution/identity objects retain their evidence and uncertainty. PDF data uses an unmodifiable owned byte snapshot. HTML, flat text and document word spans cross with each fragment without rebuilding on the UI isolate. The controller publishes contiguous ranges under one document revision and bounds unconsumed reading-ahead; downstream consumption and later preparation can overlap. This does not establish universal source-format incrementality or whole-book readiness at first publication.

Automatic repository checkpoints persist these immutable fragments with range source/word/segment coverage and checksums. Complete-manifest replay uses the same source revision; file-backed paths and callback-acquired bytes currently miss because their content identity is not available before supervisor admission. Directly captured text/bytes are eligible, but hashing the full captured input precedes lookup. Corruption invalidates the generation and retry rebuilds from source rather than continuing a partial prefix. Partial checkpoints remain incomplete and are not full-book exports. The normal `.radoc` picker path accepts serialized v1/v2 `ReaderDocument` data and rejects malformed/unsupported input with re-export guidance. The separate instrumented `.radoc-v2` codec still decodes to an immutable inspection snapshot, omits embedded asset/PDF bytes, and is not itself an application restore format. Neither format currently supplies complete multi-range checkpoint export. See [#83](https://github.com/kellyjanderson/readaloud/issues/83), [#90](https://github.com/kellyjanderson/readaloud/issues/90), and [#101](https://github.com/kellyjanderson/readaloud/issues/101).

V2 preserves ordered annotations/attributions and uncertainty, explicit assignment/resource-reference records, caller-provided document revision and optional delivery/inflection annotations with explicit source or user provenance and numeric confidence, anchored to inclusive-start/exclusive-end speech-word spans. Validation checks kind/payload pairing, finite confidence, segment membership and word bounds. Unknown intent stays absent; importers do not infer it from prose. V1 omits new annotation kinds. Realization records unsupported engine-default fallback without changing canonical intent; see [slice #79](https://github.com/kellyjanderson/readaloud/issues/79).

## Source and tests

- [normalized_import_result.dart](../../lib/src/models/normalized_import_result.dart)
- [display_document.dart](../../lib/src/models/display_document.dart)
- [speech_document.dart](../../lib/src/models/speech_document.dart)
- [position_map.dart](../../lib/src/models/position_map.dart)
- [document_import_service.dart](../../lib/src/services/document_import_service.dart)
- [document_ingestion_smoke_test.dart](../../test/document_ingestion_smoke_test.dart)
- [spoken_selection_mapper_service_test.dart](../../test/spoken_selection_mapper_service_test.dart)

Worker/direct-import artifact equality and mutation rejection are covered by [preparation tests](../../test/document_preparation_supervisor_test.dart). Current exact execution evidence lives in [P1](https://github.com/kellyjanderson/readaloud/issues/50); mapping fidelity on fixtures is not universal source-layout correctness.

## Proposed changes

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/normalized-content-and-position-mapping.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [display document](../specifications/display-document.md)
- [docx document normalization](../specifications/docx-document-normalization.md)
- [epub document normalization](../specifications/epub-document-normalization.md)
- [html document normalization](../specifications/html-document-normalization.md)
- [import diagnostics taxonomy](../specifications/import-diagnostics-taxonomy.md)
- [import failure and partial success semantics](../specifications/import-failure-and-partial-success-semantics.md)
- [import source acquisition and fingerprinting](../specifications/import-source-acquisition-and-fingerprinting.md)
- [import structural cleanup and visible content preservation](../specifications/import-structural-cleanup-and-visible-content-preservation.md)
- [line wrap and paragraph recovery](../specifications/line-wrap-and-paragraph-recovery.md)
- [lossy text common heuristic grouping](../specifications/lossy-text-common-heuristic-grouping.md)
- [markup and archive common structural normalization](../specifications/markup-and-archive-common-structural-normalization.md)
- [normalized import result envelope](../specifications/normalized-import-result-envelope.md)
- [normalized layer compatibility and migration](../specifications/normalized-layer-compatibility-and-migration.md)
- [normalized layer shared identity and metadata](../specifications/normalized-layer-shared-identity-and-metadata.md)
- [pdf extracted text normalization](../specifications/pdf-extracted-text-normalization.md)
- [plain and shared text normalization](../specifications/plain-and-shared-text-normalization.md)
- [position map](../specifications/position-map.md)
- [rtf flattened text normalization](../specifications/rtf-flattened-text-normalization.md)
- [speech document](../specifications/speech-document.md)
