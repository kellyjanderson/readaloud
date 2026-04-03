# Normalized Layer Compatibility and Migration

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines how legacy compatibility views may coexist with the normalized document layer during migration.

## Backlink

Parent specification:

- [Normalized Document Model](normalized-document-model.md)

## Scope

This specification covers:

- coexistence of normalized outputs with legacy compatibility fields
- derivation direction between normalized output and compatibility views
- migration rule for new playback work

This specification does not define the long-term removal schedule for legacy fields.

## Behavior

### Coexistence Rule

During migration, legacy compatibility outputs may coexist internally with normalized outputs.

Examples include:

- rendered HTML compatibility fields
- flattened speech text compatibility fields
- older reader/controller views that still consume those fields

### Derivation Rule

If legacy compatibility fields are still present:

- they must be derived from normalized outputs
- normalized outputs must not be reconstructed from legacy compatibility fields

### Forward-Work Rule

Any new playback, enrichment, export, or mapping work must target normalized documents first.

Legacy compatibility fields may support temporary adapters, but they must not become the primary design surface for new work.

### Migration Safety Rule

If normalized and legacy views coexist:

- they must remain traceable to the same document identity
- compatibility views must not hide diagnostics or normalization lossiness present in the normalized layer

## Constraints

- migration support must not weaken the normalized layer’s canonical status
- compatibility derivation must remain one-way, from normalized outputs outward
- new feature work must not be specified against legacy flattened-string assumptions

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The repo has an explicit rule for how legacy compatibility views coexist with normalized outputs.
- New work is prevented from drifting back onto legacy importer fields.
- Compatibility behavior remains transitional and downstream of normalized output.
