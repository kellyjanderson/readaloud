# Spoken Text Highlighting and Reading Focus

Status: draft

## Overview

This specification refines spoken-text highlighting and reading-focus behavior into implementable units.

## Backlink

Parent architecture:

- [Spoken Text Highlighting and Reading Focus](../architecture/spoken-text-highlighting-and-reading-focus.md)

## Scope

This specification covers:

- spoken selection derivation
- progress-to-display mapping
- reading-focus follow policy

## Behavior

The parent branch now delegates detailed implementation to child specifications.

In particular:

- spoken selection and display mapping belong to one leaf
- reading-focus follow policy belongs to its own leaf

This parent specification keeps only the branch-level contract that playback progress must become visible follow-along state on the reader surface.

## Constraints

- spoken highlight state must remain traceable to normalized ids
- degraded mapping must still result in useful UI feedback
- highlight behavior must remain engine-agnostic above the progress-event contract

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Spoken Text Selection and Display Mapping](spoken-text-selection-and-display-mapping.md)
- [Reading Focus Follow Policy](reading-focus-follow-policy.md)

## Acceptance

- the reader surface visibly tracks the current spoken text
- the viewport follows playback without fighting user scrolling
- the remaining work in this branch is represented by final leaf specifications
