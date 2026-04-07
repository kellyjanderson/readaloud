# Test Specification: Reader Preferences Controls

Status: final

## Overview

This test specification defines verification for the Reader Options controls that adjust reading speed, font, and reading scale.

## Backlink

Feature specification:

- [Reader Preferences Controls](../specifications/reader-preferences-controls.md)

## Manual Smoke Check

1. Open Reader Options.
2. Change reading speed, reading font, and reading scale.
3. Confirm the changes apply and remain visible when the surface is reopened.

## Automated Smoke Tests

- Render Reader Options and assert the preference controls are present with valid initial values.
- Interact with each control once and verify controller or preference state updates.
- Verify reopening the screen reflects the saved values.

## Automated Acceptance Tests

- Verify reading speed changes affect the surfaced playback rate value and persist through controller reload.
- Verify reading font selection changes the reading surface text style without breaking highlight rendering.
- Verify reading scale changes the visible document scale and persists across relaunch.
- Verify invalid or out-of-range preference values are normalized back to supported values rather than breaking the surface.

## Notes

- Pair widget tests with preference persistence coverage.
