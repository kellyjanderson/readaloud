# Automatic Voice Casting and Override Resolution

Status: final

## Overview

This specification defines how the app assigns voices automatically and how user overrides resolve against those defaults.

## Backlink

Parent specification:

- [Character Cast Registry and Voice Assignment](character-cast-registry-and-voice-assignment.md)

## Scope

This specification covers:

- automatic cast assignment
- deterministic assignment behavior
- user override precedence
- fallback behavior

## Behavior

Automatic assignment must be deterministic within one document version.

Automatic assignment may use:

- locale
- available voice metadata
- future character attributes such as explicit referential gender when that data exists and is responsibly modeled

Effective voice resolution must use this precedence:

1. user override
2. stored document-specific cast decision
3. automatic cast assignment
4. narrator/default fallback

User overrides must remain visibly distinct from automatic choices in the underlying state model.

## Constraints

- automatic assignment must not mutate cast identity
- override resolution must not depend on live playback state
- fallback behavior must remain deterministic and explicit

## Acceptance

- the app can assign default voices to narrator and characters deterministically
- user overrides always win over automatic assignment
- unresolved or missing assignments still resolve to a stable fallback
