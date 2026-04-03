# Boundary Silence Thresholds

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the first implementation round of silence caps used by the synthesis-boundary policy.

## Backlink

Parent specification:

- [Synthesis Boundary Policy](synthesis-boundary-policy.md)

## Scope

This specification covers:

- combined join-silence caps
- pathological leading-silence threshold
- initial and resumed chunk opening caps

## Behavior

### Pathological Leading Silence

For noninitial joins, leading silence is considered pathological when it exceeds `180ms`.

### Combined Join Silence Caps

The first implementation round must cap total join silence to:

- `none`: `60ms`
- `weak`: `120ms`
- `sentence`: `240ms`
- `paragraph`: `420ms`
- `section`: `650ms`

### Initial and Resumed Chunk Opening Cap

For `isInitialChunk` or `isResumedChunk`:

- cap leading opening silence at `120ms`

### Trim Rule

If noninitial leading silence exceeds the class-specific remaining budget after considering previous trailing silence:

- trim current leading silence down to the available budget
- never trim below `20ms` unless the class is `none`

## Constraints

- Thresholds are initial product heuristics, not claims about linguistic perfection.
- Threshold application must be deterministic.
- Future tuning must happen by revising this specification rather than hidden code changes.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The boundary policy has explicit initial thresholds for each join class.
- Overlong joins can be corrected consistently without ad hoc hard-coded values scattered through code.
