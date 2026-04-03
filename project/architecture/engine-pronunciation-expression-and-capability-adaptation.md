# Engine Pronunciation Expression and Capability Adaptation

Last updated: April 3, 2026
Status: Active architecture

## Purpose

This document defines how `Read Aloud` converts app-owned pronunciation and TTS artifacts into engine-expressible inputs without surrendering pronunciation ownership to any one engine.

## Overview

The system now owns pronunciation planning internally, but that does not mean every engine can directly express every planned decision.

`Read Aloud` therefore needs an explicit engine-expression architecture that:

- derives runtime-ready chunk requests from chunk planning and TTS artifacts
- understands the control surface of the active engine
- chooses how each pronunciation decision will be expressed
- records whether a pronunciation decision was expressed directly, approximated, or deferred
- keeps engine-specific control surfaces downstream of the app-owned artifact model

This architecture exists because the remaining pronunciation-quality problems are no longer only planner problems. They also depend on how planner-owned intent is adapted to the actual engine.

## Components

### Runtime Chunk Request Derivation

This component derives runtime-ready chunk requests from:

- `ChunkPlan`
- `TtsArtifactSet`
- active engine id and version
- selected voice and rate

Responsibilities:

- preserve chunk ordering and text span ownership
- attach the pronunciation and TTS artifacts relevant to each chunk
- keep runtime requests small, deterministic, and traceable

### Engine Capability Model

This is the app-owned description of what an engine can actually accept and express.

Responsibilities:

- declare whether the engine supports direct phoneme strings, normalized spoken text, or only plain text
- declare whether expression behavior differs by platform or engine version
- keep capability checks explicit rather than implicit in adapter code

Examples:

- direct phoneme expression available
- normalized spoken-text substitution available
- only engine-default text path available

### Engine Pronunciation Expression

This component chooses how each realized pronunciation artifact is expressed to the engine.

Responsibilities:

- map app-owned pronunciation artifacts to engine-expressible forms
- preserve the selected pronunciation profile and active voice context
- choose among direct, approximated, or deferred expression paths

This component does not re-plan pronunciation. It only decides how already-owned intent is expressed through the active engine.

### Engine Adapter Translation

This is the final engine-facing adapter layer.

Responsibilities:

- build the actual engine input payload
- keep engine-native formatting, tokenization constraints, and quirks confined to one place
- use the chosen expression path from the engine-expression layer
- adapt canonical app-owned phoneme strings to the active engine's accepted phoneme inventory when direct phoneme expression is used

This is where Kokoro-specific or future engine-specific formatting belongs.

For the current Kokoro path, this layer includes translation from canonical internal IPA into the Kokoro/Misaki token inventory expected by direct-phoneme tokenization.

### Fallback and Traceability

This component preserves what happened when expression was not exact.

Responsibilities:

- record whether a pronunciation decision was expressed directly, approximated, or deferred
- preserve which artifact or range the outcome applies to
- expose those outcomes to runtime diagnostics, export sidecars, and future QA tooling

## Relationships

- `Pronunciation Planning and TTS Artifacts` produces canonical app-owned pronunciation intent.
- `English Pronunciation Profiles and Rule Modularity` determines which profile and rule/resource combination shaped that intent.
- `Runtime Chunk Request Derivation` packages the relevant artifact subsets for generation.
- `Engine Capability Model` constrains what the adapter may attempt.
- `Engine Pronunciation Expression` chooses how each artifact is expressed for the active engine.
- `Engine Adapter Translation` produces the concrete engine payload used by the runtime worker.
- `Fallback and Traceability` records any degradation between planned intent and actual engine expression.

## Data Flow

```text
TTS Artifact Set + ChunkPlan
  -> runtime chunk request derivation
  -> engine capability lookup
  -> engine pronunciation expression
  -> engine adapter translation
  -> speech runtime worker
  -> synthesis
  -> pronunciation traceability and diagnostics
```

## Cross-Domain Solutions

### 1. Pronunciation ownership stays above the engine

The app must continue to own pronunciation truth even when the engine cannot express every detail.

Reason:

- planner-owned intent must remain inspectable
- export and QA need to see the same pronunciation truth as playback
- switching engines should not require re-inventing the app’s pronunciation model

### 2. Engine capability must be explicit

The system must not infer engine support opportunistically from scattered adapter behavior.

Reason:

- hidden capability assumptions make fallback behavior unpredictable
- platform differences can change what an engine can express
- explicit capability modeling makes future engines much easier to add

### 3. Expression outcome classes are first-class system behavior

The accepted outcome classes are:

- direct
- approximated
- deferred

Reason:

- not every artifact can be expressed equally well
- the system needs one shared vocabulary for runtime, export, and QA
- pronunciation debugging becomes much easier when degradation is visible

### 4. Approximation is allowed, silent replacement is not

If the engine cannot express the exact planned pronunciation, the adapter may approximate or defer, but it must not silently replace the planner’s intent with unrelated engine guesses while pretending nothing changed.

Reason:

- hidden degradation makes pronunciation tuning nearly impossible
- user trust depends on consistent behavior across playback and export

### 5. Engine-native formatting is a leaf concern

Engine-native markup, tokenization quirks, and payload construction belong at the adapter edge.

Reason:

- the canonical app model must remain engine-agnostic
- the adapter is where engine-specific behavior should be isolated

This includes engine-specific phoneme alphabets.

Canonical app-owned pronunciation data may use standard IPA internally, while the adapter translates that IPA to an engine-specific inventory only for the active engine payload.

## Architectural Rules

- Engine capability must be represented explicitly in app-owned code.
- Runtime chunk requests must preserve the artifact ids and ranges that shaped them.
- Engine adapters must not invent first-principles pronunciation policy from raw text when planner-owned pronunciation artifacts already exist.
- Direct, approximated, and deferred expression outcomes must remain visible beyond the adapter boundary.
- Engine-native markup must not become the canonical internal pronunciation representation.
- Engine-specific phoneme alphabets must not become the canonical internal pronunciation representation.
- Adding a new engine requires both a capability model and an expression strategy, not only a raw adapter implementation.

## Current Implementation Gap

The codebase now implements this layer clearly for the current engine path, with narrower remaining gaps:

- the Kokoro path has explicit capability modeling, translation outcomes, adapter-boundary payload construction, and canonical IPA to Kokoro/Misaki inventory adaptation
- direct, approximated, and deferred outcomes are traceable and affect cache identity for the current engine path
- broader multi-engine capability coverage and additional engine-specific inventory adapters remain future work
- some remaining pronunciation rough edges now reflect planner/rule coverage rather than missing adapter-boundary ownership

## Governing Specifications

- [Engine Pronunciation Expression and Capability Adaptation](../specifications/engine-pronunciation-expression-and-capability-adaptation.md)
- [Engine Capability Model](../specifications/engine-capability-model.md)
- [Engine Adapter Translation Boundary](../specifications/engine-adapter-translation-boundary.md)
- [Kokoro Phoneme Inventory Adaptation](../specifications/kokoro-phoneme-inventory-adaptation.md)
- [TTS Artifact Consumption Contract](../specifications/tts-artifact-consumption-contract.md)
- [TTS Runtime Chunk Request Derivation](../specifications/tts-runtime-chunk-request-derivation.md)
- [Engine Pronunciation Translation Policy](../specifications/engine-pronunciation-translation-policy.md)
- [Pronunciation Fallback and Traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [Engine Intent Translation Policy](../specifications/engine-intent-translation-policy.md)
- [Platform Capability and Fallback Policy](../specifications/platform-capability-and-fallback-policy.md)

## Related Architecture

- [System Overview](system-overview.md)
- [Document and Speech Pipeline](document-speech-pipeline.md)
- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)
- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)
- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)
