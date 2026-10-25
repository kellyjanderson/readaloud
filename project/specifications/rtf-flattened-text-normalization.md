# RTF Flattened Text Normalization

## Architecture ownership

- [document speech pipeline](../architecture/document-speech-pipeline.md)
- [normalized content and position mapping](../architecture/normalized-content-and-position-mapping.md)
- [system overview](../architecture/system-overview.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines normalization behavior for flattened RTF text.

## Backlink

Parent specification:

- [Lossy Extracted Text Normalization](lossy-extracted-text-normalization.md)

## Scope

This specification covers:

- control-noise stripping
- metadata-table stripping
- paragraph-boundary preservation for flattened RTF

This specification does not define generic heuristic-grouping policy.

## Behavior

### RTF Rule

- formatting may be flattened during initial normalization
- obvious metadata tables and control-noise groups should be stripped before text recovery
- paragraph boundaries should be preserved where they can be recovered safely

## Constraints

- flattened RTF recovery must still converge on canonical normalized outputs without pretending rich structure exists

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Flattened RTF normalization has explicit cleanup and paragraph-preservation rules.
- RTF flattening remains weak but explicit instead of accidental.

