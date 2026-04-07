# Live Input And File Menu UI

Status: draft

## Overview

This specification refines the live-input UI definition into implementable leaves for menu placement and user-visible playback semantics.

## Backlink

Parent UI definition:

- [Live Input and File Menu Behavior](../ui/live-input-and-file-menu-behavior.md)

## Scope

This specification covers:

- File-menu placement for live input
- surfaced live-input continuation semantics while playing
- surfaced paused-versus-playing behavior during document refresh

## Behavior

The parent UI branch now delegates detailed implementation to child specifications.

In particular:

- File-menu placement and playing-state continuation belong to one leaf

This parent specification keeps only the branch-level contract that live input is an advanced workflow feature and should behave like a truly live reading experience when enabled.

## Constraints

- live input must not consume persistent primary-surface space
- user-observable transport semantics must remain consistent with the underlying continuity and importer behavior

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Live Input Menu Placement and Playing-State Continuation](live-input-menu-placement-and-playing-state-continuation.md)

## Acceptance

- the remaining UI work in this branch is represented by final leaf specifications
- the running app can be specified as exposing live input through menus with explicit playing-versus-paused semantics
