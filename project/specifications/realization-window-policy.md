# Realization Window Policy

## Architecture ownership

- [document speech pipeline](../architecture/document-speech-pipeline.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)
- [system overview](../architecture/system-overview.md)
- [playback orchestration and synthesis boundaries](../architecture/playback-orchestration-and-synthesis-boundaries.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines how much content voice/session realization must cover at a time.

## Backlink

Parent specification:

- [Voice and Session Realization](voice-session-realization.md)

## Scope

This specification covers:

- active realization window size
- look-ahead policy
- invalidation triggers

## Behavior

### Minimum Window

The realization window must cover:

- the current start segment
- enough following segments to satisfy first-chunk planning

### Preferred Look-Ahead

The first implementation round should additionally realize enough content for:

- one chunk beyond the first ready chunk, or
- the remainder of the current paragraph,

whichever is smaller.

### Invalidation Rule

The realization window must be recomputed when:

- the selected voice changes
- the selected rate changes
- the engine changes
- a jump moves playback outside the current realized range

### Non-Invalidating Changes

The realization window must not be recomputed when:

- reader font settings change
- document rendering state changes
- already completed chunk playback metadata changes

## Constraints

- Whole-document realization on play is forbidden.
- The window policy must preserve low first-audio latency.
- Window boundaries must remain aligned to valid speech segments.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Voice/session realization remains scoped to the immediate playback need.
- Voice changes and jumps invalidate only the realized window, not normalized document structure.
