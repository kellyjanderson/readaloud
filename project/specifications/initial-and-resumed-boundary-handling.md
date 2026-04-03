# Initial and Resumed Boundary Handling

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines the special-case boundary behavior for initial playback startup and resumed playback.

## Backlink

Parent specification:

- [Synthesis Boundary Policy](synthesis-boundary-policy.md)

## Scope

This specification covers:

- initial chunk boundary treatment
- resumed chunk boundary treatment
- startup-specific leading-silence handling

This specification does not define the numeric threshold values themselves.

## Behavior

### Initial and Resumed Rule

If `isInitialChunk` or `isResumedChunk` is true:

- no previous-chunk silence contributes to join calculation
- the chunk is treated as a new audible start

### Startup Treatment Rule

- initial and resumed chunks may still have excessive opening silence trimmed according to startup-specific caps
- startup handling must not assume there is a previous playable chunk in memory or cache

### Continuity Rule

- resumed chunks are treated like a fresh audible start for silence calculation
- this does not change playback-session identity or higher-level narration continuity behavior

## Constraints

- startup boundary handling must remain distinct from ordinary noninitial join correction
- resumed-chunk handling must not accidentally reapply previous-trailing silence from an unrelated earlier chunk
- startup handling must remain deterministic for the same measured input

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Initial and resumed chunks have explicit boundary semantics instead of being treated as ordinary joins.
- Startup silence handling does not depend on nonexistent previous-chunk context.
- Resumed playback behaves like a fresh audible start for boundary correction purposes.
