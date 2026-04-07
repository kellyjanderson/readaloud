# Theme And Appearance Modes UI

Status: draft

## Overview

This specification refines the appearance-mode UI definition into implementable leaves.

## Backlink

Parent UI definition:

- [Theme and Appearance Modes](../ui/theme-and-appearance-modes.md)

## Scope

This specification covers:

- appearance-mode selection
- follow-system behavior
- placement of appearance controls off the primary reading surface

## Behavior

The parent UI branch now delegates detailed implementation to child specifications.

In particular:

- appearance-mode selection and system-following behavior belong to one leaf

This parent specification keeps only the branch-level contract that appearance modes are supported explicitly and remain outside the primary reading controls.

## Constraints

- the app must not remain effectively fixed to one appearance mode
- appearance controls must not compete with transport controls on the primary surface

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Appearance Mode Selection and System Following](appearance-mode-selection-and-system-following.md)

## Acceptance

- the remaining UI work in this branch is represented by final leaf specifications
- the running app can be specified as supporting light, dark, and follow-system behavior explicitly
