# Boundary Intent Realization

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines how document-time pause and phrase intent become active-session boundary intent during realization.

## Backlink

Parent specification:

- [Voice and Session Realization](voice-session-realization.md)

## Scope

This specification covers:

- realization of `phrase_boundary` and `pause_candidate` annotations
- the active-session boundary intent carried forward toward chunk planning and boundary policy
- best-effort handling for engines that cannot express break strength directly

This specification does not define silence-threshold numbers or finalized chunk-audio correction.

## Behavior

### Input Rule

Boundary-intent realization consumes:

- `phrase_boundary` annotations
- `pause_candidate` annotations
- the active realization window
- current `NarrationState`

### Output Rule

The active realization output must preserve, per affected segment/range:

- the relevant boundary class
- whether the boundary came from phrase-level inference or pause-level inference
- whether the intent is expected to be direct, approximated, deferred, or ignored for the active engine

The first implementation round may carry this information through segment-scoped realization diagnostics or TTS-artifact sidecars instead of a standalone dedicated boundary-hint collection, as long as the information remains inspectable and traceable.

### Precedence Rule

If both `phrase_boundary` and `pause_candidate` exist at the same boundary:

- `pause_candidate` remains the stronger playback-oriented interpretation
- `phrase_boundary` remains available for chunk-planning preference and future prosody modeling

### Engine Rule

For engines such as Kokoro that do not expose rich direct break controls:

- sentence/paragraph/section intent is primarily approximated through chunk planning and synthesis-boundary handling
- weaker phrase intent may remain preserved internally even when not directly expressed

## Constraints

- boundary-intent realization must remain traceable to normalized segment ids and word boundaries
- realization must not replace deterministic chunk-boundary policy with ad hoc player gaps
- realized boundary intent must stay separate from measured audio silence

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Document-time pause and phrase annotations have an explicit active-session realization contract.
- The system can carry boundary intent forward even when the engine cannot express it directly.
- Boundary intent remains distinguishable from final synthesized silence behavior.
