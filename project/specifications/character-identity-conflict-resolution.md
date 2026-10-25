# Character Identity Conflict Resolution

## Architecture ownership

- [character dialogue attribution and voice casting](../architecture/character-dialogue-attribution-and-voice-casting.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Status: final

## Overview

This specification defines conflict handling and `unknown` fallback for character identity extraction.

## Backlink

Historical specification lineage:

- [Character Gender Identity Extraction](../archive/specification-ancestors/character-gender-identity-extraction.md)

## Scope

This specification covers:

- conflicting evidence handling
- precision-first unknown fallback
- conflict flag semantics

## Behavior

Explicit identity evidence beats pronouns.

If two equally strong explicit identity outcomes conflict and cannot be resolved, the system must return:

- `gender_identity_label = unknown`
- `conflict_flag = true`

If evidence is sparse, weak, conflicting, or not attached to the specific canonical character, the system must prefer `unknown`.

## Constraints

- precision is more important than recall
- conflicting evidence must remain visible through `conflict_flag`
- weak fallback evidence must not overrule explicit conflict

## Acceptance

- explicit identity evidence beats pronouns
- unresolved conflicting evidence returns `unknown`
- `conflict_flag` is set when identity conflict cannot be resolved cleanly
