# Test Specification: Reading Surface Contrast And Highlight Legibility

Status: final

## Overview

This test specification defines verification for readable reading-surface contrast and highlight-preserving text legibility across appearance modes.

## Backlink

Feature specification:

- [Reading Surface Contrast And Highlight Legibility](../specifications/reading-surface-contrast-and-highlight-legibility.md)

## Manual Smoke Check

1. Open the reading surface in light mode and dark mode.
2. Read both ordinary text and highlighted text.
3. Confirm the text surface remains readable and the highlight does not erase legibility.

## Automated Smoke Tests

- Render the reading surface in light mode and verify text, background, and highlight tokens are distinct.
- Render the same surface in dark mode and verify the text surface uses a dark background with readable text.
- Verify highlighted and non-highlighted text both remain present and visible in the same paragraph.

## Automated Acceptance Tests

- Verify ordinary reading text remains readable against the reading-surface background in all supported appearance modes.
- Verify highlighted text preserves enough contrast to remain readable while still standing out from surrounding content.
- Verify dark mode does not regress to a bright reading panel with near-white text.
- Verify contrast-sensitive surfaces such as the recenter affordance and embedded reader cards do not undermine reading clarity.

## Notes

- Theme-token assertions are useful here, but keep at least one widget test focused on actual rendered contrast pairings.
