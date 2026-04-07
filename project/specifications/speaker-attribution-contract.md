# Speaker Attribution Contract

Status: draft

## Overview

This specification refines the speaker-attribution contract into narrower implementable units.

## Backlink

Parent specification:

- [Dialogue Span and Speaker Attribution](dialogue-span-and-speaker-attribution.md)

## Scope

This specification covers:

- the per-span speaker-attribution result
- rule trace and evidence requirements
- attribution conflict and unknown handling
- provider substitution rules

## Behavior

The parent branch now delegates detailed implementation to child specifications.

In particular:

- the attribution outcome schema belongs to its own leaf
- rule-priority and unknown-threshold behavior belong to their own leaf

This parent specification keeps only the branch-level contract that speaker attribution remains provider-independent and document-time.

## Constraints

- speaker attribution is document-time work, not hot playback work
- unattributed dialogue must remain explicit
- attribution results must remain traceable to normalized segment ids and word ranges through their dialogue span references

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Speaker Attribution Outcome Schema](speaker-attribution-outcome-schema.md)
- [Speaker Attribution Priority And Unknown Handling](speaker-attribution-priority-and-unknown-handling.md)

## Acceptance

- the app can attribute likely speakers to dialogue spans when enough evidence exists
- the app can represent unattributed dialogue explicitly
- downstream cast management can consume a stable provider-independent result contract
- the remaining work in this branch is represented by final leaf specifications
