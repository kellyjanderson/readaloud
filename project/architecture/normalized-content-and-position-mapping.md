# Normalized Content and Position Mapping

Reconciled: November 13, 2026; shared import adapters, [S9.3 #149](https://github.com/kellyjanderson/readaloud/issues/149)
Status: Current source architecture with incremental range publication and automatic checkpoints

## Implemented structure and limitations

Import produces a normalized result envelope, `DisplayDocument`, `SpeechDocument` and `PositionMap` sharing document identity. Display blocks retain structure; speech segments carry normalized text, paragraph/sentence positions and word spans. Mapping entries bridge display blocks to speech ranges and carry confidence and recovery metadata.

`ReaderDocument` also exposes HTML/plain-text compatibility views used by current consumers. They coexist with the structured model; they are not evidence that every caller operates exclusively on normalized DTOs. Imported diagnostics retain parsing and recovery limitations. Quote segmentation separates mixed narration/dialogue before document voice ranges are materialized.

Source-native mapping quality varies by importer. PDF text extraction and line-wrap/paragraph recovery are heuristic. A successful import or a mapping fixture does not prove perfect reading order for arbitrary documents. Source bytes are acquired separately from these normalized representations.

Text/Markdown, HTML, DOCX and EPUB use the same `DocumentImportUnit` adapters for interactive
preparation and the explicit whole-file collector in `importBytes`. Units carry
source member/block locators, title, structural HTML, attachment records and
diagnostics. DOCX paragraphs preserve headings, exposed list markers and inline
media placeholders. EPUB reads package events and chapters in spine order,
retains metadata titles and embedded images, and reports skipped navigation and
missing members/assets. Missing required container/package/document metadata and
invalid member XML or CRC are typed failures; a missing optional spine member is
degraded success with `missing_asset`, rather than silent omission. A late parse
failure can follow earlier bounded publications and never establishes complete
source readiness. Optional invalid DOCX title metadata still falls back to the
filename. The collector accumulates the entire document only when explicitly
requested; the interactive path does not use it.

HTML normalizes bounded fragments with the maintained parser and reuses display
block policy for speech boundaries around lists, captions and nested structures.
It preserves split tags/entities and UTF-16 surrogate pairs, excluded-navigation
diagnostics and trailing media/separators, including sources containing only
structure. Structural-only units advance a single newline in the normalized
source coordinate space so successive range-local IDs cannot alias; they add no
speech. Metadata-only terminal events instead carry diagnostics/title metadata
with no source span, display blocks or speech, and explicitly suppress synthetic
title fallback. Locators remain member/block coordinates, not raw archive byte offsets.
Text file, pasted and shared entry points share recovery policy while retaining
their distinct source identities and descriptions. Heuristic mapping fallback
clamps inline offsets to the actual display block and retains low confidence and
exact recovery evidence. RTF keeps its existing shared decoder, and PDF keeps its
separate native extraction/formatting ownership.

The existing preparation worker owns each adapter instance and source handle.
Its revision/session identity, eight-credit publication window, stale-result
rejection and cancellation/worker shutdown remain the concurrency boundary.
Adapters add no background producer or shared parser state. ZIP directory and
EPUB manifest metadata remain resident; chapter bodies and DOCX text are read
incrementally with bounded text units. Embedded image decoding still requires
one image's bytes and base64 display representation; this is not a constant
memory claim for arbitrarily large media. The existing `archive`, `xml`, `html`
and `pdfrx` packages remain in use; the shared adapter is application-specific
structure/provenance policy, not a replacement ZIP/XML/HTML parser.

Only the preparation supervisor retains a successor for EOF/dialogue lookahead;
HTML and EPUB adapters yield each completed content unit immediately rather
than holding another successor. Later excluded content or metadata cannot make
two already completed readable units wait for EOF. Trailing diagnostics use the
metadata-only events above. The HTML context stack accounts for implicit end
tags, including repeated paragraphs and list items, before applying its nesting
limit; the maintained HTML parser still builds and repairs the bounded DOMs.
Genuine excessive nesting and oversized incomplete tokens remain typed failures.

Interactive preparation freezes each normalized range on the worker before transfer. Display blocks/inlines/assets/metadata, speech segments/index/word spans, position entries, diagnostics, pronunciation artifacts and cast alias/id arrays are unmodifiable. Existing immutable annotation/attribution/identity objects retain their evidence and uncertainty. PDF data uses an unmodifiable owned byte snapshot. HTML, flat text and document word spans cross with each fragment without rebuilding on the UI isolate. The controller publishes contiguous ranges under one document revision and bounds unconsumed reading-ahead; downstream consumption and later preparation can overlap. This does not establish universal source-format incrementality or whole-book readiness at first publication.

Automatic repository checkpoints persist immutable fragments with source/word/segment coverage and checksums. Complete-manifest replay skips source acquisition and analysis for a matching content revision or trusted local macOS file-generation receipt. File identity uses canonical target, device/inode/generation, size, nanosecond mtime/ctime and mode; it requires no whole-source startup hash, and is checked around acquisition/replay/EOF. Unsupported metadata and callback-acquired bytes miss conservatively. Captured text/bytes retain their full-input hash before lookup. The [pipeline](document-speech-pipeline.md) documents probe ownership and metadata trust limits. Corruption invalidates the generation; retry rebuilds from the untouched source rather than continuing a partial prefix. Partial checkpoints cannot export a full book. Explicit complete-checkpoint export validates all ranges and merges their existing derived graphs on a worker, preserving segment IDs and evidence while qualifying local counter IDs and adjusting global ordering/word offsets. The result is regular v2 `.radoc` data, including optional explicit cast choices; the normal picker restores it without reanalysis. Malformed assignments fail before preferences/document mutation. The instrumented `.radoc-v2` inspection codec remains separate and does not restore an application document or native resources. See [#83](https://github.com/kellyjanderson/readaloud/issues/83), [#90](https://github.com/kellyjanderson/readaloud/issues/90), and [#101](https://github.com/kellyjanderson/readaloud/issues/101).

V2 preserves ordered annotations/attributions and uncertainty, explicit assignment/resource-reference records, caller-provided document revision and optional delivery/inflection annotations with explicit source or user provenance and numeric confidence, anchored to inclusive-start/exclusive-end speech-word spans. Validation checks kind/payload pairing, finite confidence, segment membership and word bounds. Unknown intent stays absent; importers do not infer it from prose. V1 omits new annotation kinds. Realization records unsupported engine-default fallback without changing canonical intent; see [slice #79](https://github.com/kellyjanderson/readaloud/issues/79).

## Source and tests

- [normalized_import_result.dart](../../lib/src/models/normalized_import_result.dart)
- [display_document.dart](../../lib/src/models/display_document.dart)
- [speech_document.dart](../../lib/src/models/speech_document.dart)
- [position_map.dart](../../lib/src/models/position_map.dart)
- [document_import_service.dart](../../lib/src/services/document_import_service.dart)
- [document_ingestion_smoke_test.dart](../../test/document_ingestion_smoke_test.dart)
- [document_import_adapter_test.dart](../../test/document_import_adapter_test.dart)
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
