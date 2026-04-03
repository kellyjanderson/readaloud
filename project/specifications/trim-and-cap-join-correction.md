# Trim-and-Cap Join Correction

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines the default correction algorithm for noninitial chunk joins.

## Backlink

Parent specification:

- [Synthesis Boundary Policy](synthesis-boundary-policy.md)

## Scope

This specification covers:

- noninitial join correction
- trim-and-cap behavior
- combined-join-silence handling

This specification does not define initial/resumed chunk startup semantics.

## Behavior

### Default Strategy

The default join strategy is trim-and-cap.

The first implementation round must not use overlap or crossfade as the standard join method.

### Required Noninitial Join Steps

For a noninitial join:

1. measure trailing silence from the previous chunk
2. measure leading silence from the current chunk
3. trim pathological leading silence from the current chunk
4. cap combined join silence according to `boundaryClass`
5. preserve stronger paragraph and section joins

### Combined Join Rule

- the correction algorithm operates on the sum of previous trailing silence and current leading silence
- stronger boundary classes preserve more silence budget than weaker ones
- the algorithm may trim leading silence from the current chunk, but it must not fabricate extra silence to satisfy a boundary class

### Determinism Rule

For the same chunk pair, measurement input, and boundary class:

- correction must produce the same corrected result
- correction must produce the same before/after silence metadata

## Constraints

- correction must not require re-synthesis of the chunk
- correction must not depend on player timing behavior
- trim-and-cap correction must remain compatible with cached finalized chunk output

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Noninitial joins can be corrected through one explicit trim-and-cap algorithm.
- Combined join silence is controlled without overlap or crossfade as the default strategy.
- Correction behavior is deterministic and reusable.
