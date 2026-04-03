# Import Diagnostics Taxonomy

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the stable diagnostic codes emitted by importers during normalization.

## Backlink

Parent specification:

- [Importer Normalization Contract](importer-normalization-contract.md)

## Scope

This specification covers:

- diagnostic code names
- severity assignment
- emission rules

## Behavior

### Required Type

Every `ImportDiagnostic` must contain:

- `ImportDiagnosticSeverity severity`
- `String code`
- `String message`
- `String? sourceLocator`
- `String? relatedBlockId`

### Supported Severities

- `info`
- `warning`
- `error`

### Required Baseline Codes

The first implementation round must support:

- `unsupported_structure`
- `missing_asset`
- `lossy_conversion`
- `missing_text_layer`
- `fallback_paragraph_grouping`
- `reading_order_suspect`
- `low_mapping_confidence`
- `navigation_content_skipped`

### Severity Rules

- `info` is used for expected, non-destructive cleanup or omission
- `warning` is used when the resulting document is usable but structurally degraded
- `error` is used when a specific portion of content cannot be normalized reliably, even if the overall import can continue

### Emission Rules

- `unsupported_structure` must be emitted when a visible structure is preserved only as an `unsupported` display block or otherwise degraded
- `missing_asset` must be emitted when a referenced media resource cannot be resolved
- `lossy_conversion` must be emitted when structure or text fidelity is intentionally degraded during normalization
- `missing_text_layer` must be emitted for PDFs that lack extractable text
- `fallback_paragraph_grouping` must be emitted when paragraph recovery relies on heuristic grouping instead of explicit source structure
- `reading_order_suspect` must be emitted when extraction evidence suggests multi-column or disordered reading order
- `low_mapping_confidence` must be emitted when `PositionMap` confidence is materially degraded
- `navigation_content_skipped` must be emitted when EPUB or HTML navigation scaffolding is excluded from body content

## Constraints

- Diagnostic codes must remain stable across importer versions unless a migration is documented.
- Diagnostics must be machine-testable; human-readable `message` text is not the stable contract.
- Multiple diagnostics may be emitted for the same source area when concerns differ.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Importers emit stable diagnostic codes for common degradation cases.
- Tests can assert importer behavior against codes rather than free-form strings.
- Mapping-confidence and reading-order problems are observable through diagnostics.
