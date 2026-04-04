# Character Cast Registry Model

Status: final

## Overview

This specification defines the stable document-scoped cast model used for narrator and character identity.

## Backlink

Parent specification:

- [Character Cast Registry and Voice Assignment](character-cast-registry-and-voice-assignment.md)

## Scope

This specification covers:

- narrator entry requirements
- character entry requirements
- cast ids
- display labels and supporting evidence

## Behavior

The system must maintain a cast registry that includes:

- one explicit narrator entry
- zero or more detected character entries

Each cast entry must preserve:

- a stable document-scoped cast id
- a role kind such as narrator or character
- a display label
- supporting confidence and provenance

Character entries may also preserve:

- observed aliases
- attribution evidence

Cast ids must remain stable within one normalized document version.

## Constraints

- narrator is a first-class cast entry, not null
- cast entries must remain separate from voice assignment state
- cast identity must remain traceable to document-time attribution results

## Acceptance

- the app can represent narrator and characters in one stable registry
- cast identity remains stable within one normalized document version
- voice assignment can resolve against cast ids without redoing attribution work
