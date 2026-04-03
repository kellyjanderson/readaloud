# Engine Pronunciation Translation Policy

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines how an engine adapter translates realized pronunciation artifacts into engine-usable behavior.

## Backlink

Parent specification:

- [TTS Artifact Consumption Contract](tts-artifact-consumption-contract.md)

## Scope

This specification covers:

- direct expression of realized pronunciation artifacts
- approximation behavior when an engine lacks exact controls
- deferred behavior when an engine must fall back to default tokenization

This specification does not define audio playback or queue control.

## Behavior

### Translation Outcomes

The first implementation round must support these stable outcomes:

- `direct`
- `approximated`
- `deferred`

### Direct Rule

If an engine can directly express a realized pronunciation representation, the adapter must preserve that representation in the translated chunk payload or adjacent engine-side translation state.

### Approximation Rule

If an engine cannot directly express the full representation but can preserve some pronunciation intent, the adapter may approximate it.

Approximated behavior must remain distinguishable from direct translation.

### Deferred Rule

If an engine cannot reliably express the representation, the adapter may defer to engine-default behavior.

Deferred behavior must remain distinguishable from both direct and approximated translation.

### Current-Engine Rule

For the current Kokoro path, tokenization and lexical handling may still remain partly engine-driven.

That is acceptable only if the adapter treats this as a translation stage applied to prepared artifacts, not a replacement for planner ownership.

## Constraints

- translation behavior must not silently erase planner decisions
- translation outcomes must remain observable per realized pronunciation artifact
- adapter translation must not rewrite canonical stored pronunciation artifacts

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The adapter has explicit direct, approximated, and deferred translation outcomes.
- Engine limitations no longer hide whether planner intent was used or bypassed.
- The engine path consumes realized pronunciation artifacts as input rather than inventing pronunciation policy independently.
