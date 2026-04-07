# Test Specification: Primary Reader Control Set

Status: final

## Overview

This test specification defines manual and automated verification for the simplified reading-first control set on the primary reader surface.

## Backlink

Feature specification:

- [Primary Reader Control Set](../specifications/primary-reader-control-set.md)

## Manual Smoke Check

1. Launch the app with a readable document loaded.
2. Look only at the primary reader surface without opening secondary menus.
3. Confirm the dominant controls are the selected voice or character-voice entrypoint, play or pause, jump back, jump forward, and the reading surface.

## Automated Smoke Tests

- Render the reader screen with a loaded document and assert the primary transport controls are present.
- Assert the primary surface does not render unrelated advanced controls by default.
- Verify the primary surface remains stable when playback state changes between idle, playing, and paused.

## Automated Acceptance Tests

- Verify the primary surface exposes play or pause, jump back, and jump forward as immediately accessible controls.
- Verify advanced controls such as diagnostics, live input, or secondary settings are not promoted into the top-level transport row.
- Verify multi-voice mode swaps the primary voice affordance from a single-voice selector to the character-voice entrypoint without expanding the primary control footprint.
- Verify small and large layout widths preserve the same control priority rather than introducing extra top-level controls opportunistically.

## Notes

- Prefer widget tests against the top-level reader screen.
- Keep assertions focused on control presence, prominence, and absence of clutter rather than exact pixel positions.
