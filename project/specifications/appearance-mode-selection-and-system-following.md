# Appearance Mode Selection And System Following

Status: final

## Overview

This specification defines the surfaced appearance-mode behavior for light, dark, and follow-system modes.

## Backlink

Parent specification:

- [Theme And Appearance Modes UI](theme-and-appearance-modes-ui.md)

## Scope

This specification covers:

- the supported appearance-mode choices
- default follow-system behavior
- explicit light and dark overrides
- placement of the setting outside the primary reading surface

## Behavior

The running app must expose appearance-mode choices for:

- light
- dark
- follow system

On first use, the default must be:

- follow system

When follow system is active, the app must adopt operating system appearance changes without requiring an app restart.

When light or dark is selected explicitly, that choice must override system appearance until the user changes it again.

Appearance-mode controls must live in a lower-complexity settings path rather than occupying persistent space on the primary reading surface.

## Constraints

- the app must not remain hard-coded to a single appearance mode
- supported appearance modes must keep follow-along highlighting and reading controls legible

## Acceptance

- a user can observe the running app in light, dark, and follow-system modes
- default behavior follows the current operating system appearance
- explicit light and dark choices visibly override system appearance
- appearance controls are available without cluttering the primary reading surface
