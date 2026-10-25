# Follower Progress Coalescing And Drift Resynchronization

## Architecture ownership

- [spoken text highlighting and reading focus](../architecture/spoken-text-highlighting-and-reading-focus.md)
- [playback orchestration and synthesis boundaries](../architecture/playback-orchestration-and-synthesis-boundaries.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Last updated: April 8, 2026
Status: Final specification

## Overview

This specification defines how visible spoken selection and reader follow-along should behave when the follower side cannot keep pace with the active audio session.

## Backlink

Historical specification lineage:

- [Spoken Text Highlighting and Reading Focus](../archive/specification-ancestors/spoken-text-highlighting-and-reading-focus.md)

## Scope

This specification covers:

- visible spoken-selection update cadence
- dropping or coalescing intermediate follower states
- hard resynchronization when visible state drifts too far behind audio

## Behavior

Spoken-selection and follow-along updates are follower updates behind active audio.

The follower path may:

- coalesce multiple progress events into one visible update
- drop intermediate word-level states when later progress has already arrived
- jump directly to the current audio-mapped position when drift becomes too large

Initial follower policy:

- visible follower updates should not exceed `15` updates per second during ordinary playback
- if visible follower lag exceeds roughly `250` milliseconds of audio progress, the system may skip intermediate visible states
- if the visible region drifts by more than `10` words or by more than one display block, the system may hard-resynchronize to the current mapped audio position

Follower catch-up must not:

- request playback restart
- request queue rebuild
- replay missed highlight states

If the mapping layer temporarily loses precise word confidence, the reader may preserve the last stable state briefly and then resynchronize using segment- or block-level fallback.

## Constraints

- coalescing policy must preserve understandable follow-along behavior
- hard resynchronization must favor current audio truth over historical visual continuity
- follower recovery must remain downstream of normalized mapping rather than ad hoc renderer search

## Acceptance

- the reader surface can skip intermediate visible updates without losing the current spoken region entirely
- visible spoken selection can hard-resynchronize to current audio position when follower drift grows too large
- follower catch-up behavior no longer depends on trying to preserve every intermediate highlight step
