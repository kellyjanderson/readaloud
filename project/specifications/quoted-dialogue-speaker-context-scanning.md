# Quoted Dialogue Speaker Context Scanning

Status: draft

## Overview

This specification refines quoted-dialogue speaker-context scanning into narrower implementable heuristics.

Issue anchor:

- GitHub issue `#18`
- GitHub issue `#23`

## Backlink

Parent specification:

- [Dialogue Span and Speaker Attribution](dialogue-span-and-speaker-attribution.md)

## Scope

This specification covers:

- scanning before and after quoted dialogue for speaker evidence
- support for common narrative speaker-tag patterns
- paragraph and exchange-level attribution heuristics
- pronoun and persistence fallback heuristics

## Behavior

The parent branch now delegates detailed implementation to child specifications.

In particular:

- same-sentence explicit speaker-tag attribution belongs to its own leaf
- adjacent before/after speaker-context attribution belongs to its own leaf
- paragraph ownership and dialogue alternation belong to its own leaf
- pronoun-based resolution and speaker persistence belong to its own leaf

This parent specification keeps only the branch-level contract that quoted dialogue is attributed from ordered local context rules rather than one opaque score.

## Constraints

- attribution remains document-time work, not live playback work
- the heuristic must remain conservative when multiple possible speakers are present
- explicit unattributed dialogue is preferable to a confident wrong speaker
- the result must remain provider-independent downstream

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Explicit Speaker Tag Attribution](explicit-speaker-tag-attribution.md)
- [Adjacent Speaker Context Attribution](adjacent-speaker-context-attribution.md)
- [Paragraph Ownership And Dialogue Alternation](paragraph-ownership-and-dialogue-alternation.md)
- [Speaker Pronoun Resolution And Persistence](speaker-pronoun-resolution-and-persistence.md)

## Acceptance

- quoted dialogue can be attributed from nearby speaker context before the quote
- quoted dialogue can be attributed from nearby speaker context after the quote
- the remaining work in this branch is represented by final leaf specifications
