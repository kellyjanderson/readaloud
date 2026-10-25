# Cast Voice Override Workflow

## Architecture ownership

- [character dialogue attribution and voice casting](../architecture/character-dialogue-attribution-and-voice-casting.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Status: final

## Overview

This specification defines the user-observable workflow for changing narrator and character voices and seeing those overrides take effect in playback.

## Backlink

Historical specification lineage:

- [Character Cast Registry and Voice Assignment](../archive/specification-ancestors/character-cast-registry-and-voice-assignment.md)

## Scope

This specification covers:

- selecting narrator or character voice overrides from the running app
- visible override state
- restoring automatic assignment
- subsequent playback using the chosen override

## Behavior

The running app must allow the user to change the assigned voice for:

- narrator
- detected characters
- unattributed dialogue fallback when that role exists

Changing an assignment from the advanced voice-management surface must create a user override that is visible in the UI.

The app must allow the user to distinguish:

- automatic assignment
- explicit user override

The app must also allow the user to clear an override and return that role to automatic assignment.

After a user changes an assignment, the next relevant playback for that role must use the overridden voice rather than the automatic choice.

Explicit document-backed assignments must also be remembered for that document when the document is reopened later.

The override workflow may be reached either from:

- the narrator and character assignment rows
- direct assignment controls in the voice library when character mode is active

## Constraints

- override actions must operate on stable cast roles, not ephemeral utterances
- override state must remain separate from speaker-attribution confidence
- restoring automatic assignment must be explicit rather than requiring document reload

## Acceptance

- a user can change narrator or character voice assignments from the running app
- override state is visibly distinguishable from automatic state
- subsequent playback uses the overridden voice for the affected role
- a user can restore automatic assignment and observe that state change in the running app
