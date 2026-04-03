# Boundary-Corrected Chunk Output and Reuse

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines what becomes final after boundary correction and how corrected chunks are reused.

## Backlink

Parent specification:

- [Synthesis Boundary Policy](synthesis-boundary-policy.md)

## Scope

This specification covers:

- corrected chunk finalization
- cacheability of corrected output
- player-gap interaction rules
- reuse behavior for replay and export

This specification does not define the general generated-audio cache layout.

## Behavior

### Finalization Rule

Boundary-corrected chunk audio is the finalized playback-ready output.

### Cache Rule

- corrected chunk audio is the cacheable output
- replay and reuse should consume corrected chunks, not rerun join correction by default
- export must also consume corrected finalized chunks rather than pre-correction audio

### Player Gap Rule

The playback queue must not insert blind fixed gaps on top of chunk audio already finalized by boundary policy.

### Metadata Rule

Before/after correction metadata must remain available through sidecars or equivalent cached metadata so evaluation and debugging can inspect:

- whether correction was applied
- boundary class
- leading silence before and after
- trailing silence before and after
- combined join silence before and after

## Constraints

- corrected chunks must be treated as final playback assets for the active engine/voice/rate/cache key
- correction metadata must not require audio regeneration to be inspected later
- finalized output semantics must remain consistent across playback and export

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Boundary correction produces a finalized chunk output that can be reused directly.
- Replay and export share the same corrected audio truth.
- Player behavior does not stack new fixed gaps on top of already corrected chunk audio.
