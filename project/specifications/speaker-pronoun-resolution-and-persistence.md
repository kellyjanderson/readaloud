# Speaker Pronoun Resolution And Persistence

Status: final

## Overview

This specification defines lower-priority speaker attribution from recent pronoun context and most-recent established speaker persistence.

## Backlink

Parent specification:

- [Quoted Dialogue Speaker Context Scanning](quoted-dialogue-speaker-context-scanning.md)

## Scope

This specification covers:

- local pronoun-based speaker resolution
- most-recent established speaker fallback
- conservative unknown handling when pronoun context is ambiguous

## Behavior

If stronger explicit, adjacent, paragraph, and alternation rules do not resolve a quote, the system may use recent pronoun context and recent established-speaker persistence.

Pronoun-based resolution must remain local and attached to the quoted utterance context.

Speaker persistence may fall back to the most recent established speaker only when no stronger contradictory evidence exists.

If pronoun evidence or persistence remains ambiguous, the quote must resolve to `unknown` instead of a guess.

## Constraints

- pronoun resolution is weaker than explicit and adjacent evidence
- persistence is the weakest fallback in the current ladder
- ambiguity must favor `unknown`

## Acceptance

- recent local pronoun context can resolve a quote when stronger rules are absent
- most-recent speaker persistence can act as a fallback when no contradictory evidence exists
- ambiguous pronoun or persistence cases resolve to `unknown`
