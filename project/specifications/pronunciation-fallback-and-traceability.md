# Pronunciation Fallback and Traceability

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines how runtime and engine paths handle missing or non-expressible pronunciation artifacts while preserving traceability.

## Backlink

Parent specification:

- [TTS Artifact Consumption Contract](tts-artifact-consumption-contract.md)

## Scope

This specification covers:

- fallback behavior when no resolved pronunciation artifact exists
- fallback behavior when an artifact exists but cannot be translated directly
- required traceability surfaces for runtime and export

This specification does not define general playback instrumentation.

## Behavior

### Missing-Artifact Rule

If a token range has no realized pronunciation artifact, runtime preparation may fall back to engine-default behavior.

This case must remain distinguishable from a token range that had a realized artifact and was translated.

### Unresolved-Artifact Rule

If a realized pronunciation artifact is explicitly unresolved, runtime preparation must preserve that unresolved status through to runtime/export traceability instead of collapsing it into a silent engine default.

### Translation-Fallback Rule

If a realized artifact exists but is approximated or deferred during engine translation, the resulting traceability output must retain:

- the original artifact id
- the translation outcome
- any stable pronunciation diagnostic codes already attached to that artifact

### Export/Headless Rule

Export and headless sidecars must include enough pronunciation traceability to distinguish:

- direct artifact use
- approximated artifact use
- deferred artifact handling
- unresolved artifact presence
- missing-artifact engine fallback

## Constraints

- fallback behavior must not be represented as if it were a positively chosen pronunciation resolution
- traceability must remain stable enough for regression-oriented QA

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Missing, unresolved, approximated, and deferred pronunciation cases remain distinguishable.
- Engine fallback no longer appears identical to successful planner-driven pronunciation handling.
- Runtime/export traces preserve artifact identity and fallback class clearly enough for QA.
