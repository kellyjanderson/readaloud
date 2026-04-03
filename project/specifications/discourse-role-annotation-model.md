# Discourse Role Annotation Model

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines how document-time discourse-role annotations describe the local speech mode of normalized content.

## Backlink

Parent specification:

- [Speech Annotation Set](speech-annotation-set.md)

## Scope

This specification covers:

- `discourse_role` annotations
- the first-round discourse-role vocabulary
- segment-scope rules for discourse roles

This specification does not define `NarrationState`, though `NarrationState` may consume these annotations.

## Behavior

### Annotation Kind

`discourse_role` marks the local delivery mode implied by a segment or segment-scoped range.

### First-Round Role Vocabulary

The first implementation round must support:

- `heading`
- `narration`
- `quotation`
- `dialogue`
- `list_item`
- `caption`

### Scope Rule

- a discourse-role annotation normally spans the full segment
- the first implementation round may treat discourse role as one dominant role per segment
- if a later importer exposes stronger source metadata, narrower ranges may be added without changing the role vocabulary

### Inference Rule

Discourse-role inference may use:

- display block kind
- quotation structure
- list structure
- imported source metadata

### Consumer Rule

- voice/session realization may use discourse role to influence pronunciation, rate-sensitive realization, and narration continuity
- playback and export must be able to inspect the role chosen for a segment

## Constraints

- discourse roles must remain engine-agnostic
- discourse roles must not rewrite normalized speech text
- discourse roles must stay stable across voice changes for the same normalized document version

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app has a stable document-time vocabulary for local speech mode.
- Segment-level delivery context can flow into realization and narration continuity without being re-inferred from raw text every time.
- Heading, quotation, dialogue, list, caption, and ordinary narration are distinguishable as internal discourse roles.
