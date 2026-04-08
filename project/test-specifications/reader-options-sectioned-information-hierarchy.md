# Test Specification: Reader Options Sectioned Information Hierarchy

Status: final

## Overview

This test specification defines verification for the grouped hierarchy inside Reader Options.

## Backlink

Feature specification:

- [Reader Options Sectioned Information Hierarchy](../specifications/reader-options-sectioned-information-hierarchy.md)

## Manual Smoke Check

1. Open Reader Options.
2. Confirm the surface is grouped into clearly named sections.
3. Confirm preferences, timing, diagnostics, and source panels are visually distinct from one another.

## Automated Smoke Tests

- Verify Reader Options renders named grouped sections rather than a flat control list.
- Verify diagnostics and source panels remain in secondary grouped sections.

## Automated Acceptance Tests

- Verify Reader Options presents a calmer sectioned hierarchy in the running app.
- Verify users can distinguish preferences from diagnostics and source information without scanning one undifferentiated list.
