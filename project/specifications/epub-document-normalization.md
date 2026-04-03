# EPUB Document Normalization

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines EPUB-specific normalization behavior.

## Backlink

Parent specification:

- [Markup and Archive Document Normalization](markup-and-archive-document-normalization.md)

## Scope

This specification covers:

- EPUB reading order
- treatment of navigation documents
- chapter and media normalization behavior

This specification does not define HTML or DOCX rules.

## Behavior

### EPUB Rule

- spine order defines reading order
- navigation documents do not become body speech content
- chapter content is normalized in spine order
- inline media references and captions should be preserved when extractable

## Constraints

- archive traversal and chapter/entry ordering must remain deterministic

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- EPUB normalization has explicit reading-order and navigation-handling rules.
- Chapter content and extractable media are preserved in spine order.

