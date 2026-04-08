# Document-Specific Cast Voice Assignment Memory

Status: final

## Overview

This specification defines how narrator and character voice assignments are remembered for one document and restored when that same document is reopened later.

## Backlink

Parent specification:

- [Character Cast Registry and Voice Assignment](character-cast-registry-and-voice-assignment.md)

## Scope

This specification covers:

- persisting explicit narrator and character voice choices for one document
- restoring those stored choices when the same document is reopened
- interaction between stored document choices and session-only user overrides

## Behavior

When a user explicitly assigns a narrator or character voice for a document, the app must persist that choice as a document-specific cast assignment.

The persistence key must be tied to the app-owned normalized document identity rather than only transient playback session state.

When the same document is reopened later, the app must restore those document-specific cast assignments before playback begins, so the resolved narrator and character voices match the user’s previous choices when the referenced voices are still available.

Stored document-specific cast assignments must resolve with this precedence:

1. session-local user override made in the current run
2. stored document-specific cast choice from earlier runs
3. automatic cast assignment
4. narrator/default fallback

If a stored voice is no longer available, the app must ignore that stored choice and continue with normal automatic or fallback resolution rather than surfacing a fatal error.

Clearing an explicit assignment back to automatic must remove the stored document-specific choice for that cast role.

## Constraints

- document-specific cast memory must not depend on live playback being active
- stored choices must remain keyed by stable normalized document identity
- restoring stored cast choices must not require redoing speaker inference differently from the normal import path

## Acceptance

- a user can assign narrator and character voices for a document, close the app, reopen that same document later, and observe those assignments restored
- clearing an assignment returns that cast role to automatic behavior and removes the stored document-specific choice
- unavailable stored voices are skipped safely without breaking document reopen
