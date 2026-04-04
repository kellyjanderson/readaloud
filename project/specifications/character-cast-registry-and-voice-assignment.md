# Character Cast Registry and Voice Assignment

Status: draft

## Overview

This specification refines narrator-plus-character cast management into implementable units.

## Backlink

Parent architecture:

- [Character Dialogue Attribution and Voice Casting](../architecture/character-dialogue-attribution-and-voice-casting.md)

## Scope

This specification covers:

- stable cast identity
- automatic voice assignment
- user override resolution

## Behavior

The parent branch now delegates detailed implementation to child specifications.

In particular:

- the cast registry model belongs to its own leaf
- automatic voice assignment and override resolution belong to their own leaf

This parent specification keeps only the branch-level contract that narrator and character identities become stable cast entries before multi-voice routing is derived.

## Constraints

- narrator is a first-class cast entry, not null
- cast ids must remain stable within one normalized document version
- user overrides must remain separate from automatic inference confidence

## Refinement Status

Requires refinement.

## Child Specifications

- [Character Cast Registry Model](character-cast-registry-model.md)
- [Automatic Voice Casting and Override Resolution](automatic-voice-casting-and-override-resolution.md)

## Acceptance

- the app can represent narrator and detected characters in one stable cast model
- automatic casting and user override can coexist without ambiguity
- the remaining work in this branch is represented by final leaf specifications
