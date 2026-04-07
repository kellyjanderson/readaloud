# Speaker Attribution Outcome Schema

Status: final

## Overview

This specification defines the per-quoted-span attribution output schema.

## Backlink

Parent specification:

- [Speaker Attribution Contract](speaker-attribution-contract.md)

## Scope

This specification covers:

- required attribution fields per quoted utterance
- explicit unknown handling
- traceability requirements for rule and evidence output

## Behavior

For each quoted utterance, the system must produce one attribution outcome.

Each outcome must carry:

- `speaker`
- `confidence`
- `rule_used`
- `evidence_span`

When no reliable speaker can be assigned, the result must still be emitted with:

- `speaker = unknown`
- the winning fallback rule or explicit `unknown` rule marker
- confidence representing that unresolved outcome

The outcome must remain traceable back to the quoted utterance and to the evidence span that justified the decision.

## Constraints

- the schema must remain provider-independent
- `rule_used` must describe the winning attribution rule, not an implementation-only debug string
- `evidence_span` must point to attached source text rather than a vague narrative description

## Acceptance

- every quoted utterance has a structured attribution outcome
- the outcome includes `speaker`, `confidence`, `rule_used`, and `evidence_span`
- unknown outcomes remain explicit rather than omitted
