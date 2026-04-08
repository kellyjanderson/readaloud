# Test Specification: Editorial Typography Role Application

Status: final

## Overview

This test specification defines verification for typography-role application across current app surfaces.

## Backlink

Feature specification:

- [Editorial Typography Role Application](../specifications/editorial-typography-role-application.md)

## Manual Smoke Check

1. Launch the app and confirm UI chrome, reading content, and technical panels each feel typographically distinct.
2. Confirm reading text feels suited to long-form content rather than generic UI copy.
3. Confirm technical surfaces read as subordinate support tooling.

## Automated Smoke Tests

- Verify the app theme applies role-based typography to current surfaces.
- Verify document reading content is not styled with the same role as menus and dialogs.

## Automated Acceptance Tests

- Verify the running app visibly distinguishes UI chrome, reading content, and technical surfaces by typography role.
- Verify current typography changes do not regress readability on primary or secondary surfaces.
