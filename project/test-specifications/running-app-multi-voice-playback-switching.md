# Test Specification: Running-App Multi-Voice Playback Switching

Status: final

## Overview

This test specification defines verification for audible narrator-versus-character switching during live playback in the running app.

## Backlink

Feature specification:

- [Running-App Multi-Voice Playback Switching](../specifications/running-app-multi-voice-playback-switching.md)

## Manual Smoke Check

1. Enable multi-voice reading on a document with dialogue from at least two characters.
2. Play through narrator, character, and quote-tag-quote passages.
3. Confirm the app audibly switches voices at the expected narration and dialogue boundaries without stalling.

## Automated Smoke Tests

- Build a routed playback plan with distinct narrator and character voices and verify multiple effective voice ids are present.
- Drive the playback controller with a fake runtime and assert routed chunks continue in order across a voice switch.
- Verify later-chunk preparation failure does not trap playback in a silent highlight loop.

## Automated Acceptance Tests

- Verify narrator and character voice changes happen only at routed narration or dialogue boundaries.
- Verify live playback continues forward after the first switched chunk instead of requiring pause or play to recover.
- Verify automatic casting preserves audible narrator-versus-character contrast when compatible distinct voices exist.
- Verify when distinct voices cannot be produced, the surfaced cast state makes that limitation explicit rather than pretending switching is active.

## Notes

- This leaf needs both controller-level and audio-path tests.
- Manual verification by ear remains important even after automated coverage is in place.
