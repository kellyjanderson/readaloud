# Importer Normalization Contract

Last updated: March 31, 2026
Status: Draft specification

## Scope

This specification defines how importers convert source files or pasted text into normalized documents.

## Backlink

Parent specification:

- [Normalized Document Model](normalized-document-model.md)

## Behavior

The importer branch now delegates detailed contracts to focused child specifications.

In particular:

- source acquisition and canonical fingerprinting belong to their own leaf
- cleanup and visible-structure preservation belong to their own leaf
- format-family normalization rules belong to dedicated leaves
- failure and partial-success behavior belongs to its own leaf

This parent specification keeps only the branch-level rule that all importers must converge on one normalized output contract.

## Required Output

Every importer must emit:

- `NormalizedImportResult result`

`NormalizedImportResult` must contain:

- `DisplayDocument displayDocument`
- `SpeechDocument speechDocument`
- `PositionMap positionMap`
- `List<ImportDiagnostic> diagnostics`

The importer must derive `documentId` before block and segment ids are assigned.

## Constraints

- The importer path must stay lightweight enough to preserve responsive file-open behavior.
- Importers must not depend on voice selection or engine-specific realization.
- Lossy decisions must be diagnosable, not silent.

## Refinement Status

This specification requires further refinement.

## Child Specifications

- [Import Source Acquisition and Fingerprinting](import-source-acquisition-and-fingerprinting.md)
- [Import Diagnostics Taxonomy](import-diagnostics-taxonomy.md)
- [Import Structural Cleanup and Visible Content Preservation](import-structural-cleanup-and-visible-content-preservation.md)
- [Markup and Archive Document Normalization](markup-and-archive-document-normalization.md)
- [Lossy Extracted Text Normalization](lossy-extracted-text-normalization.md)
- [Import Failure and Partial Success Semantics](import-failure-and-partial-success-semantics.md)
- [Line Wrap and Paragraph Recovery](line-wrap-and-paragraph-recovery.md)

## Acceptance

- The remaining importer behavior unique to this branch is represented by final leaf specifications.
- All importer families converge on one normalized output contract without hiding source, cleanup, or failure behavior only in parent prose.
