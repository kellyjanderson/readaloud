# Test Specification: Document-Specific Cast Voice Assignment Memory

Status: final

## Overview

This test specification defines verification for remembering narrator and character voice assignments per document across app restarts.

## Backlink

Feature specification:

- [Document-Specific Cast Voice Assignment Memory](../specifications/document-specific-cast-voice-assignment-memory.md)

## Manual Smoke Check

1. Open a file-backed document with detected characters.
2. Assign explicit narrator and character voices.
3. Close the app.
4. Reopen the app and reopen or restore the same document.
5. Confirm the previous narrator and character assignments are still present and used.

## Automated Smoke Tests

- Persist document-specific cast choices through preferences and verify they decode correctly.
- Reopen the same normalized document identity in controller tests and verify resolved assignments return as stored document choices.
- Clear one stored cast choice and verify that cast role resolves back to automatic selection.

## Automated Acceptance Tests

- Verify narrator and character assignments survive app restart for the same reopened document.
- Verify document-specific stored choices apply before playback starts.
- Verify unavailable stored voices are ignored safely without breaking document reopen.
- Verify current-session overrides still outrank stored document choices during the active run.
