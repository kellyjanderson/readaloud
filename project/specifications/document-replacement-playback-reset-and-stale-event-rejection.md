# Document Replacement Playback Reset And Stale Event Rejection

Status: final

## Overview

This specification defines how the Reader must reset playback state when a new document replaces the current one, and how stale runtime events from the prior document must be rejected.

Issue anchor:

- GitHub issue `#34`

## Backlink

Parent specification:

- [Imported Document Playback](imported-document-playback.md)

## Scope

This specification covers:

- replacing the active document while playback or buffering is underway
- rejecting stale progress, completion, and status effects from the prior document after replacement
- preventing duplicate audio or highlight drift when the user loads another document

## Behavior

When the active document is replaced, the Reader must treat the previous playback session as invalid immediately.

After replacement:

- prior-document progress events must not mutate the new document state
- prior-document highlight mapping must not move the new document selection
- prior-document completion or failure effects must not overwrite the new document's playback state
- the new document must start from a clean playback state unless a deliberate resume rule for that same document applies

If the runtime emits progress or status carrying a document identity that does not match the active document, the Reader must ignore it.

If the runtime emits a late lifecycle event from the prior playback after document replacement, the Reader must prefer the current document state over the stale event and must not surface duplicate-audio or jumped-highlight behavior.

Replacing a document must not create a state where the Reader appears to have loaded one document while progress, highlight motion, or audio are still owned by the prior document.

## Constraints

- document replacement must remain safe even while buffering or actively playing
- stale event rejection must prefer preserving the new document state over replaying prior lifecycle assumptions
- this behavior must work for startup-restored documents and manually opened documents

## Acceptance

- if the user loads a new document while the prior document was buffering or playing, the new document does not inherit stale highlights or duplicate audio from the prior one
- late progress from the prior document does not move highlight state in the newly loaded document
- late completion from the prior document does not incorrectly mark the new document complete or paused
- the running app can replace a restored document with a manually opened document without echoing, doubled playback, or erratic highlight jumps
