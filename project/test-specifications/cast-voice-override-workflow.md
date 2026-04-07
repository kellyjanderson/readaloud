# Test Specification: Cast Voice Override Workflow

Status: final

## Overview

This test specification defines verification for manual narrator and character voice overrides and their effect on playback routing.

## Backlink

Feature specification:

- [Cast Voice Override Workflow](../specifications/cast-voice-override-workflow.md)

## Manual Smoke Check

1. Enable multi-voice reading and open `Character Voices`.
2. Change the narrator voice and at least one character voice from automatic to explicit selections.
3. Play the document and confirm the chosen overrides are reflected in audible playback.

## Automated Smoke Tests

- Render the cast-management dialog with narrator and character rows and verify override controls can change selection state.
- Apply an override in controller or service tests and verify resolved voice assignments update.
- Clear an override and verify the assignment returns to automatic selection.

## Automated Acceptance Tests

- Verify narrator overrides take precedence over automatic narrator selection.
- Verify character overrides take precedence over automatic cast selection for the targeted character only.
- Verify unrelated characters remain automatic when one character is overridden.
- Verify override state survives closing and reopening the dialog and is reflected in routed playback plans.

## Notes

- Pair widget tests with routing or controller tests so the workflow is proven end to end.
