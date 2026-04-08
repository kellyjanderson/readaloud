# Mobile Overflow Menu Domain Grouping

Status: final

## Overview

This specification defines the internal grouping and ordering of commands inside the mobile overflow menu.

## Backlink

Parent specification:

- [App Shell And Platform Navigation UI](app-shell-and-platform-navigation-ui.md)

## Scope

This specification covers:

- grouping secondary mobile overflow commands by domain
- separating document actions from settings, live input, and export
- reducing the sense of one flat miscellaneous command dump

## Behavior

On mobile, the overflow menu may remain the access path for secondary or global commands, but it must not present those commands as one undifferentiated list.

For the current product phase, the menu should group at least:

- document intake actions
- document-output or export actions
- live-input actions
- secondary settings actions such as `Reader Options`

The exact UI control may use separators or other lightweight grouping treatments, but the result must read as intentional domain clustering rather than as a miscellaneous stack.

## Constraints

- grouping must stay lightweight and must not turn the menu into a mini dashboard
- the menu must remain secondary to the Reader surface
- primary reading actions must remain outside the overflow menu

## Acceptance

- the running mobile app shows the overflow menu grouped by command domain rather than as one flat list
- users can distinguish document actions from settings, live input, and export more quickly
- the menu remains secondary, compact, and reading-first
