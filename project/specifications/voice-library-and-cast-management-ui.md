# Voice Library and Cast Management UI

Status: draft

## Overview

This specification refines the voice-library and cast-management UI definitions into implementable UI leaves.

## Backlink

Parent UI definition:

- [Voice Library and Cast Management](../ui/voice-library-and-cast-management.md)

## Scope

This specification covers:

- voice library row presentation
- information affordance behavior
- cast management dialog structure

## Behavior

The parent UI branch now delegates detailed implementation to child specifications.

In particular:

- voice library row presentation and information affordance belong to one leaf
- cast management dialog structure belongs to its own leaf

This parent specification keeps only the branch-level contract for the advanced surface itself.

The primary-surface entry path into that surface is refined separately by:

- [Primary Reader Surface UI](primary-reader-surface-ui.md)

## Constraints

- top-level UI must remain visually simple
- advanced voice/cast controls must not become a persistent primary-surface panel
- UI presentation must consume app-owned voice metadata rather than engine-private raw blobs

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Voice Library Row and Information Affordance](voice-library-row-and-information-affordance.md)
- [Cast Management Dialog Structure](cast-management-dialog-structure.md)
- [Voice Management Dialog Contrast And Readability](voice-management-dialog-contrast-and-readability.md)

## Acceptance

- the remaining UI work in this branch is represented by final leaf specifications
- the voice-management surface can be implemented without inventing its structure ad hoc
