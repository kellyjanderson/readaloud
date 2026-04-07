# Test Specification: Appearance Mode Selection And System Following

Status: final

## Overview

This test specification defines verification for surfaced light, dark, and follow-system appearance behavior.

## Backlink

Feature specification:

- [Appearance Mode Selection And System Following](../specifications/appearance-mode-selection-and-system-following.md)

## Manual Smoke Check

1. Open Reader Options and switch between `Follow System`, `Light`, and `Dark`.
2. Confirm the app updates immediately.
3. With `Follow System` selected, change the OS appearance and confirm the app follows it.

## Automated Smoke Tests

- Render the app in each appearance mode and verify the active theme changes.
- Persist the selected appearance mode and verify it reloads correctly on restart.
- Verify `Follow System` uses platform brightness instead of locking to the last explicit theme.

## Automated Acceptance Tests

- Verify explicit `Light` and `Dark` selections override current system brightness.
- Verify `Follow System` mirrors the host brightness when the system changes after launch.
- Verify theme-dependent reader surfaces, dialogs, and feedback use the active appearance mode consistently.
- Verify the initial default is `Follow System` rather than a hard-coded light or dark fallback.

## Notes

- Pair widget tests with preference persistence tests and one app-shell test that simulates system brightness changes.
