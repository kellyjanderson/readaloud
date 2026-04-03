# Markup and Archive Document Normalization

Last updated: April 1, 2026
Status: Draft specification

## Overview

This specification defines the markup- and archive-backed normalization branch.

## Backlink

Parent specification:

- [Importer Normalization Contract](importer-normalization-contract.md)

## Scope

This specification covers normalization behavior for:

- HTML
- EPUB
- DOCX

This specification does not define lossy extracted-text families such as PDF or flattened RTF.

## Behavior

The markup/archive normalization branch must define:

- common structural-preservation behavior for markup-backed families
- HTML-family normalization rules
- EPUB-family normalization rules
- DOCX-family normalization rules

## Constraints

- markup/archive normalization must not flatten explicit structure into plain text unless degradation is required
- archive traversal and chapter/entry ordering must remain deterministic
- any structural downgrade must surface through diagnostics

## Refinement Status

This specification requires further refinement.

## Child Specifications

- [Markup and Archive Common Structural Normalization](markup-and-archive-common-structural-normalization.md)
- [HTML Document Normalization](html-document-normalization.md)
- [EPUB Document Normalization](epub-document-normalization.md)
- [DOCX Document Normalization](docx-document-normalization.md)

## Acceptance

- Markup/archive normalization work is fully represented by focused child specifications.
- No oversized common, HTML, EPUB, or DOCX normalization work remains hidden in one leaf.
