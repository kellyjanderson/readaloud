# Test Specification: Follower Progress Coalescing And Drift Resynchronization

Status: final

## Overview

This test specification defines verification for visible follower coalescing and hard resynchronization when highlight or follow-along state lags active audio.

## Backlink

Feature specification:

- [Follower Progress Coalescing And Drift Resynchronization](../specifications/follower-progress-coalescing-and-drift-resynchronization.md)

## Manual Smoke Check

1. Start playback on a long document with follow-along visible.
2. Watch the spoken highlight during continuous reading.
3. Confirm the visible region may skip ahead to the current spoken location rather than trying to animate every intermediate step when the reader surface falls behind.

## Automated Smoke Tests

- Feed rapid progress updates into the follower path and verify visible updates are coalesced to the configured cadence.
- Verify follower lag can trigger a hard resynchronization without requesting playback restart.
- Verify lower-confidence mapping can still recover using segment- or block-level fallback.

## Automated Acceptance Tests

- Verify the follower path can drop intermediate word states once lag exceeds the configured threshold.
- Verify drift beyond the configured word or block threshold causes a direct jump to the current mapped audio position.
- Verify follower catch-up never replays missed highlight history or requests queue rebuild from the audio side.

## Notes

- Widget tests and controller tests should both participate in this leaf because it crosses visible state and progress policy.
