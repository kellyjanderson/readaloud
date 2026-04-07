# Test Specification: Playback Progress And Jump Mapping

Status: final

## Overview

This test specification defines verification for playback progress records, visible position mapping, and 30-second jump behavior.

## Backlink

Feature specification:

- [Playback Progress and Jump Mapping](../specifications/playback-progress-and-jump-mapping.md)

## Manual Smoke Check

1. Start playback on a mid-length document.
2. Use jump back and jump forward controls several times during playback and while paused.
3. Confirm the spoken position, visible highlight, and resumed playback position stay coherent.

## Automated Smoke Tests

- Feed progress records into the controller and verify the mapped visible position updates.
- Invoke jump back and jump forward once each and verify the resulting target position remains in range.
- Verify jump mapping does not throw when timing estimates are sparse.

## Automated Acceptance Tests

- Verify jump operations clamp safely at document start and document end.
- Verify the same progress model drives both visible follow-along state and jump target derivation.
- Verify resumed playback after a jump starts near the mapped target position rather than the stale pre-jump point.
- Verify repeated jump operations do not accumulate drift that moves the visible and spoken positions out of sync.

## Notes

- Controller tests with stable synthetic progress fixtures are preferable to real-time playback tests here.
