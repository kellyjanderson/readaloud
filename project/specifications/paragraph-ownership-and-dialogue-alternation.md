# Paragraph Ownership And Dialogue Alternation

Status: final

## Overview

This specification defines paragraph-level ownership and dialogue alternation heuristics for unattributed dialogue.

## Backlink

Parent specification:

- [Quoted Dialogue Speaker Context Scanning](quoted-dialogue-speaker-context-scanning.md)

## Scope

This specification covers:

- one-speaker-per-dialogue-paragraph ownership
- consecutive unattributed dialogue paragraph alternation
- contradiction by stronger local evidence

## Behavior

One dialogue paragraph should normally map to one speaker unless stronger local evidence contradicts that assumption.

When consecutive dialogue paragraphs remain unattributed after stronger rules are applied, the system may alternate speakers across that local exchange.

This alternation heuristic must be cancelled or overridden whenever explicit attribution or stronger adjacent evidence identifies a different speaker.

## Constraints

- paragraph ownership and alternation are weaker than explicit and adjacent evidence
- alternation must stay local to one exchange, not drift across unrelated narration

## Acceptance

- a dialogue paragraph normally resolves to one speaker
- consecutive unattributed dialogue paragraphs can alternate speakers locally
- stronger explicit or adjacent evidence overrides paragraph alternation
