# Test Specification: Feedback Surface Contrast Readability

Status: final

## Overview

This test specification defines verification for minimum readable contrast on surfaced in-app feedback while broader feedback UX redesign is still pending.

## Backlink

Feature specification:

- [Feedback Surface Contrast Readability](../specifications/feedback-surface-contrast-readability.md)

## Manual Smoke Check

1. Trigger an in-app feedback message such as a warning or runtime notice.
2. Verify the message text, icon, and dismiss affordance are all legible in the active theme.
3. Repeat in both light and dark appearance modes.

## Automated Smoke Tests

- Render the feedback surface in light mode and assert theme colors are taken from semantic feedback tokens rather than washed-out literals.
- Render the same surface in dark mode and assert text and icon colors remain distinct from the background.
- Verify long messages wrap without becoming visually invisible.

## Automated Acceptance Tests

- Verify primary feedback text remains readable at the default text scale in both light and dark appearance modes.
- Verify icons and dismiss controls maintain adequate visual separation from the feedback background.
- Verify the feedback surface does not regress to near-white-on-light or near-dark-on-dark combinations when the theme changes.
- Verify common warning and information variants use the same semantic contrast strategy rather than ad hoc per-message colors.

## Notes

- Widget tests should assert color usage through theme tokens where practical.
- Full WCAG auditing can remain in the later UI overhaul, but these tests should still catch obvious unreadable regressions.
