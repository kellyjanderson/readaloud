# Test Specification: Segmented Transport Capsule

Status: final

## Overview

This test specification defines verification for the unified segmented transport on the primary Reader surface.

## Backlink

Feature specification:

- [Segmented Transport Capsule](../specifications/segmented-transport-capsule.md)

## Manual Smoke Check

1. Open the Reader workspace and locate the transport.
2. Confirm the transport appears as one segmented capsule rather than three unrelated buttons.
3. Verify back, center play or pause, and forward can each be activated independently.
4. Trigger a processing state and confirm only the center segment changes into processing feedback.

## Automated Smoke Tests

- Verify the Reader surface renders one shared transport container.
- Verify the container exposes three independent action targets.
- Verify the processing state swaps only the center segment content.

## Automated Acceptance Tests

- Verify the transport no longer renders as three visually unrelated controls.
- Verify back and forward remain active side actions while the center remains the dominant primary action.
- Verify processing feedback never replaces the back or forward segments.
- Verify the transport remains usable across light and dark appearance modes.

## Notes

- Prefer widget-level structure assertions plus targeted interaction tests for each segment.
