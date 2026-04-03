# DOCX Document Normalization

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines DOCX-specific normalization behavior.

## Backlink

Parent specification:

- [Markup and Archive Document Normalization](markup-and-archive-document-normalization.md)

## Scope

This specification covers:

- DOCX reading order
- paragraph and heading preservation
- inline media handling

This specification does not define HTML or EPUB rules.

## Behavior

### DOCX Rule

- paragraph order defines reading order
- headings and paragraph boundaries must be preserved when the parser exposes them
- inline media should remain represented as attachment or placeholder content rather than being silently dropped

## Constraints

- DOCX normalization must preserve parser-exposed paragraph structure where available

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- DOCX normalization has explicit reading-order and paragraph-preservation rules.
- Inline media remains represented rather than being silently dropped.

