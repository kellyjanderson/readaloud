# Test Specification: Voice Library Row And Information Affordance

Status: final

## Overview

This test specification defines verification for the row-level voice presentation, quality surfacing, and metadata information affordance in the voice library.

## Backlink

Feature specification:

- [Voice Library Row and Information Affordance](../specifications/voice-library-row-and-information-affordance.md)

## Manual Smoke Check

1. Open the voice-management or voice-library surface.
2. Inspect several voice rows with different metadata availability.
3. Confirm name, quality, gender, locale, preview, and visible short description remain readable and usable.

## Automated Smoke Tests

- Render a voice row with full metadata and assert name, quality, gender, locale, preview, and short description are shown.
- Render a voice row with partial metadata and verify the row still lays out cleanly.
- Trigger the preview affordance and verify sample playback can start without changing assignment state.
- Trigger the information affordance and verify traits or description content becomes visible.

## Automated Acceptance Tests

- Verify quality metadata appears directly in the row when known.
- Verify gender metadata appears directly in the row when known.
- Verify the preview affordance is available per voice row and does not require selecting the voice first.
- Verify a short description remains directly visible when available instead of being hidden entirely behind the info affordance.
- Verify the information affordance reveals richer metadata without forcing a separate heavyweight details workflow.
- Verify rows remain usable when description text is absent and traits are the only metadata.
- Verify desktop and mobile interaction paths both expose the same metadata payload.

## Notes

- Use widget tests with representative voice fixtures that vary in quality, description, and locale coverage.
