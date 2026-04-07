# Character Pronoun Profile Extraction

Status: final

## Overview

This specification defines separate pronoun-profile extraction for canonical characters.

## Backlink

Parent specification:

- [Character Gender Identity Extraction](character-gender-identity-extraction.md)

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
