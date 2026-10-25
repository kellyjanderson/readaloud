# Character Identity Descriptor Attachment

## Architecture ownership

- [character dialogue attribution and voice casting](../architecture/character-dialogue-attribution-and-voice-casting.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Status: final

## Overview

This specification defines secondary identity evidence from strong gendered descriptors attached to a canonical character.

## Backlink

Historical specification lineage:

- [Character Gender Identity Extraction](../archive/specification-ancestors/character-gender-identity-extraction.md)

## Scope

This specification covers:

- strong descriptor evidence such as `man`, `woman`, `brother`, `sister`
- attachment of that descriptor to one canonical character
- its weaker status relative to explicit identity statements

## Behavior

The system may use strong gendered descriptors as secondary evidence only when the descriptor is clearly attached to the specific canonical character.

Examples include:

- `man`
- `woman`
- `boy`
- `girl`
- `brother`
- `sister`
- `mother`
- `father`

Descriptor evidence is weaker than explicit identity statements and explicit apposition.

## Constraints

- descriptors must not be treated as valid evidence unless they are attached to the specific character mention being resolved
- descriptor evidence must not imply cis identity
- weak or floating descriptors should not be treated as reliable identity evidence

## Acceptance

- strong attached descriptors can contribute secondary identity evidence
- unattached descriptors do not count as identity evidence
