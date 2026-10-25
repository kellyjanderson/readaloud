# Character Reference Consolidation And Alias Clustering

## Architecture ownership

- [character dialogue attribution and voice casting](../architecture/character-dialogue-attribution-and-voice-casting.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Status: final

## Overview

This specification defines how near-duplicate speaker references are consolidated into one stable character identity before cast voice assignment.

## Backlink

Historical specification lineage:

- [Character Cast Registry and Voice Assignment](../archive/specification-ancestors/character-cast-registry-and-voice-assignment.md)

## Scope

This specification covers:

- consolidation of near-duplicate character labels
- preservation of observed aliases
- safeguards against merging distinct characters
- canonical display-label selection for one cast entry

## Behavior

The cast-registry build step must not treat every orthographic speaker-label variation as a new character by default.

When multiple attributed speaker references are highly likely to refer to the same character, the registry must consolidate them into one cast entry.

Consolidation may use:

- normalized exact-label equality
- near-duplicate spelling similarity for longer names
- shared initial token and close edit distance
- repeated attribution evidence across the same document

Consolidation must preserve:

- one stable cast id for the merged character
- all observed aliases that supported the merge
- all attribution ids that were folded into that character entry

The canonical display label should prefer the strongest observed form rather than an arbitrary later typo.

The system must remain conservative for short names.

It must not merge distinct characters such as different short names solely because they have a small edit distance.

## Constraints

- consolidation must happen at document time, not live during playback
- narrator must never be merged with character entries
- consolidation must remain traceable through preserved aliases and attribution evidence
- conservative false negatives are preferable to aggressive false merges for short names

## Acceptance

- obvious longer-name variants such as `Jennifer`, `Jenifer`, and `Jenefer` can resolve to one cast entry when the document evidence supports that merge
- merged cast entries preserve the observed aliases that were consolidated
- clearly distinct short names remain separate cast entries
- downstream voice assignment resolves against the consolidated cast entry rather than fragmented typo variants
