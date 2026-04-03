# Pronunciation Planning and TTS Artifacts

Last updated: March 30, 2026
Status: Draft specification

## Overview

This specification defines how pronunciation planning and pronunciation-aware TTS artifacts are represented and passed from the internal speech model into the TTS layer.

## Backlink

Parent architecture:

- [Pronunciation Planning and TTS Artifacts](../architecture/pronunciation-planning-and-tts-artifacts.md)

## Scope

This specification covers:

- pronunciation-planning inputs
- document-time pronunciation artifacts
- voice/session pronunciation realization
- TTS artifact consumption by chunk planning and runtime generation
- pronunciation diagnostics

This specification does not define chunk audio generation or playback queue behavior.

## Behavior

### Required Structural Split

The system must distinguish between:

- document-time pronunciation artifacts that can be cached with the normalized document
- voice/session pronunciation realization scoped to the active playback or export window
- pronunciation-aware TTS artifacts consumed by chunk planning and runtime generation

### Required Input Layer

Pronunciation planning must operate from:

- `SpeechDocument`
- `BaseSpeechAnnotationSet`
- `PositionMap`
- speech-relevant importer diagnostics
- lexical resources available to the app

The planner must not operate from display-side HTML or engine-generated audio.

### Required Output Layers

The architecture must produce:

- `BasePronunciationArtifactSet`
- `VoiceSessionPronunciationRealization`
- `TtsArtifactSet`

These outputs must remain traceable to normalized segment ids and word ranges.

### Planner Ownership Rule

The speech runtime and engine adapters must consume pronunciation/TTS artifacts. They must not be the place where first-principles pronunciation policy is invented for the active session.

### Context Rule

The system must support both:

- stable lexical cases such as names and known inflected forms
- context-sensitive cases such as function words and phrase-sensitive pronunciation

Blanket lexical replacement is not sufficient for the full problem.

## Constraints

- engine-specific inline markup is not the canonical internal pronunciation format
- pronunciation artifacts must not mutate display content
- document-time pronunciation work must remain lightweight enough for document-open or background continuation
- voice/session pronunciation realization must remain windowed and must not force whole-document recomputation on every play action

## Refinement Status

This specification requires further refinement.

## Child Specifications

- [Pronunciation Artifact Model](pronunciation-artifact-model.md)
- [Document-Time Pronunciation Planner](document-time-pronunciation-planner.md)
- [Voice-Session Pronunciation Realization](voice-session-pronunciation-realization.md)
- [TTS Artifact Consumption Contract](tts-artifact-consumption-contract.md)
- [Pronunciation Diagnostics and Observability](pronunciation-diagnostics-and-observability.md)

## Acceptance

- Pronunciation planning is modeled as its own internal speech-side subsystem.
- The TTS layer consumes explicit pronunciation-aware artifacts instead of relying only on raw speech text.
- The architecture distinguishes document-time pronunciation work from active voice/session realization.
