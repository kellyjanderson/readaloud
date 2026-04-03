# HTML Document Normalization

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines HTML-specific normalization behavior.

## Backlink

Parent specification:

- [Markup and Archive Document Normalization](markup-and-archive-document-normalization.md)

## Scope

This specification covers:

- HTML block-boundary behavior
- HTML hidden/script/style removal expectations
- HTML structural preservation behavior

This specification does not define EPUB or DOCX rules.

## Behavior

### HTML Rule

- block elements define initial display-block boundaries
- hidden, script, and style content must be removed before normalization
- semantic headings, lists, tables, blockquotes, and media references must be preserved when available

## Constraints

- HTML normalization must preserve semantic block structure when available

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- HTML normalization has explicit block-boundary and semantic-preservation rules.
- HTML cleanup removes hidden/script/style content before normalized output is built.

