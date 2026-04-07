# Test Specification: Remembered Reading Position And Startup Resume

Status: final

## Overview

This test specification defines verification for restoring the user's last heard reading position when a remembered document is reopened.

## Backlink

Feature specification:

- [Remembered Reading Position And Startup Resume](../specifications/remembered-reading-position-and-startup-resume.md)

## Manual Smoke Check

1. Play partway into a long document.
2. Close the app and relaunch it.
3. Confirm the remembered document reopens near the last heard position rather than restarting from the beginning.

## Automated Smoke Tests

- Persist a resume state from playback progress and verify it reloads on startup.
- Reopen the remembered document and verify the restored controller state uses the saved position.
- Verify absent or invalid resume state falls back safely.

## Automated Acceptance Tests

- Verify the restored position is derived from actual heard progress rather than the most recently displayed block alone.
- Verify startup resume lands near the saved reading location even after app restart.
- Verify resume state is discarded or safely downgraded when the saved location cannot be mapped in the reopened document.
- Verify changing to a new document updates the stored resume target so stale progress is not applied to the wrong file.

## Notes

- Use deterministic progress fixtures and persisted resume snapshots in tests.
