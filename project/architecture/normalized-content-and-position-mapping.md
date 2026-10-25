# Normalized Content and Position Mapping

Reconciled: October 24, 2026
Status: Current source architecture; runtime validation not refreshed

## Implemented structure and limitations

Import produces a normalized result envelope, `DisplayDocument`, `SpeechDocument` and `PositionMap` sharing document identity. Display blocks retain structure; speech segments carry normalized text, paragraph/sentence positions and word spans. Mapping entries bridge display blocks to speech ranges and carry confidence and recovery metadata.

`ReaderDocument` also exposes HTML/plain-text compatibility views used by current consumers. They coexist with the structured model; they are not evidence that every caller operates exclusively on normalized DTOs. Imported diagnostics retain parsing and recovery limitations. Quote segmentation separates mixed narration/dialogue before document voice ranges are materialized.

Source-native mapping quality varies by importer. PDF text extraction and line-wrap/paragraph recovery are heuristic. A successful import or a mapping fixture does not prove perfect reading order for arbitrary documents. Source bytes are acquired separately from these normalized representations.

## Source and tests

- [normalized_import_result.dart](../../lib/src/models/normalized_import_result.dart)
- [display_document.dart](../../lib/src/models/display_document.dart)
- [speech_document.dart](../../lib/src/models/speech_document.dart)
- [position_map.dart](../../lib/src/models/position_map.dart)
- [document_import_service.dart](../../lib/src/services/document_import_service.dart)
- [document_ingestion_smoke_test.dart](../../test/document_ingestion_smoke_test.dart)
- [spoken_selection_mapper_service_test.dart](../../test/spoken_selection_mapper_service_test.dart)

Tests listed here are existing evidence locations, not a claim that they passed in this review. The bundled Intel Dart executable cannot run in the current Apple Silicon execution environment.

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
