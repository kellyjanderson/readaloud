# Character Identity Extraction Pass Ordering

## Architecture ownership

- [character dialogue attribution and voice casting](../architecture/character-dialogue-attribution-and-voice-casting.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Status: final

## Overview

This specification defines when character identity extraction runs and what data it may depend on.

## Backlink

Historical specification lineage:

- [Character Gender Identity Extraction](../archive/specification-ancestors/character-gender-identity-extraction.md)

## Scope

This specification covers:

- extraction pass ordering
- dependency on canonical character entities
- separation from quote attribution

## Behavior

Character identity extraction must run as a second pass after:

- quote attribution
- character alias consolidation
- canonical character entity creation

It must scan the full document for each canonical character after those earlier steps complete.

Gender identity extraction must not run during quote attribution.

## Constraints

- quote attribution and character identity extraction are separate passes
- the identity pass must operate on canonical characters, not raw mention strings

## Acceptance

- identity extraction runs after canonical character creation
- quote attribution does not attempt to assign identity labels directly
