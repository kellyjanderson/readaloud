# Test Specification: Watched-File Session Refresh

Status: final

## Overview

This test specification defines verification for watched-file refresh behavior while a live-input session is active.

## Backlink

Feature specification:

- [Watched-File Session Refresh](../specifications/watched-file-session-refresh.md)

## Manual Smoke Check

1. Start a watched-file session from the File menu.
2. Edit and save the source file while the app is open.
3. Confirm the document reloads with the changed content.

## Automated Smoke Tests

- Simulate a watched-file change and verify the session triggers a refresh.
- Verify repeated file-change notifications do not crash or duplicate the reader state.
- Verify disabling or ending the watched-file session stops refresh handling.

## Automated Acceptance Tests

- Verify a watched-file change replaces the active document content with the updated source.
- Verify live-input refresh preserves the session identity instead of behaving like a completely unrelated document load.
- Verify refresh can occur both while playback is active and while playback is paused.
- Verify file-watch errors or invalidated paths degrade gracefully without leaving the controller in a broken intermediate state.

## Notes

- Favor controller tests with fake file-watch events over actual filesystem watches when possible.
