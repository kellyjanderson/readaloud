# Test Specification: Reader Diagnostics And Source Panels

Status: final

## Overview

This test specification defines verification for the Reader Options panels that surface TTS diagnostics and document-source metadata.

## Backlink

Feature specification:

- [Reader Diagnostics And Source Panels](../specifications/reader-diagnostics-and-source-panels.md)

## Manual Smoke Check

1. Open Reader Options on a loaded document.
2. Open the diagnostics and source panels.
3. Confirm diagnostic information and source metadata can be inspected without displacing the primary reader surface.

## Automated Smoke Tests

- Render Reader Options with diagnostic and source data available and assert both panels appear.
- Render the same surface with partial or missing data and verify the panels degrade gracefully.
- Verify opening and closing the panels does not throw layout overflow or focus errors.

## Automated Acceptance Tests

- Verify source metadata identifies the active document without exposing raw internal implementation details unnecessarily.
- Verify diagnostics content can surface runtime trace information when available and a sensible empty state when not.
- Verify diagnostic and source panels remain secondary settings content rather than reappearing on the primary reading surface.
- Verify the panels remain usable under both light and dark appearance modes.

## Notes

- Widget tests should cover both populated and sparse-data states.
