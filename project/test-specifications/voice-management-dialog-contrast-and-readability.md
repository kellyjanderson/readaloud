# Test Specification: Voice Management Dialog Contrast And Readability

Status: final

## Overview

This test specification defines verification for minimum readable contrast inside the narrator-and-character voice-management dialog.

## Backlink

Feature specification:

- [Voice Management Dialog Contrast And Readability](../specifications/voice-management-dialog-contrast-and-readability.md)

## Manual Smoke Check

1. Open the voice-management dialog in both light and dark appearance modes.
2. Inspect headings, row labels, selected values, badges, locale labels, and affordances.
3. Confirm the dialog is readable enough to support actual testing and assignment work.

## Automated Smoke Tests

- Render the dialog in light mode and assert semantic surface and text colors are used rather than washed-out hard-coded values.
- Render the dialog in dark mode and assert labels, values, and controls remain visually distinct.
- Verify rows with badges and secondary metadata still remain readable when selected or hovered.

## Automated Acceptance Tests

- Verify narrator and character row labels remain readable against their card backgrounds.
- Verify selected-voice values and dropdown controls maintain readable contrast in both themes.
- Verify badges, pills, and secondary metadata such as locale text remain legible instead of fading into the surface.
- Verify the dialog can serve as a practical testing surface rather than only a structurally correct but unreadable one.

## Notes

- Widget tests can assert theme-token usage and key color combinations.
- Full visual polish belongs to the later overhaul, but these tests should prevent the dialog from becoming untestable.
