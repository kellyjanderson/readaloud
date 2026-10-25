# Adjacent Speaker Context Attribution

## Architecture ownership

- [character dialogue attribution and voice casting](../architecture/character-dialogue-attribution-and-voice-casting.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Status: final

## Overview

This specification defines before-and-after local context attribution for quoted dialogue when no same-sentence explicit tag is available.

## Backlink

Historical specification lineage:

- [Quoted Dialogue Speaker Context Scanning](../archive/specification-ancestors/quoted-dialogue-speaker-context-scanning.md)

## Scope

This specification covers:

- immediately previous sentence evidence
- immediately next sentence evidence
- local name, pronoun, speech-verb, and action binding tied to the quote

## Behavior

If no same-sentence explicit speaker tag is available, the system must inspect immediately adjacent local context.

Valid adjacent evidence includes:

- a previous sentence with named or pronominal speaker tied to speech/action
- a next sentence with named or pronominal speaker tied to speech/action
- adjacent named character action that clearly implies the speaker

When both sides are plausible, the system must prefer the evidence most local to the quoted utterance rather than allowing a prior exchange to bleed into the next quote.

## Constraints

- adjacency must remain local to the quote context
- the system must prefer precision over filling every quote

## Acceptance

- immediately previous and next sentence context can attribute a quote when clearly attached
- local trailing evidence can override prior-speaker bleed in alternating exchanges
