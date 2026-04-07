# Test Specification: Integrated Secondary Voice Access

Status: final

## Overview

This test specification defines verification for the integrated secondary affordance that opens advanced voice and cast controls without crowding the primary reading surface.

## Backlink

Feature specification:

- [Integrated Secondary Voice Access](../specifications/integrated-secondary-voice-access.md)

## Manual Smoke Check

1. Load a document and stay on the primary reader surface.
2. Locate the integrated secondary affordance associated with voice management.
3. Open it and confirm advanced voice controls appear without reshaping the primary reading layout first.

## Automated Smoke Tests

- Render the reader screen and assert the secondary voice affordance is present when voice or cast management is available.
- Tap or click the affordance in a widget test and assert the voice-management surface opens.
- Verify opening the secondary surface does not require exposing additional top-level controls beforehand.

## Automated Acceptance Tests

- Verify the primary reader surface remains reading-first while advanced voice access is still reachable in one gesture.
- Verify the same affordance can represent either single-voice or cast-management entry depending on mode.
- Verify the affordance stays attached to the voice-management domain rather than becoming a generic overflow control.
- Verify keyboard, pointer, and touch activation all reach the same voice-management surface.

## Notes

- Prefer widget tests that assert route, dialog, or sheet opening rather than relying on exact iconography.
