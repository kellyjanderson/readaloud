# Desktop Native Menu And Mobile Overflow Navigation

Status: final

## Overview

This specification defines the platform-specific shell rule that preserves the three-dots overflow menu on mobile while removing it from the desktop Reader shell.

## Backlink

Parent specification:

- [App Shell And Platform Navigation UI](app-shell-and-platform-navigation-ui.md)

## Scope

This specification covers:

- desktop removal of the in-app three-dots overflow menu
- migration of those desktop commands into native menu-bar items
- continued mobile use of the overflow menu for secondary or global commands

## Behavior

On macOS desktop, the Reader workspace must not render an in-app three-dots overflow menu.

Commands that were previously gathered there must be reachable through native menu-bar items instead.

For the current product phase:

- the File menu is the primary product-facing home for those desktop commands
- commands that belong in the application menu by native platform convention should remain there rather than being duplicated in File

On mobile, the three-dots overflow menu should remain available as the access path for secondary or global commands that do not belong on the primary reading surface.

The desktop app must not expose the same global command family in both:

- a native menu-bar path
- and a Reader-shell in-app overflow trigger

## Constraints

- the desktop shell must stay coherent with native macOS document-app expectations
- the mobile overflow menu must not become the primary path for transport or reading itself
- this platform split must remain consistent with the reading-first complexity-layering rule

## Acceptance

- in the running macOS app, the Reader shell no longer shows the three-dots overflow menu
- commands previously housed there are reachable from native menu-bar items, with File as the primary product-facing home
- the mobile app retains the three-dots overflow menu for secondary or global commands
- desktop no longer presents a duplicated hybrid command model
