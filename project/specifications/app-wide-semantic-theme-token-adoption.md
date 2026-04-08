# App-Wide Semantic Theme Token Adoption

Status: final

## Overview

This specification defines the app-wide adoption of one semantic theme-token system across Reader, dialogs, overlays, toasts, and auxiliary surfaces.

## Backlink

Parent specification:

- [Visual Design System Adoption UI](visual-design-system-adoption-ui.md)

## Scope

This specification covers:

- one shared light and dark surface-token family
- one shared set of readable feedback, highlight, border, and chrome tokens
- replacement of scattered one-off literal colors where semantic tokens now exist

## Behavior

The running app must derive current product surfaces from one shared semantic token layer rather than from screen-local literal color picks.

At minimum this must cover:

- app background
- chrome and scaffold surfaces
- reader surface
- dialog and sheet surfaces
- elevated cards
- borders
- feedback toasts
- processing overlays
- spoken-text highlight colors
- debug or technical panels

The app may keep a warm editorial light theme and a darker technical-adjacent dark theme, but those themes must still read as one product family.

## Constraints

- readability wins over preserving an older ad hoc color choice
- current surfaces must not regress into low-contrast states
- token adoption should reduce, not increase, visual fragmentation

## Acceptance

- the running app uses one semantic token family across its current surfaces
- major current surfaces no longer depend on unrelated one-off literal color treatments
- light and dark modes read as one design system rather than separate products
