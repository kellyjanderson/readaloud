# Test Specification: App-Wide Semantic Theme Token Adoption

Status: final

## Overview

This test specification defines verification for the app-wide semantic theme-token adoption work.

## Backlink

Feature specification:

- [App-Wide Semantic Theme Token Adoption](../specifications/app-wide-semantic-theme-token-adoption.md)

## Manual Smoke Check

1. Launch the app in light mode and confirm Reader, dialogs, sheets, cards, and toasts feel like one palette family.
2. Launch the app in dark mode and confirm the same surfaces still read as one system.
3. Confirm major surfaces no longer look like they belong to different prototype phases.

## Automated Smoke Tests

- Verify major shell and secondary surfaces resolve colors from shared theme or token sources.
- Verify the current light and dark themes expose the custom token family used by Reader surfaces and secondary surfaces.

## Automated Acceptance Tests

- Verify the current running app surfaces no longer depend on visibly conflicting hard-coded palette fragments.
- Verify Reader, voice management, Reader Options, overlays, and feedback surfaces use one coherent semantic token family.
