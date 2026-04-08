# Test Specification: Desktop Native Menu And Mobile Overflow Navigation

Status: final

## Overview

This test specification defines verification for the platform split that removes the in-app overflow menu on desktop while preserving it on mobile.

## Backlink

Feature specification:

- [Desktop Native Menu And Mobile Overflow Navigation](../specifications/desktop-native-menu-and-mobile-overflow-navigation.md)

## Manual Smoke Check

1. Launch the macOS app and confirm the Reader shell does not show the three-dots overflow menu.
2. Confirm the commands that previously lived there are now reachable from native menu-bar items, with File as the primary product-facing home.
3. Launch the mobile app and confirm the three-dots overflow menu is still available for secondary commands.

## Automated Smoke Tests

- Verify the desktop Reader shell does not render the overflow trigger.
- Verify the mobile shell still renders the overflow trigger.
- Verify the desktop command registry exposes the moved command set through native menu-bar wiring instead of an in-app overflow entrypoint.

## Automated Acceptance Tests

- Verify the macOS Reader shell presents no in-app three-dots overflow affordance.
- Verify the commands formerly grouped in the desktop overflow menu are reachable from native menu-bar commands.
- Verify the mobile shell retains the overflow menu without moving primary reading controls into it.
- Verify desktop does not duplicate the same command family in both menu-bar structure and an in-app overflow trigger.

## Notes

- Prefer platform-gated shell/widget tests plus command-registration tests over brittle pixel-comparison checks.
