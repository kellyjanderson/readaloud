# First-Chunk Startup Contract

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines the startup contract for the first user-visible playback action on an imported document.

## Backlink

Parent specification:

- [Imported Document Playback](imported-document-playback.md)

## Scope

This specification covers:

- what playback may wait for before audio starts
- where startup activity is surfaced
- how later chunks relate to the first startup path

This specification does not define the transport state machine in full.

## Behavior

### Startup Dependency Rule

Playback startup may depend on only:

- the active realization window
- first-chunk preparation

Playback startup must not depend on:

- whole-document voice-specific preprocessing
- whole-document synthesis preparation
- later-chunk readiness

### First Audio Rule

- the first user-visible play action may wait only for first-chunk preparation
- playback begins as soon as the first chunk is ready
- later chunks must prepare behind playback

### Startup Feedback Rule

- the play control is the primary place where initial buffering is shown
- normal startup must not depend on a broad global warning banner

## Constraints

- startup behavior must remain compatible with cached first-chunk reuse
- startup behavior must not block on background preparation for later chunks
- startup feedback must stay scoped to the transport experience unless a genuine failure occurs

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Imported playback starts from first-chunk readiness rather than whole-document preparation.
- Later chunk work stays behind active playback.
- Startup feedback is scoped to the transport, not a generic warning surface.
