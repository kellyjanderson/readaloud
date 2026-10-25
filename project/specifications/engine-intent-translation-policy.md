# Engine Intent Translation Policy

## Architecture ownership

- [document speech pipeline](../architecture/document-speech-pipeline.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)
- [system overview](../architecture/system-overview.md)
- [engine pronunciation expression and capability adaptation](../architecture/engine-pronunciation-expression-and-capability-adaptation.md)
- [playback orchestration and synthesis boundaries](../architecture/playback-orchestration-and-synthesis-boundaries.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

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
