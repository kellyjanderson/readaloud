# Normalized Import Result Envelope

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines the shared output envelope emitted by every importer after normalization.

## Backlink

Parent specification:

- [Normalized Document Model](normalized-document-model.md)

## Scope

This specification covers:

- `NormalizedImportResult`
- the required top-level members of normalized importer output
- success-path expectations for a structurally valid normalized result
- downstream consumer expectations for the envelope

This specification does not define the internals of `DisplayDocument`, `SpeechDocument`, `PositionMap`, or importer diagnostics.

## Behavior

### Required Output Contract

Every importer must produce one `NormalizedImportResult` value with:

- one `DisplayDocument`
- one `SpeechDocument`
- one `PositionMap`
- zero or more import diagnostics

### Structural Validity Rule

A successful `NormalizedImportResult` must be structurally valid even when it is degraded or lossy.

That means:

- `DisplayDocument`, `SpeechDocument`, and `PositionMap` are all present
- all three objects are internally well-formed according to their own specifications
- diagnostics explain degradation instead of replacing required normalized outputs

### Consumer Rule

- rendering consumes `DisplayDocument`
- speech enrichment and playback consume `SpeechDocument`
- progress mapping, future highlighting, and jump mapping consume `PositionMap`

Later layers must not bypass the envelope by depending on ad hoc importer strings as their primary input.

## Constraints

- the normalized envelope must remain the canonical output of import, even if legacy compatibility fields coexist elsewhere
- a successful normalized result must not be represented only as display HTML plus flattened text
- importer diagnostics may be empty, but the diagnostics collection must always exist conceptually as part of the envelope

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Every importer converges on one shared normalized output envelope.
- Downstream layers can choose consumers by normalized type instead of by ad hoc importer-specific fields.
- Degraded success remains structurally valid and diagnosable.
