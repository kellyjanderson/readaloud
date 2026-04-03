# Line Wrap and Paragraph Recovery

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the normalization heuristics used to recover paragraphs from plain text and lossy extracted text such as PDF-derived lines.

## Backlink

Parent specification:

- [Importer Normalization Contract](importer-normalization-contract.md)

## Scope

This specification covers:

- line joining
- blank-line paragraph splitting
- preserved hard breaks
- suspicious extraction handling

## Behavior

### Paragraph Split Rules

- one or more blank lines create a paragraph break
- explicit heading lines remain their own blocks
- explicit list markers begin a new list or list item block
- page boundaries remain visible as `pageBreak` display blocks

### Line Join Rules

Within a recovered paragraph:

- adjacent non-empty lines are joined with a single space
- leading and trailing whitespace is trimmed before joining
- repeated internal whitespace collapses to a single space

### Hyphenated Wrap Rule

If a line ends in a trailing hyphen immediately after an alphabetic sequence and the next line begins with a lowercase alphabetic sequence:

- remove the line-ending hyphen
- join the tokens without inserting a space

Otherwise:

- preserve the hyphen and join with normal spacing rules

### Preserved Hard Break Rule

A hard line break should remain explicit only when there is strong structural evidence, such as:

- poetry or verse mode already identified by the importer
- code blocks
- explicit source block boundaries

Plain visual wraps must not become hard speech breaks by default.

### Suspicious Reading-Order Rule

If extracted line ordering appears inconsistent with a plausible reading order:

- preserve the best available extracted order
- emit `reading_order_suspect`
- do not invent a more aggressive reorder pass in `v1`

## Constraints

- Recovery rules must remain deterministic.
- Heuristics must prefer conservative repair over aggressive restructuring.
- The recovery pass must remain lightweight enough for the document-open path.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Plain text and extracted line content can be normalized into paragraphs without relying on voice-specific logic.
- Typical visual line wraps do not become artificial speech pauses.
- Suspicious reading-order cases remain diagnosable instead of silently overcorrected.
