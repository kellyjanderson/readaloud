# Watched-File Session Refresh

Status: final

## Overview

This specification defines the core watched-file refresh behavior used by live input inside the running app.

## Backlink

Parent specification:

- [Reader Session Continuity And Live Input](reader-session-continuity-and-live-input.md)

## Scope

This specification covers:

- selecting a watched file as the live input source
- re-importing that file through the normal importer stack
- replacing only the current document state inside the running app
- remaining active when the watched file disappears temporarily

## Behavior

The app must allow the user to select a readable file and turn it into a watched live input source for the current running session.

Starting live input must:

- normalize and persist the selected path as the current remembered file-backed document
- import the file through the same importer stack used for ordinary file loads
- replace only the current document state inside the running app
- start a watch on the selected file's parent directory

When the watched file changes, the app must debounce rapid filesystem events briefly and then re-import only that file into the current reader session.

The app must not restart or reload the full Flutter process.

If the watched live-input file disappears temporarily, the app should remain in live-input mode and surface that it is waiting for the file to reappear.

## Constraints

- watched-file refresh must reuse the normal importer path rather than a special parser shortcut
- this leaf defines file-based local live input only; pipes, sockets, and process-restart behavior remain out of scope

## Acceptance

- a watched file can refresh the current document inside the running app without restarting the app
- live-input refresh uses the same importer behavior as ordinary file loading
- temporary file disappearance does not silently disable live-input mode
