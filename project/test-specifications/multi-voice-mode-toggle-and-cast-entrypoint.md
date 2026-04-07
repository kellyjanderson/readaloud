# Test Specification: Multi-Voice Mode Toggle And Cast Entrypoint

Status: final

## Overview

This test specification defines verification for the surfaced multi-voice mode toggle and the corresponding cast-management entrypoint behavior.

## Backlink

Feature specification:

- [Multi-Voice Mode Toggle And Cast Entrypoint](../specifications/multi-voice-mode-toggle-and-cast-entrypoint.md)

## Manual Smoke Check

1. Open Reader Options.
2. Toggle multi-voice reading on and off.
3. Confirm the primary surface swaps between the single-voice control and the `Character Voices` entrypoint as the mode changes.

## Automated Smoke Tests

- Toggle `multiVoiceEnabled` in controller or preferences state and assert the surfaced controls update.
- Verify the toggle persists across controller reload or app restart state restoration.
- Verify opening the cast entrypoint succeeds only when multi-voice mode is active.

## Automated Acceptance Tests

- Verify enabling multi-voice mode surfaces cast-management entry without adding extra permanent clutter to the primary control set.
- Verify disabling multi-voice mode restores the single-voice path and hides cast-only UI.
- Verify persisted mode state is reflected correctly on next launch.
- Verify the primary-surface entrypoint label and activation path remain accurate for the active mode rather than mixing narrator and cast terminology.

## Notes

- Pair widget tests with preference persistence tests.
