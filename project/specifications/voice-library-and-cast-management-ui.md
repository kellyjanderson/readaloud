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

This parent specification keeps only the branch-level contract that advanced voice and cast controls remain off the primary surface and accessible through the standard secondary affordance.

## Constraints

- top-level UI must remain visually simple
- advanced voice/cast controls must not become a persistent primary-surface panel
- UI presentation must consume app-owned voice metadata rather than engine-private raw blobs

## Refinement Status

Requires refinement.

## Child Specifications

- [Voice Library Row and Information Affordance](voice-library-row-and-information-affordance.md)
- [Cast Management Dialog Structure](cast-management-dialog-structure.md)

## Acceptance

- the remaining UI work in this branch is represented by final leaf specifications
- the voice-management surface can be implemented without inventing its structure ad hoc
