# Voice and Session Realization

Last updated: March 31, 2026
Status: Draft specification

## Overview

This specification defines how cached base speech annotations are realized for the active voice, rate, engine, and playback window.

## Backlink

Parent architecture:

- [Speech Enrichment and Narration](../architecture/speech-enrichment-and-narration.md)

## Scope

This specification covers:

- realization inputs
- realization invalidation behavior
- the shared realization envelope consumed by chunk planning and runtime derivation
- non-pronunciation realization of boundary and emphasis intent

This specification does not define model inference or audio generation.

## Behavior

The parent branch now delegates the detailed payload contracts to child specifications.

In particular:

- pronunciation-specific realization belongs to the pronunciation branch
- shared realization-envelope behavior belongs to its own leaf
- boundary-intent realization and emphasis-intent realization are separate implementation concerns

This parent specification keeps only the branch-level contract that those concerns must compose into one active realization layer.

## Constraints

- realization is downstream of `BaseSpeechAnnotationSet`
- realization must not rewrite normalized segment ids
- realization must stay independent from current queue ownership
- realized output must remain traceable back to segment ids and word ranges

## Refinement Status

This specification requires further refinement.

## Child Specifications

- [Voice Session Realization Envelope](voice-session-realization-envelope.md)
- [Realization Window Policy](realization-window-policy.md)
- [Boundary Intent Realization](boundary-intent-realization.md)
- [Emphasis Intent Realization](emphasis-intent-realization.md)
- [Pronunciation Realization Precedence](pronunciation-realization-precedence.md)
- [Engine Intent Translation Policy](engine-intent-translation-policy.md)

## Acceptance

- Voice changes trigger realization-window updates, not whole-document structural recomputation.
- Pronunciation-specific realization remains separated from base document-time annotation caching and from non-pronunciation realization concerns.
- The remaining work in this branch is represented by final leaf specifications.
