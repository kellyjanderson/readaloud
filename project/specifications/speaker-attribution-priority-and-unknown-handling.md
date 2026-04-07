# Speaker Attribution Priority And Unknown Handling

Status: final

## Overview

This specification defines how competing speaker-attribution rules are ordered and when attribution must resolve to `unknown`.

## Backlink

Parent specification:

- [Speaker Attribution Contract](speaker-attribution-contract.md)

## Scope

This specification covers:

- rule priority ordering
- override behavior between stronger and weaker evidence
- confidence thresholding for unknown output

## Behavior

Speaker attribution must use an explicit priority ladder rather than one flat heuristic score.

Higher-priority rules must override lower-priority rules.

Explicit attribution must always beat heuristics.

If the best available result remains below the configured confidence threshold, the system must return `unknown` rather than a guessed speaker.

The priority ladder for the current branch must support at least:

1. same-sentence explicit attribution
2. adjacent attribution
3. paragraph ownership
4. dialogue alternation
5. action binding
6. pronoun resolution
7. speaker persistence

## Constraints

- priority resolution must be deterministic for one normalized document version
- unknown is the preferred outcome when evidence is weak or conflicting
- rule priority must remain visible in `rule_used`

## Acceptance

- higher-priority rules override lower-priority rules
- explicit attribution beats heuristics
- low-confidence results resolve to `unknown`
