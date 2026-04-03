# Pronunciation Realization Precedence

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the precedence order used when multiple pronunciation sources could apply to the same text.

## Backlink

Parent specification:

- [Voice and Session Realization](voice-session-realization.md)

## Scope

This specification covers:

- pronunciation source precedence
- accent matching
- conflict resolution

## Behavior

### Precedence Order

When multiple pronunciation sources apply to the same normalized span, the system must prefer:

1. explicit user override
2. explicit source-provided pronunciation metadata
3. imported inline phoneme or equivalent explicit markup preserved through normalization
4. document-time pronunciation candidate with matching accent family
5. accent-family dictionary override
6. engine default G2P behavior

### Accent Match Rule

- a candidate with an exact accent-family match outranks an accent-neutral candidate at the same precedence tier
- an accent-mismatched candidate must not outrank an accent-neutral candidate

### Conflict Rule

If two candidates from the same precedence tier and accent tier conflict:

- prefer the one with the higher `priorityHint`
- if still tied, prefer the narrower span

## Constraints

- The chosen pronunciation must remain traceable to its source tier.
- Conflict resolution must be deterministic.
- Falling back to engine-default G2P is valid when no stronger source applies.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app can deterministically choose one pronunciation source when multiple candidates exist.
- User overrides reliably outrank inferred or dictionary-based candidates.
