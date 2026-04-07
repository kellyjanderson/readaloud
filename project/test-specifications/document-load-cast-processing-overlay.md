# Test Specification: Document-Load Cast Processing Overlay

Status: final

## Overview

This test specification defines verification for the visible multi-voice processing overlay shown while document-load cast analysis is running.

## Backlink

Feature specification:

- [Document-Load Cast Processing Overlay](../specifications/document-load-cast-processing-overlay.md)

## Manual Smoke Check

1. Enable multi-voice reading.
2. Open a dialogue-bearing document.
3. Confirm the reader surface greys out and shows a processing overlay with visible progress rather than appearing idle.

## Automated Smoke Tests

- Drive the reader controller into cast-processing state and assert the overlay becomes visible.
- Verify the overlay can display progress text or progress values without layout overflow.
- Verify ordinary reading controls are visually suppressed while processing is active.

## Automated Acceptance Tests

- Verify multi-voice document preparation exposes a surfaced processing state from the moment analysis starts until it completes or fails.
- Verify the overlay is styled as in-progress work, not as a fatal-error banner.
- Verify progress updates can move forward across multiple internal phases without requiring the exact internal phase names to stay fixed.
- Verify processing completion removes the overlay and restores ordinary interaction.

## Notes

- Use fake controller state for widget coverage and one controller-level test for lifecycle transitions.
