# Normalized Layer Shared Identity and Metadata

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines the identity, metadata, and versioning invariants shared across the normalized document layer.

## Backlink

Parent specification:

- [Normalized Document Model](normalized-document-model.md)

## Scope

This specification covers:

- shared `documentId` invariants
- source and title metadata shared across normalized outputs
- normalization and mapping version relationships
- normalized-layer diagnostics visibility

This specification does not redefine the field-level contracts of the individual normalized objects.

## Behavior

### Shared Identity Rule

`DisplayDocument`, `SpeechDocument`, and `PositionMap` must refer to the same logical source document.

At minimum:

- `DisplayDocument.documentId == SpeechDocument.documentId`
- `PositionMap.documentId == DisplayDocument.documentId`

### Shared Metadata Rule

Every normalized import result must preserve, across the normalized layer where applicable:

- document id
- source type
- best available title
- source locator when available
- normalization version
- mapping version
- diagnostics for lossy conversion or unsupported content

### Versioning Rule

- display-side and speech-side normalization versions must remain traceable to the importer/normalization version that produced them
- `PositionMap.mappingVersion` must remain traceable to the normalization pass that emitted the mapping
- version values must be stable enough for caching, export sidecars, and runtime request derivation

### Diagnostics Visibility Rule

Omitted, degraded, or unsupported content must be represented through diagnostics rather than silent loss.

Those diagnostics must remain associated with the normalized result rather than hidden only in importer-local state.

## Constraints

- shared identity must be assigned before later layers derive chunk, realization, or cache identities
- shared metadata must remain engine-agnostic
- source and version metadata must not be lost when legacy compatibility views are derived from normalized output

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The normalized layer has explicit cross-object identity and metadata invariants.
- Versioning and diagnostics relationships are clear across display, speech, and mapping outputs.
- Downstream systems can trust normalized-layer identity and version metadata without rediscovering it.
