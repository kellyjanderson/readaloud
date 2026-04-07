# Reader Session Continuity And Live Input

Last updated: April 4, 2026
Status: Draft specification

## Overview

This specification refines file-backed reader continuity and watched-file live input into executable leaves.

## Backlink

Parent specification:

- [Imported Document Playback](imported-document-playback.md)

## Scope

This specification covers:

- remembering the most recently opened file-backed document
- restoring that document on startup when no explicit startup input is provided
- remembering the reader's last heard position for that document
- watched-file live input refresh inside the running app

Visible menu placement and playing-versus-paused continuation semantics for live input are refined separately by:

- [Live Input And File Menu UI](live-input-and-file-menu-ui.md)

## Behavior

The parent branch now delegates detailed continuity and live-input work to child specifications.

In particular:

- file-backed document restore and directory continuity belong to one leaf
- remembered reading position and startup resume belong to one leaf
- watched-file session refresh belongs to one leaf

This parent specification keeps only the branch-level contract that the app should preserve continuity for file-backed reading sessions rather than dropping the user back into sample content or the top of the document by default.

## Constraints

- continuity behavior must reuse the normal importer path rather than a special parser shortcut
- remembered resume state must remain best-effort and must not block startup indefinitely
- watched-file live input must refresh the running session without restarting the Flutter process

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [File-Backed Document Restore And Directory Continuity](file-backed-document-restore-and-directory-continuity.md)
- [Remembered Reading Position And Startup Resume](remembered-reading-position-and-startup-resume.md)
- [Watched-File Session Refresh](watched-file-session-refresh.md)

## Acceptance

- the remaining continuity and live-input work is represented by final leaf specifications
- the running app has an explicit leaf for reopening the most recent file-backed document at the user's last heard position
