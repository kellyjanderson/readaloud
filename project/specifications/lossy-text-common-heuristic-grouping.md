# Lossy Text Common Heuristic Grouping

## Architecture ownership

- [document speech pipeline](../architecture/document-speech-pipeline.md)
- [normalized content and position mapping](../architecture/normalized-content-and-position-mapping.md)
- [system overview](../architecture/system-overview.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines common heuristic-grouping behavior for lossy extracted-text families.

## Backlink

Parent specification:

- [Lossy Extracted Text Normalization](lossy-extracted-text-normalization.md)

## Scope

This specification covers:

- common reading-order preservation
- heuristic paragraph recovery behavior
- diagnostics expectations for heuristic grouping

This specification does not define family-specific rules.

## Behavior

### Common Rule

For lossy extracted-text families:

- preserve the best available reading order
- recover paragraph structure heuristically when explicit structure is weak or absent
- emit diagnostics when grouping or extraction is known to be heuristic

## Constraints

- lossy extracted-text normalization must never pretend high structural confidence when the importer is using heuristics
- heuristic grouping decisions must be diagnosable

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Heuristic grouping and fragile reading-order recovery are explicit and diagnosable.
- Lossy text families share one common heuristic-grouping contract.

