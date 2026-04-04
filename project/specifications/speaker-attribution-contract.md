# Speaker Attribution Contract

Status: final

## Overview

This specification defines the result contract and provider boundary for attributing detected dialogue to likely speakers.

## Backlink

Parent specification:

- [Dialogue Span and Speaker Attribution](dialogue-span-and-speaker-attribution.md)

## Scope

This specification covers:

- the per-span speaker-attribution result
- attribution confidence and provenance
- provider substitution rules

## Behavior

For each detected dialogue span, the system must produce one attribution outcome:

- a likely speaker reference, or
- explicit unattributed dialogue

Each attribution result must preserve:

- the dialogue span id
- the attributed speaker reference when present
- confidence
- provenance such as heuristic inference, imported metadata, or future provider output

The attribution subsystem must support:

- a built-in heuristic provider
- future richer providers without changing downstream casting contracts

Downstream consumers must not depend on one specific attribution algorithm.

## Constraints

- speaker attribution is document-time work, not hot playback work
- unattributed dialogue must remain explicit
- attribution results must remain traceable to normalized segment ids and word ranges through their dialogue span references

## Acceptance

- the app can attribute likely speakers to dialogue spans when enough evidence exists
- the app can represent unattributed dialogue explicitly
- downstream cast management can consume a stable provider-independent result contract
