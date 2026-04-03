# Narration State

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the small symbolic state carried across chunks to reduce sentence-reset behavior and preserve long-form continuity.

## Backlink

Parent architecture:

- [Speech Enrichment and Narration](../architecture/speech-enrichment-and-narration.md)

## Scope

This specification covers:

- `NarrationState`
- reset behavior
- update behavior
- invalidation rules for replay, jump, and voice changes

## Behavior

### Required Type

`NarrationState` must contain:

- `String sessionId`
- `String? currentSectionMode`
- `String? discourseMode`
- `String? recentBoundaryClass`
- `bool continuationPending`
- `double recentEmphasisDensity`
- `double recentRate`
- `String? quoteMode`
- `Map<String, String> localPronunciationChoices`

### Intended Meaning

- `currentSectionMode` tracks high-level content mode such as heading, prose, list, caption, or aside
- `discourseMode` tracks local delivery mode such as narration, dialogue, or quotation
- `recentBoundaryClass` tracks the most recent realized break class
- `continuationPending` is true when the previous realized boundary implies continuation rather than closure
- `recentEmphasisDensity` is a lightweight continuity signal, not a raw acoustic measure
- `recentRate` records the effective realized rate for continuity decisions

### Update Rule

`NarrationState` updates after each finalized chunk using:

- the realized chunk output
- the chunk’s ending boundary class
- any unresolved continuation state

### Reset Rule

`NarrationState` resets when:

- a new document starts playback
- replay begins from the start
- voice changes
- engine changes

### Rebuild Rule

`NarrationState` should rebuild from the new entry point when:

- a 30-second jump moves to a substantially different segment window
- resume starts from a restored mid-document anchor

### Forbidden State

`NarrationState` must not store:

- raw PCM audio history
- speculative model-internal embeddings
- data that cannot survive cache reuse or engine changes

## Constraints

- `NarrationState` must remain serializable
- it must stay small enough to pass through worker and controller boundaries cheaply
- it must remain engine-agnostic

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Playback can carry a symbolic continuity state across adjacent chunks.
- Replay and voice change semantics for state reset are explicit.
- The state remains small, serializable, and independent from model-internal audio state.
