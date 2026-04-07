# Test Specification: Sleep Timer And Timing Surface

Status: final

## Overview

This test specification defines verification for the surfaced sleep-timer controls and timing information in Reader Options.

## Backlink

Feature specification:

- [Sleep Timer And Timing Surface](../specifications/sleep-timer-and-timing-surface.md)

## Manual Smoke Check

1. Open Reader Options.
2. Set a sleep timer and confirm the chosen value is reflected in the UI.
3. Verify timing-related information remains readable and stable while playback continues.

## Automated Smoke Tests

- Render the timing section and assert sleep-timer controls are present.
- Set or clear a timer in tests and verify the state updates without throwing.
- Verify the timing section renders safely when no active timer is present.

## Automated Acceptance Tests

- Verify choosing a sleep timer value updates controller state and persists for the active session.
- Verify clearing the timer returns the UI to a neutral no-timer state.
- Verify timing information remains consistent while playback state changes between playing and paused.
- Verify the timing section does not crowd out unrelated reader preferences or diagnostics content.

## Notes

- Favor controller and widget tests over real-time waiting tests when possible.
