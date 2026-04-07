# Explicit Character Identity Evidence

Status: final

## Overview

This specification defines explicit identity extraction for canonical characters.

## Backlink

Parent specification:

- [Character Gender Identity Extraction](character-gender-identity-extraction.md)

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
