# Test Specification: Running-App Uninterrupted Speech Under Follow-Along Load

Status: final

## Overview

This test specification defines verification for the surfaced running-app outcome of the audio-authoritative playback rearchitecture.

## Backlink

Feature specification:

- [Running-App Uninterrupted Speech Under Follow-Along Load](../specifications/running-app-uninterrupted-speech-under-follow-along-load.md)

## Manual Smoke Check

1. Open a long document and enable the normal follow-along reader surface.
2. Start playback and let it run through multiple later-chunk arrivals while the spoken highlight updates.
3. Confirm speech stays audibly smooth; if the visible text catches up by jumping, it should do so without making audio stutter.

## Automated Smoke Tests

- Run playback with fake progress pressure and verify audio continuity remains the primary outcome.
- Verify follower drift recovery does not require a user pause/play cycle.
- Verify no silent highlight-only loops appear when later chunks or follower work are under pressure.

## Automated Acceptance Tests

- Verify ordinary running-app playback with follow-along active remains audibly continuous across later-chunk arrival and follower catch-up.
- Verify the visible spoken region may skip intermediate states and still converge on the current audio position.
- Verify the app no longer requires manual intervention to continue ordinary playback when the follower side briefly falls behind.

## Notes

- This leaf needs real running-app verification by ear in addition to controller and engine coverage.
