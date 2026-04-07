# Remembered Reading Position And Startup Resume

Status: final

## Overview

This specification defines how the app remembers the user's last heard position in a file-backed document and restores that position when the document is reopened automatically.

## Backlink

Parent specification:

- [Reader Session Continuity And Live Input](reader-session-continuity-and-live-input.md)

## Scope

This specification covers:

- persisting the last heard reading position for the active file-backed document
- restoring that position when the remembered document is reopened on startup
- best-effort recovery when the source document has changed

## Behavior

While a file-backed document is active, the app must persist enough resume information to recover the user's last heard position in that document.

The remembered resume state should be derived from playback progress rather than only from scroll position.

The persisted resume state must be associated with the remembered file-backed document and should include enough normalized identity or anchor information to attempt best-effort recovery after re-import.

When the app restores the remembered file-backed document on startup, it should also restore the current reading position to the remembered last-heard point before the user presses play again.

If the source document has changed and the exact prior position is no longer recoverable, the app should recover to the nearest safe mapped position when possible.

If no trustworthy recovery is possible, the app may fall back to the beginning of the document and surface a nonfatal status rather than silently pretending the old position was restored.

## Constraints

- remembered resume state must be tied to file-backed document identity, not only to transient in-memory session ids
- resume recovery must reuse normalized mapping and playback-position primitives rather than inventing a second position system
- persistence must remain best-effort and must not block document restore

## Acceptance

- a user can listen to part of a file-backed document, close the app, reopen it later, and find that same document restored near the last heard position in the running app
- startup resume is based on remembered playback position rather than only visual scroll position
- if exact recovery is not possible because the source changed, the app recovers safely or falls back explicitly instead of silently losing state
