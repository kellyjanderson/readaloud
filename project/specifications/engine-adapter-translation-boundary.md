# Engine Adapter Translation Boundary

Last updated: April 3, 2026
Status: Final specification

## Overview

This specification defines the boundary where app-owned chunk requests and pronunciation artifacts are converted into engine-native payloads.

## Backlink

Parent specification:

- [Engine Pronunciation Expression and Capability Adaptation](engine-pronunciation-expression-and-capability-adaptation.md)

## Scope

This specification covers:

- required adapter-boundary inputs
- ownership of engine-native payload construction
- required traceability outputs associated with payload construction

This specification does not redefine the pronunciation-translation outcome taxonomy or fallback classes already specified elsewhere.

## Behavior

### Required Inputs

Engine-adapter translation must consume:

- one runtime-ready chunk request
- one engine capability model
- the translation outcome chosen for each realized pronunciation artifact covered by that chunk

### Boundary Ownership Rule

Engine-native formatting and payload construction must happen only at the adapter boundary.

This includes:

- engine-specific text substitution
- engine-specific phoneme payload shaping
- engine-specific markup or tokenization quirks
- engine-specific phoneme inventory adaptation when canonical app-owned phoneme strings use a broader or different alphabet

These details must not become the canonical stored pronunciation representation.

### Payload Trace Rule

The adapter-boundary output must preserve enough traceability to identify:

- the chunk id being translated
- the artifact ids that influenced translation
- which artifacts were expressed directly, approximated, or deferred
- which capability profile was active during translation

### Canonical-Separation Rule

Adapter translation must derive engine-native payloads from canonical app-owned artifacts without mutating:

- `TtsArtifactSet`
- realized pronunciation artifacts
- cached document-time pronunciation artifacts

### Current-Engine Rule

For the current Kokoro path, direct phoneme use, normalized-spoken-text approximation, and plain-text fallback must all pass through this boundary rather than being scattered across controller or planner code.

When direct phoneme payloads are used, the adapter may translate canonical internal IPA into Kokoro/Misaki-specific phoneme symbols at this boundary, but that translation must remain downstream of canonical artifact ownership.

## Constraints

- The adapter boundary must not invent first-principles pronunciation policy from raw text when artifact-driven input exists.
- Engine-native payloads are derived artifacts and must remain replaceable if the engine changes.
- The adapter boundary must be usable by both interactive playback and export/headless synthesis.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Engine-native payload construction is confined to one explicit adapter boundary.
- Canonical app-owned pronunciation artifacts remain separate from engine-native formatting.
- Runtime and export paths can trace translated chunk payloads back to capability profile and artifact identity.
