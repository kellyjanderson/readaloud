# Follow-Along Reading Surface UI

Status: draft

## Overview

This specification refines the follow-along reading-surface UI definition into implementable UI leaves.

## Backlink

Parent UI definition:

- [Follow-Along Reading Surface](../ui/follow-along-reading-surface.md)

## Scope

This specification covers:

- spoken highlight visual presentation
- user-scroll interaction with auto-follow behavior

## Behavior

The parent UI branch now delegates detailed implementation to child specifications.

In particular:

- spoken highlight presentation belongs to one leaf
- user-scroll interaction and re-centering behavior belong to one leaf

This parent specification keeps only the branch-level contract that the reading surface should be visibly follow-along and visually calm.

## Constraints

- the reading surface must not feel jumpy or crowded
- the UI must separate highlight presentation from viewport-follow interaction

## Refinement Status

Requires refinement.

## Child Specifications

- [Spoken Highlight Visual Presentation](spoken-highlight-visual-presentation.md)
- [Follow-Along User Scroll Interaction](follow-along-user-scroll-interaction.md)

## Acceptance

- the remaining UI work in this branch is represented by final leaf specifications
- the reader-surface follow-along UI can be implemented without inventing structure ad hoc
