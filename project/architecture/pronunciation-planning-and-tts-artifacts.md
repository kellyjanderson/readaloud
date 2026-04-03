# Pronunciation Planning and TTS Artifacts

Last updated: April 3, 2026
Status: Active architecture

## Purpose

This document defines how `Read Aloud` turns normalized speech content into inspectable, durable pronunciation and TTS artifacts that are then consumed by the TTS layer.

## Overview

Pronunciation must not be decided ad hoc inside the live runtime path.

The system requires a pronunciation-planning layer that:

- operates on the internal speech representation rather than raw source text
- makes pronunciation decisions with more context than isolated word tokenization
- distinguishes between reusable document-time pronunciation knowledge and active voice/session realization
- emits durable TTS artifacts that the runtime and engine adapters consume without re-deciding pronunciation from scratch

This layer exists because:

- one-off lexical fixes are not a systemic solution
- function words and inflected forms are often context-sensitive
- live runtime tokenization is the wrong place to invent pronunciation behavior under playback pressure
- playback smoothness and pronunciation quality must both be preserved
- English pronunciation behavior must remain modular enough to support multiple English variants and future accented-English overlays

## Components

### Pronunciation Planning Input

This is the normalized speech-facing input used by the pronunciation planner.

It consists of:

- `SpeechDocument`
- `BaseSpeechAnnotationSet`
- `PositionMap`
- importer diagnostics relevant to speech quality
- optional existing lexical resources such as bundled app lexicons or future user dictionaries

Responsibilities:

- provide stable ids, segment boundaries, and word ranges
- provide paragraph, dialogue, and phrase context
- provide the base context needed for pronunciation decisions

### Document-Time Pronunciation Analysis

This is the voice-agnostic pronunciation pass that runs on normalized content.

Responsibilities:

- identify pronunciation-sensitive tokens and token ranges
- detect names, inflected forms, contractions, possessives, dialogue-heavy turns, and other cases likely to need explicit handling
- resolve high-confidence lexical pronunciations that do not depend on the active voice
- record uncertainty when the planner cannot confidently resolve a pronunciation
- remain lightweight enough to run at document-open time or in background continuation after open

This pass does not produce engine-specific commands. It produces app-owned pronunciation intent.

### Base Pronunciation Artifact Set

This is the cached pronunciation sidecar attached to the internal representation.

Responsibilities:

- preserve document-time pronunciation decisions without mutating `SpeechDocument`
- store token- or range-level pronunciation intent
- store the source of each decision, such as lexicon, heuristic, imported annotation, or unresolved fallback
- store confidence and diagnostic information

This artifact set is part of the internal speech representation, not an engine cache.

### Voice and Session Pronunciation Realization

This is the active-pass pronunciation realization layer.

Responsibilities:

- adapt base pronunciation artifacts to the selected voice, accent, rate, and current narration state
- decide which pronunciation choices remain stable and which must vary by active session
- resolve function-word and phrase-level cases that depend on neighboring context
- produce playback-window-scoped pronunciation output rather than whole-document recomputation

This layer is distinct from document-time analysis because not all pronunciation decisions are safely voice-agnostic.

This layer must also remain compatible with selectable English pronunciation profiles and future accent-overlay behavior.

### TTS Artifact Set

This is the final internal artifact set consumed by chunk planning and the TTS layer.

Responsibilities:

- bind chunk-plannable speech units to resolved pronunciation decisions
- provide engine-agnostic TTS intent that can be translated into engine-specific inputs later
- preserve token, segment, and range traceability back to `SpeechDocument` and `PositionMap`
- remain inspectable for QA, export sidecars, and future tooling

Examples of TTS artifacts include:

- resolved pronunciation for a token or token range
- pronunciation source and confidence
- pronunciation fallback class
- tokenization guidance for the active window
- future prosody, pause, or emphasis payloads once those are formalized

### Engine Adapter Translation

This is the final boundary between internal TTS artifacts and the active speech engine.

Responsibilities:

- translate internal TTS artifacts into the narrow control surface supported by the active engine
- preserve as much app-owned pronunciation intent as the engine can express
- degrade gracefully when the engine cannot express all internal detail
- adapt canonical internal IPA to engine-specific phoneme inventories where a direct-phoneme engine path requires it

This layer must not invent new pronunciation decisions that bypass the planner.

### Engine Capability and Expression Adaptation

This is the capability-aware layer that decides how planner-owned pronunciation intent is expressed to the active engine.

Responsibilities:

- determine whether each artifact can be expressed directly, approximated, or deferred
- keep capability modeling explicit rather than implicit in adapter code
- preserve pronunciation traceability across expression and fallback decisions

### Pronunciation Diagnostics

This is the observability layer associated with pronunciation planning.

Responsibilities:

- expose unresolved or low-confidence cases
- preserve enough metadata for headless QA, export sidecars, and future pronunciation review tools
- support targeted regression work on specific names, inflections, or dialogue patterns

## Relationships

- `SpeechDocument`, `BaseSpeechAnnotationSet`, and `PositionMap` feed pronunciation planning.
- document-time pronunciation analysis emits `BasePronunciationArtifactSet`.
- voice and session pronunciation realization consumes `BasePronunciationArtifactSet`, active voice/rate, and `NarrationState`.
- `TTS Artifact Set` is the pronunciation-aware planner output consumed by chunk planning and the engine adapter boundary.
- the speech runtime consumes TTS artifacts; it does not own first-principles pronunciation planning.
- engine-expression adaptation sits between canonical TTS artifacts and engine-native payload construction.
- export and headless execution use the same TTS artifacts as interactive playback.

## Data Flow

```text
SpeechDocument + BaseSpeechAnnotationSet + PositionMap
  -> document-time pronunciation analysis
  -> BasePronunciationArtifactSet
  -> voice and session pronunciation realization
  -> TTS Artifact Set
  -> runtime chunk request derivation
  -> engine capability and expression adaptation
  -> engine adapter translation
  -> speech runtime boundary
  -> synthesis
```

## Cross-Domain Solutions

### 1. Pronunciation belongs to the internal representation, not only the engine

The app must own pronunciation intent in its internal representation.

Reason:

- the same document may be spoken by multiple voices or engines
- playback, export, and QA need one shared pronunciation truth
- runtime engine behavior alone is not inspectable enough for product-quality tuning

### 2. Pronunciation planning is split into document-time and voice/session-time passes

The system must distinguish between:

- reusable pronunciation knowledge that can be cached with the document
- context-sensitive realization that depends on the active voice, rate, and narration window

Reason:

- some names and inflected words are stable enough to resolve early
- function words and phrase-sensitive pronunciation often require more active context
- doing everything on the play path would hurt smoothness

### 3. The runtime consumes artifacts; it does not improvise pronunciation

The speech runtime must not be the place where pronunciation policy is invented.

Reason:

- runtime responsibilities are already complex: queueing, chunk generation, caching, and boundary handling
- pronunciation experimentation inside the runtime creates instability
- deterministic playback is easier when the runtime consumes prepared artifacts

### 4. Engine-specific markup is not the app’s canonical representation

Inline engine-specific markup must not become the app’s long-term internal speech format.

Reason:

- engines expose different control surfaces
- some markup forms are brittle on long-form inputs
- the app needs one durable representation even when engine adapters differ

The same rule applies to phoneme alphabets:

- internal pronunciation artifacts may use standard IPA
- Kokoro/Misaki-specific phoneme symbols belong only at the engine adapter edge

### 5. Context-sensitive function words require structural handling

Words such as `for` must not be treated the same way as isolated proper names or obvious lexical misses.

Reason:

- reduced forms and contextual pronunciation are sensitive to neighboring phrasing
- blanket lexical overrides can make many normal cases worse
- this is exactly the kind of problem that the active realization layer should own

### 6. Pronunciation diagnostics are part of the architecture

The system must preserve enough evidence to understand why a pronunciation choice happened.

Reason:

- iterative TTS tuning depends on being able to inspect resolved pronunciation behavior
- headless export and QA become much more useful when pronunciation decisions are visible

### 7. English pronunciation behavior must be profile-aware and modular

The system must support multiple English rule/resource combinations through explicit pronunciation profiles and rule modules.

Reason:

- English pronunciation is not one universal fixed policy
- future support for `en-gb`, `en-au`, and accented-English overlays requires modularity
- productive rules and lexical resources need a clean way to vary by profile

## Architectural Rules

- The internal representation must be able to carry pronunciation and TTS artifacts as first-class speech-side sidecars.
- Document-time pronunciation planning must not mutate display content.
- Voice/session pronunciation realization must be limited to the active playback or export window.
- The TTS layer must accept pronunciation/TTS artifacts from the internal representation rather than reconstructing pronunciation policy from raw text alone.
- Engine adapters may translate or degrade internal TTS artifacts, but they must not silently replace planner decisions with unrelated engine guesses when a planner decision exists.
- Lexicon resources are one input to pronunciation planning, not the entire architecture.
- Context-sensitive pronunciation must be handled structurally, not by growing an unbounded list of blind one-off lexical patches.
- Pronunciation artifacts must remain traceable to stable segment ids, token ranges, and `PositionMap` anchors.
- English pronunciation rules and resources must be modular enough to support selectable profiles and future accent overlays.
- Engine capability-aware expression must remain downstream of planner-owned pronunciation artifacts rather than replacing them.

## Current Implementation Gap

The current codebase now implements this branch as first-class system behavior, but some edges remain intentionally narrow:

- the app has document-time pronunciation artifacts, profile-aware planning, voice/session realization, engine translation outcomes, and durable pronunciation observability
- the live engine path still uses plain-text fallback for uncovered tokens when no artifact-driven direct or approximated expression exists
- the current English rule/resource set and pronunciation QA tooling are strong for the Kokoro path, but broader multi-engine and multi-profile coverage remains future work
- context-sensitive prosody and function-word handling are implemented selectively rather than exhaustively

## Governing Specifications

- [Pronunciation Artifact Model](../specifications/pronunciation-artifact-model.md)
- [Document-Time Pronunciation Planner](../specifications/document-time-pronunciation-planner.md)
- [Voice-Session Pronunciation Realization](../specifications/voice-session-pronunciation-realization.md)
- [TTS Artifact Consumption Contract](../specifications/tts-artifact-consumption-contract.md)
- [TTS Runtime Chunk Request Derivation](../specifications/tts-runtime-chunk-request-derivation.md)
- [Engine Pronunciation Translation Policy](../specifications/engine-pronunciation-translation-policy.md)
- [Pronunciation Fallback and Traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [Pronunciation Diagnostics and Observability](../specifications/pronunciation-diagnostics-and-observability.md)
- [Speech QA Debug Tooling](../specifications/speech-qa-debug-tooling.md)

## Related Architecture

- [Speech Enrichment and Narration](speech-enrichment-and-narration.md)
- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)
- [Engine Pronunciation Expression and Capability Adaptation](engine-pronunciation-expression-and-capability-adaptation.md)
- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)
- [System Overview](system-overview.md)
- [Document and Speech Pipeline](document-speech-pipeline.md)
- [Normalized Content and Position Mapping](normalized-content-and-position-mapping.md)
- [Playback Orchestration and Synthesis Boundaries](playback-orchestration-and-synthesis-boundaries.md)

## Change Log

- March 30, 2026
  Description: Added pronunciation planning and TTS artifacts as a first-class architecture layer between speech enrichment and runtime generation.
  Reason: Research and implementation friction showed that systemic pronunciation control needs to live in the internal representation and be passed into the TTS layer as explicit artifacts rather than improvised inside the live runtime path.
  Feature branch: `main`
  PR reference: `not opened yet`
