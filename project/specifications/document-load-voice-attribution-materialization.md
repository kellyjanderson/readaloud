# Document-Load Voice Attribution Materialization

Status: final

## Overview

This specification defines how narrator-versus-character attribution becomes first-class document-owned data during import.

## Backlink

Parent specification:

- [Multi-Voice Playback Routing](multi-voice-playback-routing.md)

## Scope

This specification covers:

- document-owned materialization of attributed spoken ranges
- narrator-versus-character ownership per spoken range
- separation between document-owned cast attribution and late-bound effective voice ids
- reuse of the same attribution structure by playback, export, and headless synthesis

## Behavior

At document load, the import pipeline must materialize a first-class attribution structure on the internal document model.

That structure must:

- cover the full spoken document, not only the dialogue spans
- resolve each spoken range to a stable cast identity
- preserve narrator ownership for non-quoted narration
- preserve character ownership for quoted dialogue when attribution succeeds
- preserve explicit dialogue identity for unattributed quoted speech without silently re-inferring it later
- preserve traceability back to normalized segment ids and word bounds

This document-owned attribution layer must not embed final effective voice ids.

Instead:

- the document owns speaker and cast attribution
- the active session owns the final effective voice assignment for each cast entry
- playback, export, and headless generation join those two layers rather than rescanning the document for speaker identity

## Constraints

- document-owned voice attribution is import-time work, not controller-time inference
- the internal document structure must expose the attribution layer as first-class data
- user overrides may change effective voices, but they must not change the underlying narrator-versus-character ownership of spoken ranges
- playback preparation must consume the materialized attribution structure instead of re-deriving speaker ownership from lower-level annotations

## Acceptance

- an imported document exposes a first-class narrator-versus-character attribution structure
- the structure covers both quoted dialogue and surrounding narration
- playback, export, and headless synthesis can consume the same document-owned attribution without rescanning dialogue context
- effective voice ids can still vary by narrator choice and user override without invalidating the document-owned attribution layer
