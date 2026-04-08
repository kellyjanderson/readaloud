# Test Specification: Reader-Only App Shell Until Authoring Exists

Status: final

## Overview

This test specification defines verification that the current product shell remains Reader-only while authoring work is still unimplemented.

## Backlink

Feature specification:

- [Reader-Only App Shell Until Authoring Exists](../specifications/studio-workspace-entry-and-reader-isolation.md)

## Manual Smoke Check

1. Launch the app and confirm it opens into Reader.
2. Confirm there is no Studio entry in the current shell.
3. Confirm Reader does not show Studio panels, controls, or authoring terminology on the main reading surface.
4. On each platform, confirm the menu surfaces do not expose an authoring-workspace stub.

## Automated Smoke Tests

- Verify Reader is the default initial workspace.
- Verify Studio is not rendered as a persistent primary navigation item or menu item in the current shell.
- Verify platform-specific menu registration does not expose a Studio entry on desktop or mobile.

## Automated Acceptance Tests

- Verify Reader remains the default workspace on launch.
- Verify the current shell does not surface Studio access on desktop or mobile.
- Verify Reader does not render Studio-specific controls or labels in its main surface.
- Verify authoring work stays out of the shell until there is real implemented functionality behind it.

## Notes

- Prefer shell-level navigation tests over brittle pixel assertions.
