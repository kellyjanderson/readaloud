# Engine Intent Translation Policy

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines how internal speech intent is translated into the active engine when the engine cannot directly express every annotation type.

## Backlink

Parent specification:

- [Voice and Session Realization](voice-session-realization.md)

## Scope

This specification covers:

- translation outcome categories
- best-effort handling for unsupported intent
- Kokoro-specific initial policy

## Behavior

### Translation Outcome Categories

Every realized speech-intent item must resolve to one of:

- `direct`
- `approximated`
- `deferred`
- `ignored`

### Outcome Meanings

- `direct`: the engine can express the intent explicitly
- `approximated`: the engine cannot express it directly, but the app can steer behavior indirectly
- `deferred`: the intent is preserved for future capabilities but not expressed now
- `ignored`: the intent is not carried forward because it is out of scope for the current engine and product slice

### Initial Kokoro Policy

For Kokoro in the first implementation round:

- pronunciation overrides are `direct`
- chunk-boundary intent is `approximated` through chunk planning and boundary policy
- emphasis hints are `approximated`
- synchronization marks are `deferred`
- unsupported deep narrator-style controls are `deferred`

## Constraints

- Unsupported engine controls must not erase internal speech intent from the model.
- Translation outcomes must be deterministic for the same engine and input.
- Engine adapters must not pretend direct support where only approximation exists.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The realization layer can classify internal intent as direct, approximated, deferred, or ignored.
- Kokoro-specific handling is explicit instead of implicit or hand-waved.
