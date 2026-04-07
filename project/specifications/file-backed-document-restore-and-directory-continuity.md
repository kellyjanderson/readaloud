# File-Backed Document Restore And Directory Continuity

Status: final

## Overview

This specification defines how the app remembers the most recently opened file-backed document and restores it on startup.

## Backlink

Parent specification:

- [Reader Session Continuity And Live Input](reader-session-continuity-and-live-input.md)

## Scope

This specification covers:

- remembering the last opened file-backed document path
- remembering the last opened directory for file selection
- restoring the remembered document on startup when no explicit startup input is present

## Behavior

When a readable file-backed document is loaded through the normal open flow or live-input file selection, the app must persist:

- the normalized absolute document path
- the parent directory path when available

Sample content and pasted or shared text must not replace the remembered file-backed document path.

When the interactive app starts without an explicit startup input file, it should attempt to restore the last remembered file-backed document.

If restoration fails or the file no longer exists, the app may keep the current sample or default document and surface a nonfatal status.

Interactive file selection should use the remembered directory as the initial directory when the platform picker supports it.

## Constraints

- remembered file continuity must remain best-effort
- ordinary document restore must not depend on remembered playback position being recoverable

## Acceptance

- the app remembers the most recently opened file-backed document
- the app remembers the last used directory for file selection
- when the app starts without an explicit file input, it restores the remembered file-backed document in the running app when available
