# Test Specification: Playback Coordination

Status: final

## Overview

This test specification defines verification for transport behavior, controller playback state, replay semantics, and coordination across chunk boundaries.

## Backlink

Feature specification:

- [Playback Coordination](../specifications/playback-coordination.md)

## Manual Smoke Check

1. Load a document and exercise play, pause, resume, restart, and jump controls.
2. Confirm the visible state and audible behavior stay consistent as playback moves across chunk boundaries.
3. Verify the app does not enter stalled or contradictory transport states.

## Automated Smoke Tests

- Exercise the playback controller through idle, playing, paused, completed, and resumed states.
- Verify ordinary transport events do not throw or leave the controller without a valid state.
- Verify chunk-completion events continue playback when more routed content remains.

## Automated Acceptance Tests

- Verify pause immediately stops forward playback progression and resume restarts from the expected point.
- Verify replay or restart behavior returns to the intended earlier point without corrupting subsequent progress mapping.
- Verify transport state remains internally consistent when chunk generation, chunk completion, and progress events interleave.
- Verify playback coordination survives routed multi-voice boundaries without dropping into a dead end or phantom-complete state.

## Notes

- This leaf should be covered mostly by controller tests with fake runtimes and deterministic event sequences.
