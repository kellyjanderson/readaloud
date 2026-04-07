# Character Gender Identity Extraction

Status: draft

## Overview

This specification refines second-pass character gender-identity extraction into narrower implementable units.

## Backlink

Parent specification:

- [Character Cast Registry and Voice Assignment](character-cast-registry-and-voice-assignment.md)

## Scope

This specification covers:

- pass ordering after quote attribution and alias consolidation
- output schema for identity, pronouns, evidence, and conflicts
- explicit identity evidence extraction
- descriptor and pronoun fallback logic
- conflict handling and unknown fallback

## Behavior

The parent branch now delegates detailed implementation to child specifications.

In particular:

- pass ordering and scope belong to their own leaf
- the identity output schema belongs to its own leaf
- explicit identity evidence extraction belongs to its own leaf
- descriptor attachment belongs to its own leaf
- pronoun profile extraction belongs to its own leaf
- conflict handling and unknown resolution belong to their own leaf

This parent specification keeps only the branch-level contract that gender identity is extracted after canonical character creation and remains separate from quote attribution and voice assignment.

## Constraints

- never infer gender identity during quote attribution
- never infer cis identity from pronouns, names, or descriptors alone
- never infer gender identity from names by default
- do not treat `they/them` as automatic evidence for `nonbinary`

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Character Identity Extraction Pass Ordering](character-identity-extraction-pass-ordering.md)
- [Character Identity Output Schema](character-identity-output-schema.md)
- [Explicit Character Identity Evidence](explicit-character-identity-evidence.md)
- [Character Identity Descriptor Attachment](character-identity-descriptor-attachment.md)
- [Character Pronoun Profile Extraction](character-pronoun-profile-extraction.md)
- [Character Identity Conflict Resolution](character-identity-conflict-resolution.md)

## Acceptance

- each canonical character can carry explicit identity extraction output after alias consolidation
- explicit identity evidence outranks pronouns
- downstream voice casting can consume this metadata without recomputing it live
- the remaining work in this branch is represented by final leaf specifications
