# Test Specification: Cast Management Dialog Structure

Status: final

## Overview

This test specification defines verification for the narrator-and-character voice-management dialog structure.

## Backlink

Feature specification:

- [Cast Management Dialog Structure](../specifications/cast-management-dialog-structure.md)

## Manual Smoke Check

1. Enable multi-voice mode and open `Character Voices`.
2. Verify the dialog clearly separates narrator assignment from character assignments.
3. Confirm each cast row exposes assignment state, preview, and selected-voice metadata without becoming crowded or confusing.

## Automated Smoke Tests

- Render the dialog with narrator plus character entries and assert both sections appear.
- Render the dialog with an empty or sparse cast list and verify the structure still holds.
- Verify assignment rows can expose preview actions and visible metadata for the selected voice.
- Verify closing the dialog returns focus cleanly to the reader surface.

## Automated Acceptance Tests

- Verify narrator assignment is visually distinct from character assignments.
- Verify each character row can represent automatic versus overridden assignment state.
- Verify narrator and character rows can preview their current selected voices without committing a new assignment first.
- Verify selected-voice quality, gender, and short description remain visible when that metadata exists.
- Verify large cast lists remain scrollable without breaking the dialog header or footer structure.
- Verify the dialog can be reopened without losing current assignment state presentation.

## Notes

- Widget tests should cover both short and long cast lists.
