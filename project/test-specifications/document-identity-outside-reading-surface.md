# Test Specification: Document Identity Outside Reading Surface

Status: final

## Overview

This test specification defines verification for keeping document identity outside the reading pane and using the window title for the current file-backed document.

## Backlink

Feature specification:

- [Document Identity Outside Reading Surface](../specifications/document-identity-outside-reading-surface.md)

## Manual Smoke Check

1. Open a file-backed document.
2. Confirm the reading pane starts with content, not a large title banner.
3. Confirm the window title shows `Read Aloud - <document file name>`.

## Automated Smoke Tests

- Render the reader with a file-backed document and assert no in-surface title header is present.
- Verify the window-title state derives from the current file-backed document name.
- Verify non-file-backed content still uses a sane fallback title without throwing.

## Automated Acceptance Tests

- Verify the reading surface top edge is not consumed by a document-title card or banner.
- Verify the highlighted follow-along content cannot disappear under a title treatment inside the reading pane.
- Verify changing documents updates the window title to the newly active file name.
- Verify clearing or replacing the document updates the title state consistently without leaving stale document names behind.

## Notes

- Widget tests should assert absence of the old banner copy as well as presence of the expected window-title state.
