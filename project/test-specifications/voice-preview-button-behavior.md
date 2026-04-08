# Test Specification: Voice Preview Button Behavior

Status: final

## Overview

This test specification defines verification for reusable voice preview behavior across voice-management surfaces.

## Backlink

Feature specification:

- [Voice Preview Button Behavior](../specifications/voice-preview-button-behavior.md)

## Manual Smoke Check

1. Open a voice-selection or cast-management surface.
2. Trigger preview for one voice without assigning it.
3. Trigger preview for a second voice and confirm the first preview stops or is replaced.
4. Confirm the preview control shows sensible idle and active feedback.

## Automated Smoke Tests

- Verify a preview action can be invoked without changing the assigned voice.
- Verify only one preview remains active at a time in the current surface.
- Verify preview controls render on both voice rows and cast-assignment rows where applicable.

## Automated Acceptance Tests

- Verify starting a new preview stops or replaces the previously active preview.
- Verify preview state changes are visible and reversible without requiring assignment.
- Verify the preview affordance remains compact and icon-led across desktop and mobile layouts.
- Verify preview behavior stays consistent between narrator and character assignment surfaces.

## Notes

- Pair widget tests for control state with controller or service tests for single-active-preview behavior.
