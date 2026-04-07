# Test Specification: Live Input Menu Placement And Playing-State Continuation

Status: final

## Overview

This test specification defines verification for File-menu live-input access and the playing-versus-paused behavior after watched-file refresh.

## Backlink

Feature specification:

- [Live Input Menu Placement And Playing-State Continuation](../specifications/live-input-menu-placement-and-playing-state-continuation.md)

## Manual Smoke Check

1. Locate live-input controls in the File menu rather than on the primary reader surface.
2. Start a watched-file session and begin playback.
3. Edit the watched file and confirm playback continues automatically when already playing, but remains paused when paused.

## Automated Smoke Tests

- Verify the primary reader surface does not render a dedicated live-input button.
- Verify File-menu activation can start a watched-file session.
- Verify a watched-file refresh preserves either playing or paused state according to the pre-refresh state.

## Automated Acceptance Tests

- Verify live-input access lives in the File menu instead of crowding the primary reading surface.
- Verify a watched-file refresh while playing continues forward automatically after reload.
- Verify a watched-file refresh while paused does not auto-resume playback.
- Verify the surfaced behavior remains consistent across repeated refresh cycles instead of alternating unpredictably.

## Notes

- Combine menu-surface widget tests with controller tests for playing-state continuation.
