# Document Identity Outside Reading Surface

Status: final

## Overview

This specification defines how the current document identity is surfaced without taking space away from the readable content pane.

## Backlink

Parent specification:

- [Primary Reader Surface UI](primary-reader-surface-ui.md)

## Scope

This specification covers:

- removal of oversized document-title chrome from the reading surface
- placement of document identity outside the reading pane
- preferred window-title form for file-backed documents

## Behavior

The running app must not place a large document-title banner inside the reading surface when that banner reduces the visible reading area or causes follow-along highlighting to disappear beneath it.

Document identity should instead be surfaced outside the reading surface itself.

For the current shell, the preferred placement is the window or frame title.

When the current document is file-backed, the preferred title form is:

- `Read Aloud - <document file name>`

When the current content is not file-backed, the app may fall back to the best available document title, but that fallback still must not reintroduce a large embedded title block into the reading pane.

The reading surface should therefore begin with readable content rather than a decorative title section.

## Constraints

- document identity must remain available somewhere in the shell
- the chosen placement must not compete with the follow-along reading surface for vertical space
- the solution must preserve room for the top highlighted region to remain visible

## Acceptance

- the running app no longer shows a large document-title banner inside the reading surface
- document identity is still available outside the reading surface
- file-backed documents can be identified by file name in the shell chrome rather than by a content-pane header
