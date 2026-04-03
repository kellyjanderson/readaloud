# Plain and Shared Text Normalization

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines normalization behavior for plain text and pasted/shared text.

## Backlink

Parent specification:

- [Lossy Extracted Text Normalization](lossy-extracted-text-normalization.md)

## Scope

This specification covers:

- plain text normalization
- pasted/shared text normalization

This specification does not redefine line-wrap recovery heuristics.

## Behavior

### Plain Text and Paste Rule

- blank-line runs create paragraph boundaries
- non-empty lines within a paragraph are joined through normalized spacing unless paragraph-recovery heuristics decide otherwise
- markdown-style headings and list markers may be recovered when present

## Constraints

- plain/shared normalization must still converge on canonical display, speech, and position outputs

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Plain and shared text normalization has explicit paragraph and markdown-recovery rules.
- Plain/shared text still converges on canonical normalized outputs.

