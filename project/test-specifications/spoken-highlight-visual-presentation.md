# Test Specification: Spoken Highlight Visual Presentation

Status: final

## Overview

This test specification defines verification for the visible spoken highlight styling and precision fallbacks on the reading surface.

## Backlink

Feature specification:

- [Spoken Highlight Visual Presentation](../specifications/spoken-highlight-visual-presentation.md)

## Manual Smoke Check

1. Play a document with follow-along enabled.
2. Watch the active spoken range while playback advances.
3. Confirm the active range is obvious, readable, and remains aligned with spoken progress.

## Automated Smoke Tests

- Render the reading surface with a word-level highlight and assert the active styling appears.
- Render fallback segment-level and block-level highlights and verify each has a visible differentiated treatment.
- Verify highlight markup can be updated repeatedly without DOM or widget build errors.

## Automated Acceptance Tests

- Verify word-level progress produces the highest-precision highlight when available.
- Verify segment-level or block-level fallback still makes the current spoken region unmistakable when finer timing is absent.
- Verify active highlight styling remains readable rather than washing text out against the surface.
- Verify highlight updates do not leave stale active regions behind when playback advances.

## Notes

- Use renderer and widget tests together so both markup generation and visible styling stay covered.
