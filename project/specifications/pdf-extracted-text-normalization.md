# PDF Extracted Text Normalization

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines normalization behavior for extracted PDF text.

## Backlink

Parent specification:

- [Lossy Extracted Text Normalization](lossy-extracted-text-normalization.md)

## Scope

This specification covers:

- PDF reading-order behavior
- PDF paragraph grouping behavior
- PDF page-boundary handling
- PDF extraction diagnostics

This specification does not define generic heuristic-grouping policy.

## Behavior

### PDF Rule

- page order defines initial reading order
- extracted text is grouped heuristically into paragraphs
- each page boundary becomes a display-side page-break block when page identity is available
- missing text-layer content must produce diagnostics rather than silent omission
- suspicious extracted reading order should surface diagnostics

## Constraints

- PDF extraction weakness must remain visible through diagnostics

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- PDF extracted text has explicit reading-order, page-boundary, and diagnostic rules.
- Missing or suspicious PDF text extraction remains visible rather than silent.

