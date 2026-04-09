# Test Specification: Append-Only Forward Playback Queue

Status: final

## Overview

This test specification defines verification for append-only queue growth during ordinary forward playback.

## Backlink

Feature specification:

- [Append-Only Forward Playback Queue](../specifications/append-only-forward-playback-queue.md)

## Manual Smoke Check

1. Start reading a long document and let playback move across multiple chunks.
2. Keep follow-along visible while later chunks arrive.
3. Confirm speech continues forward without an audible stop-and-restart feel when later chunks are prepared.

## Automated Smoke Tests

- Simulate first-chunk startup followed by later `chunkReady` events during active playback.
- Verify later chunk arrival appends future audio instead of rebuilding the whole player source list.
- Verify player-source replacement remains absent during ordinary forward queue growth.

## Automated Acceptance Tests

- Verify later chunk readiness cannot trigger `stop -> setAudioSources -> seek -> play` while prepared audio still exists for the active session.
- Verify queue bookkeeping may advance or drop consumed chunks without replaying already spoken audio.
- Verify true rebuild behavior remains reserved for explicit session changes or confirmed starvation recovery.

## Notes

- This leaf needs explicit player-spy assertions, not only audible regression checks.
