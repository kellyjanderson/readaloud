# RTF Flattened Text Normalization

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

