# Primary Reader Surface UI

Status: draft

## Overview

This specification refines the primary reading surface and complexity-layering UI definition into implementable UI leaves.

## Backlink

Parent UI definition:

- [Primary Surface and Complexity Layering](../ui/primary-surface-and-complexity-layering.md)

## Scope

This specification covers:

- the dominant top-level reader control set
- reduction of top-level configuration clutter
- document identity placement outside the reading surface
- integrated access to advanced voice and cast controls

## Behavior

The parent UI branch now delegates detailed implementation to child specifications.

In particular:

- the simplified primary reader control set belongs to one leaf
- document identity placement outside the reading surface belongs to one leaf
- integrated secondary access to advanced voice and cast controls belongs to one leaf
- document-load cast processing overlay belongs to one leaf
- multi-voice mode toggle and cast entrypoint behavior belong to one leaf

This parent specification keeps only the branch-level contract that the primary surface remains reading-first while still allowing access to deeper voice controls.

## Constraints

- top-level UI must remain visually simple
- advanced voice or cast controls must not become a competing persistent button family
- non-reading workflows such as live input and appearance settings must remain off the primary surface

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Primary Reader Control Set](primary-reader-control-set.md)
- [Document Identity Outside Reading Surface](document-identity-outside-reading-surface.md)
- [Integrated Secondary Voice Access](integrated-secondary-voice-access.md)
- [Document-Load Cast Processing Overlay](document-load-cast-processing-overlay.md)
- [Multi-Voice Mode Toggle And Cast Entrypoint](multi-voice-mode-toggle-and-cast-entrypoint.md)
- [Feedback Surface Contrast Readability](feedback-surface-contrast-readability.md)

## Acceptance

- the remaining UI work in this branch is represented by final leaf specifications
- the running app can be specified as a simplified reading-first primary surface rather than an accretion of top-level controls
