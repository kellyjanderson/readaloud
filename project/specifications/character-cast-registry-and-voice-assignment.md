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
- alias consolidation for one character across near-duplicate references
- contextual cast metadata needed for better auto-casting
- automatic voice assignment
- user override resolution
- user-observable override workflow

## Behavior

The parent branch now delegates detailed implementation to child specifications.

In particular:

- the cast registry model belongs to its own leaf
- character reference consolidation belongs to its own leaf
- contextual cast metadata inference belongs to its own leaf
- automatic voice assignment and override resolution belong to their own leaf
- context-aware automatic casting belongs to its own leaf
- user-observable cast voice override workflow belongs to its own leaf

This parent specification keeps only the branch-level contract that narrator and character identities become stable cast entries before multi-voice routing is derived.

## Constraints

- narrator is a first-class cast entry, not null
- cast ids must remain stable within one normalized document version
- user overrides must remain separate from automatic inference confidence

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Character Cast Registry Model](character-cast-registry-model.md)
- [Character Reference Consolidation And Alias Clustering](character-reference-consolidation-and-alias-clustering.md)
- [Character Gender Identity Extraction](character-gender-identity-extraction.md)
- [Automatic Voice Casting and Override Resolution](automatic-voice-casting-and-override-resolution.md)
- [Context-Aware Automatic Voice Casting](context-aware-automatic-voice-casting.md)
- [Cast Voice Override Workflow](cast-voice-override-workflow.md)

## Acceptance

- the app can represent narrator and detected characters in one stable cast model
- obvious near-duplicate references can be consolidated into one character when evidence supports that merge
- cast metadata needed for better auto-casting is represented before playback begins
- automatic casting and user override can coexist without ambiguity
- the running app has an explicit final leaf for user-observable override behavior
- the remaining work in this branch is represented by final leaf specifications
