# Reader Options Sectioned Information Hierarchy

Status: final

## Overview

This specification defines the visual hierarchy and grouping structure for the Reader Options secondary surface.

## Backlink

Parent specifications:

- [Visual Design System Adoption UI](visual-design-system-adoption-ui.md)
- [Reader Options And Secondary Settings UI](reader-options-and-secondary-settings-ui.md)

## Scope

This specification covers:

- section grouping inside Reader Options
- section titles and descriptions
- visual separation between preference, timing, diagnostics, and source blocks
- reducing the sense of one long undifferentiated utility list

## Behavior

The running Reader Options surface must group controls and panels into clearly named sections rather than presenting one visually flat list.

For the current app, the surface should separate at least:

- voice and reading preferences
- timing and sleep behavior
- diagnostics and traces
- document source information

Each section should read as a purposeful secondary-settings block, with its own small hierarchy, while still remaining lighter than the main Reader surface.

## Constraints

- Reader Options must remain secondary to Reader rather than becoming a competing dashboard
- the surface must stay scrollable on smaller windows
- grouping should clarify purpose without adding noisy decoration

## Acceptance

- the running Reader Options surface is visually grouped by purpose
- users can distinguish preference controls from diagnostics and source panels without scanning a flat list
- Reader Options feels calmer and more deliberate than the prior utility-wall presentation
