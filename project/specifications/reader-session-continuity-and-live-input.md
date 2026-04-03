# Reader Session Continuity and Live Input

Last updated: April 3, 2026
Status: Final specification

## Overview

This specification defines file-backed reader continuity across app launches and the watched-file live input mode used to refresh a running reader session without restarting the app.

## Backlink

Parent specification:

- [Imported Document Playback](imported-document-playback.md)

## Scope

This specification covers:

- remembering the last opened file-backed document path
- remembering the last opened directory for file selection
- restoring the remembered file-backed document on startup when no explicit launch input is present
- watched-file live input behavior inside the running app

This specification does not define pronunciation behavior, headless probe harnesses, or audio export.

## Behavior

### Remembered-Document Rule

When a readable file-backed document is loaded through the normal open flow or live-read file selection, the app must persist:

- the normalized absolute document path
- the parent directory path when available

Sample content and pasted/shared text must not replace the remembered file-backed document path.

### Startup-Restore Rule

When the interactive app starts without an explicit startup input file, it should attempt to restore the last remembered file-backed document.

If restoration fails or the file no longer exists, the app may keep the current sample or default document and surface a nonfatal status.

### Initial-Directory Rule

Interactive file selection should use the remembered directory as the initial directory when the platform picker supports it.

### Live-Read Activation Rule

The app must allow the user to select a readable file and turn it into a watched live input source for the current running session.

Starting live read must:

- normalize and persist the selected path as the current remembered file-backed document
- import the file through the same importer stack used for ordinary file loads
- replace only the current document state inside the running app
- start a watch on the selected file's parent directory

### Live-Read Reload Rule

When the watched file changes, the app must debounce rapid filesystem events briefly and then re-import only that file into the current reader session.

The app must not restart or reload the full Flutter process.

### Live-Read Playback Interaction Rule

If live-read reload replaces the active document while playback or buffering is in progress, the controller may stop current playback and reset playback state before loading the updated document.

### Missing-File Rule

If the watched live-read file disappears temporarily, the app should remain in live-read mode and surface that it is waiting for the file to reappear.

## Constraints

- File-backed continuity and live-read behavior must reuse the normal importer path rather than a special parser shortcut.
- Live-read mode is file-based and local; it does not require pipes, sockets, or process restart behavior in `v1`.
- Remembered-document behavior must remain best-effort and must not block startup indefinitely.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app remembers the last opened file-backed document and the last used directory.
- UI startup can restore the remembered file-backed document when no explicit input file is provided.
- A watched file can refresh the current document inside the running app without restarting the app.
- Live-read reload uses the same importer behavior as ordinary file loading.
