# Test Specification: Uninterrupted Audio Primary Channel

Status: final

## Overview

This test specification defines verification for the rule that active speech audio remains the authoritative playback channel while follower concerns stay downstream.

## Backlink

Feature specification:

- [Uninterrupted Audio Primary Channel](../specifications/uninterrupted-audio-primary-channel.md)

## Manual Smoke Check

1. Start reading a long document with follow-along active.
2. While speech is playing, trigger ordinary follower work such as visible highlighting, follow behavior, and resume persistence.
3. Confirm speech continues without being interrupted by those follower paths.

## Automated Smoke Tests

- Drive active playback while progress, highlight, and persistence callbacks fire repeatedly.
- Verify ordinary follower callbacks do not issue playback restart, queue rebuild, or transport-reset behavior.
- Verify only explicit transport or session-changing actions are allowed to create a new playback identity.

## Automated Acceptance Tests

- Verify progress handling, highlight mapping, and resume persistence can all run during active playback without stopping or rebuilding the current audio session.
- Verify scroll-yield or other follow-along state changes do not change playback identity.
- Verify voice, rate, jump, replay, and document replacement still remain the only ordinary reasons to reconfigure active playback.

## Notes

- This leaf is best covered by engine and controller tests with fake player/runtime seams plus explicit assertions about forbidden transport mutations.
