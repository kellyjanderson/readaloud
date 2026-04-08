# Platform Navigation And Menu Segmentation

`Read Aloud` should use different command-access patterns on desktop and mobile.

The product should feel native to the platform before it feels clever.

## Overview

The app currently has two relevant command surfaces:

- native desktop menu-bar menus
- an in-app three-dots overflow menu

Those should not remain symmetrical across platforms.

## Desktop Rule

On macOS desktop, the Reader shell should not surface an in-app three-dots overflow menu.

Global and secondary commands that are not part of the primary reading surface should move into the native menu bar instead.

For the current product phase:

- the File menu is the primary product-facing home for commands currently gathered into the desktop three-dots menu
- commands that belong to the application menu by platform convention should remain there rather than being duplicated in File

The goal is:

- one coherent desktop command model
- no competition between native menu-bar structure and a custom in-app overflow shell

## Mobile Rule

On mobile, the three-dots overflow menu should remain the standard access path for secondary or global commands that do not belong on the primary reading surface.

This menu is acceptable on mobile because:

- there is no native desktop menu bar
- secondary command density must stay off the main reading surface
- the overflow pattern is familiar in mobile navigation

## Scope Of The Split

This platform split applies to commands that are global to the Reader workspace rather than tied to one already surfaced control.

Examples include:

- document actions
- live-input access
- export
- no placeholder authoring-workspace entries while authoring remains unimplemented
- secondary settings or diagnostics surfaces that are not already directly represented elsewhere

## Constraints

- the desktop shell must not duplicate the same command family in both an in-app overflow trigger and the native menu bar
- the mobile shell may use the overflow menu, but it must still keep primary reading actions out of that menu
- the platform split must remain consistent with the reading-first interface rule

## Related Specifications

- [App Shell And Platform Navigation UI](../specifications/app-shell-and-platform-navigation-ui.md)
