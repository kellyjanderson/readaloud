# Voice Library Metadata and Information Surfacing

Status: draft

## Overview

This specification refines app-owned voice metadata and its presentation-facing normalization into implementable units.

## Backlink

Parent architecture:

- [Character Dialogue Attribution and Voice Casting](../architecture/character-dialogue-attribution-and-voice-casting.md)

## Scope

This specification covers:

- app-owned voice metadata fields
- source normalization for engine metadata
- presentation-facing guarantees for downstream UI

## Behavior

The parent branch now delegates detailed implementation to child specifications.

In particular:

- the voice metadata model and source-normalization policy belong to one leaf

UI presentation of that metadata is refined separately in the UI-derived specification branch.

## Constraints

- voice metadata must be normalized into app-owned fields before it reaches presentation code
- more socially sensitive cultural or identity metadata must not be improvised into the model without explicit product, UI, and architecture work
- absent optional metadata must remain a supported case

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Voice Metadata Model and Source Normalization](voice-metadata-model-and-source-normalization.md)

## Acceptance

- the app can normalize voice metadata into stable app-owned fields
- downstream UI specs can consume voice metadata without parsing engine-private raw blobs
- the remaining work in this branch is represented by final leaf specifications
