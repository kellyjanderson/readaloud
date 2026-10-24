# Explicit Character Identity Evidence

## Architecture ownership

- [character dialogue attribution and voice casting](../architecture/character-dialogue-attribution-and-voice-casting.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the active ACD/plan.

Status: final

## Overview

This specification defines explicit identity extraction for canonical characters.

## Backlink

Historical specification lineage:

- [Character Gender Identity Extraction](../archive/specification-ancestors/character-gender-identity-extraction.md)

## Scope

This specification covers:

- explicit identity statements
- explicit apposition and narration
- specificity preservation for explicit identity labels

## Behavior

The system must scan for explicit identity statements attached to a canonical character.

Valid examples include:

- `John is a man.`
- `Mara is a woman.`
- `Alex is nonbinary.`
- `Rin is genderqueer.`
- `She is a trans woman.`
- `He is a trans man.`
- `They are transgender.`
- `Mara, a cis woman, ...`
- `Avery, a nonbinary engineer, ...`
- `Jon, a transgender man, ...`

Specific explicit labels must be preserved.

More specific explicit identity beats less specific explicit identity.

For example:

- `trans_female` beats `female`
- `trans_male` beats `male`

## Constraints

- the evidence must be attached to the specific canonical character mention being resolved
- `transgender` must only be used when explicitly present and no more specific subtype is attached
- `male` and `female` must not imply cis identity

## Acceptance

- explicit identity statements are extracted and preserved
- explicit apposition and narration are extracted and preserved
- more specific explicit identity labels beat less specific explicit labels
