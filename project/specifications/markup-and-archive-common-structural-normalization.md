# Markup and Archive Common Structural Normalization

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines common normalization behavior for markup- and archive-backed document families.

## Backlink

Parent specification:

- [Markup and Archive Document Normalization](markup-and-archive-document-normalization.md)

## Scope

This specification covers:

- common parsing and structural-preservation rules shared by HTML, EPUB, and DOCX

This specification does not define format-specific rules.

## Behavior

### Common Rule

For markup- and archive-backed families:

- parse the source into an intermediate representation
- preserve explicit ordering and structure where the format provides it
- prefer structural preservation over flattening into plain paragraphs

## Constraints

- markup/archive normalization must not flatten explicit structure into plain text unless degradation is required
- any structural downgrade must surface through diagnostics

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Markup-backed families share one clear common structural-normalization contract.
- Structural preservation remains the default rather than plain-text flattening.

