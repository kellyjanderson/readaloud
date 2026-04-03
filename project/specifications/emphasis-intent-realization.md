# Emphasis Intent Realization

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines how document-time emphasis candidates become active-session emphasis intent during realization.

## Backlink

Parent specification:

- [Voice and Session Realization](voice-session-realization.md)

## Scope

This specification covers:

- realization of `emphasis_candidate` annotations
- active-session emphasis intent
- translation-outcome handling for engines with limited direct emphasis controls

This specification does not define deep narrator-style prosody modeling.

## Behavior

### Input Rule

Emphasis-intent realization consumes:

- `emphasis_candidate` annotations
- local segment text and neighboring context
- `NarrationState`
- active voice, rate, engine, and pronunciation profile

### Output Rule

The active realization output must preserve, per affected word range:

- the emphasized range
- emphasis confidence carried forward or normalized for the active session
- whether the active engine treatment is `direct`, `approximated`, `deferred`, or `ignored`

The first implementation round may carry this through segment-scoped diagnostics or TTS-artifact sidecars rather than a dedicated standalone emphasis collection, as long as the intent remains inspectable.

### Engine Rule

For Kokoro in the first implementation round:

- emphasis intent is normally `approximated`
- realization may influence chunk boundaries, normalized spoken text choice, or other indirect cues where appropriate
- realization must not claim direct emphasis control where the engine does not expose it

### Continuity Rule

Realization may use `NarrationState.recentEmphasisDensity` and nearby context to avoid isolated sentence-reset emphasis behavior.

## Constraints

- emphasis intent must remain traceable to normalized segment ids and word ranges
- emphasis realization must stay engine-agnostic until translation outcomes are assigned
- the first implementation round must preserve emphasis intent even when direct acoustic control is unavailable

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Document-time emphasis candidates have an explicit active-session realization contract.
- The app can preserve and inspect emphasis intent even when the active engine only supports approximation.
- Emphasis realization remains separate from pronunciation resolution and from raw UI state.
