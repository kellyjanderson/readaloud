# Editorial Typography Role Application

Status: final

## Overview

This specification defines how the product typography roles from the design guide are applied across the running app.

## Backlink

Parent specification:

- [Visual Design System Adoption UI](visual-design-system-adoption-ui.md)

## Scope

This specification covers:

- UI-chrome typography
- reading-surface typography
- technical-surface typography
- role-based size and weight consistency across current screens

## Behavior

The running app must apply typography by role rather than by opportunistic per-widget defaults.

For the current product phase:

- app chrome, menus, dialogs, buttons, forms, badges, and toasts use the UI sans role
- document reading content uses the reading serif role
- debug or technical inspection surfaces use the technical monospace role

The implementation may use the currently available local or bundled font path, but the role split itself must be directly observable in the running app.

## Constraints

- typography changes must preserve current readability
- the reading surface must remain optimized for long-form legibility rather than UI density
- technical surfaces must feel subordinate to reading, not like the default app voice

## Acceptance

- the running app clearly distinguishes UI chrome, reading content, and technical surfaces by typography role
- reading text no longer looks like generic app chrome
- technical panels no longer inherit the same typographic voice as the main reader content
