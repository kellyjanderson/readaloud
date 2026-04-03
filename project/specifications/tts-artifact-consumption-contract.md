# TTS Artifact Consumption Contract

Last updated: March 31, 2026
Status: Draft specification

## Overview

This specification defines how pronunciation-aware TTS artifacts are consumed beyond the document and planning layers, especially at runtime and engine-adapter boundaries.

## Backlink

Parent specification:

- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)

## Scope

This specification covers:

- runtime request derivation from `TtsArtifactSet`
- engine-adapter translation of realized pronunciation artifacts
- fallback and traceability when realized artifacts cannot be expressed directly

This specification does not define runtime command envelopes or player behavior.

## Behavior

### Required Contract Boundary

The system must distinguish between:

- pronunciation-aware planning input already represented in `TtsArtifactSet`
- runtime chunk requests derived from that artifact set
- engine-adapter translation outcomes for each realized pronunciation artifact

### Required Runtime Behavior

Runtime chunk preparation must consume `TtsArtifactSet` without reconstructing pronunciation policy from raw text alone.

### Required Engine Behavior

Engine adapters must translate realized pronunciation artifacts explicitly and must surface whether each artifact was:

- directly expressed
- approximated
- deferred to engine-default behavior

### Required Fallback Behavior

If no realizable pronunciation artifact exists for a token range, the runtime may use engine-default behavior, but the fallback must remain distinguishable from a positive planner decision.

## Constraints

- canonical pronunciation/TTS artifacts remain engine-agnostic
- engine-specific markup or token payloads are derived artifacts, not canonical stored artifacts
- the remaining work under this contract must be refined into smaller implementation units before being considered final

## Refinement Status

This specification requires further refinement.

## Child Specifications

- [TTS Runtime Chunk Request Derivation](tts-runtime-chunk-request-derivation.md)
- [Engine Pronunciation Translation Policy](engine-pronunciation-translation-policy.md)
- [Pronunciation Fallback and Traceability](pronunciation-fallback-and-traceability.md)

## Acceptance

- The remaining runtime and engine-consumption work for `TtsArtifactSet` is split into implementation-sized child specifications.
- No broad unresolved runtime/adapter behavior remains hidden inside a single final leaf.
