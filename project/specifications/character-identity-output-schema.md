# Character Identity Output Schema

Status: final

## Overview

This specification defines the per-character output schema for document-owned identity extraction.

## Backlink

Parent specification:

- [Character Gender Identity Extraction](character-gender-identity-extraction.md)

## Scope

This specification covers:

- required output fields
- valid identity labels
- separation between identity, pronouns, and evidence

## Behavior

For each canonical character, the system must preserve:

- `character_id`
- `canonical_name`
- `aliases`
- `gender_identity_label`
- `gender_confidence`
- `gender_source`
- `pronoun_profile`
- `evidence_spans`
- `conflict_flag`

Valid `gender_identity_label` values are:

- `male`
- `female`
- `cis_male`
- `cis_female`
- `transgender`
- `trans_male`
- `trans_female`
- `nonbinary`
- `genderqueer`
- `unknown`

Gender identity, pronouns, and gendered descriptors must remain separate stored data.

## Constraints

- the schema must not collapse pronouns into identity
- the schema must not collapse descriptors into identity without source tracking

## Acceptance

- each canonical character has the required identity output fields
- identity, pronouns, and evidence remain separately inspectable
