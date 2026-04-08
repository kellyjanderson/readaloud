# Visual Design System Adoption UI

Status: draft

## Overview

This specification refines the full brand, design, and UX overhaul into implementable UI leaves.

## Backlink

Parent UI definitions:

- [Design Guide](../ui/design-guide.md)
- [Component System](../ui/component-system.md)

## Scope

This specification covers:

- app-wide semantic theme token adoption
- editorial typography role application
- cross-surface dialog, sheet, card, chip, and overlay consistency
- Reader Options information hierarchy and section structure

## Behavior

The parent UI branch now delegates detailed implementation to child specifications.

In particular:

- semantic theme-token adoption belongs to one leaf
- typography role application belongs to one leaf
- secondary-surface component-family consistency belongs to one leaf
- Reader Options hierarchy belongs to one leaf

This parent specification keeps only the branch-level contract that the running app should feel like one calm editorial system rather than a collection of unrelated prototype surfaces.

## Constraints

- the overhaul must not regress the reading-first product hierarchy
- diagnostics may remain available, but must not dominate the visual system
- the current running surfaces should converge on one shared palette, shape, and spacing family rather than preserving one-off moods

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [App-Wide Semantic Theme Token Adoption](app-wide-semantic-theme-token-adoption.md)
- [Editorial Typography Role Application](editorial-typography-role-application.md)
- [Secondary Surface Component Family Consistency](secondary-surface-component-family-consistency.md)
- [Reader Options Sectioned Information Hierarchy](reader-options-sectioned-information-hierarchy.md)

## Acceptance

- the current brand, design, and UX overhaul branch is fully represented by final leaf specifications
- the overhaul can be implemented as explicit surfaced work rather than as untracked polish drift
