# Test Specification: Transient Feedback Toast Behavior

Status: final

## Overview

This test specification defines verification for non-blocking toast feedback in the Reader workspace.

## Backlink

Feature specification:

- [Transient Feedback Toast Behavior](../specifications/transient-feedback-toast-behavior.md)

## Manual Smoke Check

1. Trigger a recoverable runtime warning in the Reader workspace.
2. Confirm feedback appears as a floating toast rather than an inline banner that pushes content downward.
3. Confirm the reading surface and transport stay in place.
4. Confirm the message uses plain language rather than raw engine diagnostics.

## Automated Smoke Tests

- Verify surfaced non-blocking feedback renders in an overlay layer instead of a layout-flow banner.
- Verify showing a toast does not change the measured position of the reading surface container.
- Verify recoverable feedback copy is sourced from product-facing copy rather than raw exception text by default.

## Automated Acceptance Tests

- Verify Reader-surface layout does not shift when ordinary feedback appears.
- Verify routine recoverable diagnostics do not surface raw technical strings as the primary user-facing message.
- Verify recoverable startup-restore failures use accurate, non-alarming copy.
- Verify blocking states still use their own overlay or dialog path instead of the toast channel.

## Notes

- Combine widget layout assertions with controller or error-surface tests that inject recoverable failures.
