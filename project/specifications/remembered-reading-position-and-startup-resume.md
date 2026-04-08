# Remembered Reading Position And Startup Resume

Status: final

## Overview

This specification defines how the app remembers the user's last heard position in a file-backed document and restores that position when the document is reopened automatically.

Issue anchor:

- GitHub issue `#35`
- GitHub issue `#42`

## Backlink

Parent specification:

- [Reader Session Continuity And Live Input](reader-session-continuity-and-live-input.md)

## Scope

This specification covers:

- persisting the last heard reading position for the active file-backed document
- restoring that position when the remembered document is reopened on startup
- best-effort recovery when the source document has changed
- aligning the visible reader surface to the restored position before the user presses play again

## Behavior

While a file-backed document is active, the app must persist enough resume information to recover the user's last heard position in that document.

The remembered resume state should be derived from playback progress rather than only from scroll position.

The persisted resume state must be associated with the remembered file-backed document and should include enough normalized identity or anchor information to attempt best-effort recovery after re-import.

When the app restores the remembered file-backed document on startup, it should also restore the current reading position to the remembered last-heard point before the user presses play again.

On platforms that require persistent restore access beyond a plain stored path, startup resume depends on the remembered document being reopened through that persisted access mechanism first.

When startup restore succeeds, the visible reader surface must align near that restored point rather than leaving the user at a contradictory viewport while playback resumes from somewhere else.

If the source document has changed and the exact prior position is no longer recoverable, the app should recover to the nearest safe mapped position when possible.

If no trustworthy recovery is possible, the app may fall back to the beginning of the document.

For automatic startup restore, a degraded non-actionable outcome such as "document reopened, but exact last-heard position could not be recovered" should prefer diagnostics or debug logging over a surfaced Reader toast when the user cannot meaningfully fix that state from the message alone.

If the same degraded outcome is surfaced in a more explicit user-triggered restore flow later, the message must describe that degraded outcome precisely rather than implying that full restore already happened.

Startup restore success should not be surfaced as a celebratory load message by default. If the restore result is not visibly aligned or the last-heard position could not be recovered, the surfaced feedback must describe that degraded outcome precisely instead of implying that full restore already happened.

If startup restore fails in a way that is not user-actionable and the user can still recover by opening the document normally, that failure may remain in diagnostics rather than being surfaced as a primary Reader toast.

## Constraints

- remembered resume state must be tied to file-backed document identity, not only to transient in-memory session ids
- resume recovery must reuse normalized mapping and playback-position primitives rather than inventing a second position system
- persistence must remain best-effort and must not block document restore

## Acceptance

- a user can listen to part of a file-backed document, close the app, reopen it later, and find that same document restored near the last heard position in the running app
- when startup restore succeeds, the visible reading surface is aligned near the restored point before playback begins
- startup resume is based on remembered playback position rather than only visual scroll position
- if exact recovery is not possible because the source changed, the app recovers safely or falls back explicitly instead of silently losing state
