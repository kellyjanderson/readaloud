# Voice Metadata Model and Source Normalization

## Architecture ownership

- [character dialogue attribution and voice casting](../architecture/character-dialogue-attribution-and-voice-casting.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Status: final

## Overview

This specification defines the app-owned voice metadata model and how raw engine metadata is normalized into it.

## Backlink

Historical specification lineage:

- [Voice Library Metadata and Information Surfacing](../archive/specification-ancestors/voice-library-metadata-and-information-surfacing.md)

## Scope

This specification covers:

- app-owned voice metadata fields
- normalization of raw engine or catalog metadata into those fields
- handling of absent metadata

## Behavior

The app-owned voice metadata model must allow optional fields such as:

- explicit gender when the engine or app can determine it responsibly
- quality grade
- target quality
- training duration class
- short traits
- optional prose description

The model must allow those fields to be absent.

Raw engine or catalog metadata must be normalized into app-owned fields before reaching presentation code.

More socially sensitive cultural or identity metadata must not be improvised into the model without explicit product, UI, and architecture work defining:

- why it is needed
- how it is sourced
- how it is presented safely and respectfully
- how user expectations and failure modes are handled

## Constraints

- downstream UI must not parse engine-private raw metadata blobs directly
- absent optional metadata must remain a supported case

## Acceptance

- the app can expose stable app-owned voice metadata fields to downstream consumers
- the model remains usable even when a voice has only partial metadata
- more sensitive identity metadata remains explicitly out of scope until designed
