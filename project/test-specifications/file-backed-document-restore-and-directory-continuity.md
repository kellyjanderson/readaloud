# Test Specification: File-Backed Document Restore And Directory Continuity

Status: final

## Overview

This test specification defines verification for remembering the last file-backed document and the last used open-directory context.

## Backlink

Feature specification:

- [File-Backed Document Restore And Directory Continuity](../specifications/file-backed-document-restore-and-directory-continuity.md)

## Manual Smoke Check

1. Open a file-backed document from a chosen directory.
2. Close and relaunch the app.
3. Confirm the app attempts to restore the last document and that later open-document flows start from the last used directory.

## Automated Smoke Tests

- Save last-document and last-directory state and verify it reloads on app startup.
- Verify missing prior state yields a clean empty startup rather than an exception.
- Verify changing documents updates the stored path and directory.

## Automated Acceptance Tests

- Verify the last successfully opened file-backed document becomes the startup restore candidate.
- Verify the app preserves the last used directory independently of whether startup restore succeeds.
- Verify restore failures degrade gracefully without leaving stale in-memory state.
- Verify opening a different file updates both restore target and directory continuity.

## Notes

- Preference-service tests should cover persistence.
- One controller-level test should verify startup behavior uses the persisted values.
