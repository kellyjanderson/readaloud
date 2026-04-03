# Normalized Document Model

Last updated: March 31, 2026
Status: Draft specification

## Scope

This is the umbrella specification for the normalized document layer.

It defines the shared contract that every importer must satisfy before document content can move into rendering, chunk planning, or playback.

## Backlink

Parent architecture:

- [Normalized Content and Position Mapping](../architecture/normalized-content-and-position-mapping.md)

Detailed implementation specifications:

- [Display Document](display-document.md)
- [Speech Document](speech-document.md)
- [PositionMap](position-map.md)
- [Importer Normalization Contract](importer-normalization-contract.md)
- [Normalized Import Result Envelope](normalized-import-result-envelope.md)
- [Normalized Layer Shared Identity and Metadata](normalized-layer-shared-identity-and-metadata.md)
- [Normalized Layer Compatibility and Migration](normalized-layer-compatibility-and-migration.md)

## Behavior

The normalized document branch now delegates the detailed shared-contract work to focused child specifications.

In particular:

- the normalized output envelope belongs to its own leaf
- shared identity, metadata, and versioning invariants belong to their own leaf
- legacy compatibility and migration behavior belongs to its own leaf

This parent specification keeps only the branch-level rule that every importer must converge on one normalized document layer before rendering, enrichment, or playback.

## Refinement Status

This is a draft umbrella specification. Its child specifications are expected to carry most implementation detail.

## Child Specifications

- [Display Document](display-document.md)
- [Speech Document](speech-document.md)
- [PositionMap](position-map.md)
- [Importer Normalization Contract](importer-normalization-contract.md)
- [Normalized Import Result Envelope](normalized-import-result-envelope.md)
- [Normalized Layer Shared Identity and Metadata](normalized-layer-shared-identity-and-metadata.md)
- [Normalized Layer Compatibility and Migration](normalized-layer-compatibility-and-migration.md)

## Acceptance Criteria

- An importer can emit a complete `NormalizedImportResult` without populating a legacy `speakableText` field.
- Controller code can choose display or speech consumers by type instead of by ad hoc string fields.
- Controller code can resolve playback positions through `PositionMap`.
- Diagnostics exist for importer lossiness and unsupported content.
- The remaining shared normalized-layer work is represented by final leaf specifications.

## Deferred Items

- semantic metadata systems beyond what is required to preserve display and speech structure
- generated descriptions for non-text media
- cross-document annotations or embeddings
