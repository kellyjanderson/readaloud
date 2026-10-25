# Character Pronoun Profile Extraction

## Architecture ownership

- [character dialogue attribution and voice casting](../architecture/character-dialogue-attribution-and-voice-casting.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Status: final

## Overview

This specification defines separate pronoun-profile extraction for canonical characters.

## Backlink

Historical specification lineage:

- [Character Gender Identity Extraction](../archive/specification-ancestors/character-gender-identity-extraction.md)

## Scope

This specification covers:

- pronoun counts and profile extraction
- separate storage from identity labels
- weaker fallback status for identity resolution

## Behavior

The system must extract a pronoun profile separately from identity labels.

At minimum, it must track:

- `he/him/his`
- `she/her/hers`
- `they/them/theirs`
- neopronouns when present

Pronoun evidence is weaker than explicit identity statements, explicit apposition, and attached descriptors.

Pronouns may contribute fallback identity resolution only when stronger explicit evidence is absent.

## Constraints

- pronouns and identity labels must remain separate fields
- `they/them` must not automatically imply `nonbinary`
- pronoun evidence alone must not imply cis identity

## Acceptance

- each canonical character can carry a separate pronoun profile
- pronoun profile remains inspectable independently of identity labels
