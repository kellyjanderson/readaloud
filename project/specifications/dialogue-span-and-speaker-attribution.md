# Dialogue Span and Speaker Attribution

Status: draft

## Overview

This specification refines dialogue detection and speaker attribution into implementable units.

## Backlink

Parent architecture:

- [Character Dialogue Attribution and Voice Casting](../architecture/character-dialogue-attribution-and-voice-casting.md)

## Scope

This specification covers:

- dialogue span detection
- speaker attribution result shape
- attribution-provider boundary

## Behavior

The parent branch now delegates detailed implementation to child specifications.

In particular:

- dialogue-span identification belongs to its own leaf
- speaker-attribution result shape and provider contract belong to their own leaf

This parent specification keeps only the branch-level requirement that dialogue identity and likely speaker identity must be resolved before playback routing begins.

## Constraints

- attribution is document-time work, not hot playback work
- attribution must remain engine-agnostic
- dialogue and speaker results must remain traceable to normalized segment ids and word ranges

## Refinement Status

Requires refinement.

## Child Specifications

- [Dialogue Span Detection](dialogue-span-detection.md)
- [Speaker Attribution Contract](speaker-attribution-contract.md)

## Acceptance

- the app can distinguish narration from direct-speech spans
- the app can attach likely speaker identity to dialogue when enough evidence exists
- the remaining work in this branch is represented by final leaf specifications
