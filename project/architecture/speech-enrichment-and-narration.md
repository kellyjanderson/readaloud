# Speech Enrichment and Narration

Last updated: March 31, 2026
Status: Active architecture

## Purpose

This document defines the architectural layer that bridges normalized speech content and natural long-form synthesis.

## Overview

`SpeechDocument` alone is not sufficient to reach the product’s target speech quality.

The system requires a speech enrichment layer that:

- infers phrase and pause structure from normalized text
- attaches speech-specific hints without altering display content
- separates cached document-time enrichment from live voice/session-time realization
- maintains narration continuity across sentences, chunks, and paragraphs

This layer is responsible for turning well-formed speech text into speech input that can sound natural and coherent over long-form reading.

## Components

### Speech Normalization Output

Input from the normalized content layer:

- sentence-first segments
- paragraph structure
- word spans
- stable ids

This is the base material for enrichment, not the final synthesis input.

### Document-Time Annotation Inference

This component infers voice-agnostic speech-side information from normalized content and context.

Responsibilities:

- phrase boundary inference
- pause class inference
- emphasis candidate inference
- pronunciation override inference
- future `say-as` style interpretation support
- operate as a lightweight, primarily rule-based pass suitable for document-open or background continuation

### BaseSpeechAnnotationSet

`BaseSpeechAnnotationSet` is the cached structural sidecar attached to normalized speech content.

Responsibilities:

- preserve inferred speech hints separately from source text
- keep annotation ownership on the speech side of the system
- give later layers a stable contract for pause, emphasis, pronunciation, and future marks

### Voice and Session Realization

This component realizes cached base annotations for the active playback situation.

Responsibilities:

- adapt base annotations to the selected voice and rate
- apply voice-specific pronunciation or prosody rules
- finalize accent-specific pronunciation and phoneme output
- use current narration context to avoid sentence-reset behavior
- operate only on the active playback window and immediate look-ahead
- emit the live speech realization consumed by chunk planning

### Pronunciation Planning

This component resolves pronunciation intent against the internal speech representation.

Responsibilities:

- identify where pronunciation should be carried explicitly rather than left to engine guesswork
- separate voice-agnostic pronunciation planning from active voice/session realization
- produce pronunciation-side artifacts that remain attached to internal speech content
- prepare the pronunciation-aware inputs consumed by the TTS layer

This component does not belong inside the engine adapter or live runtime queue.

### TTS Artifact Set

This is the pronunciation-aware synthesis input derived from enrichment and realization.

Responsibilities:

- preserve resolved pronunciation and related TTS intent as app-owned artifacts
- give chunk planning and the runtime a stable, inspectable contract
- allow export, headless execution, and future QA tooling to use the same speech truth as live playback

### NarrationState

`NarrationState` represents continuity across longer spans of speech.

Responsibilities:

- carry symbolic continuity between adjacent chunks
- preserve discourse mode such as heading, prose, list, caption, or dialogue
- preserve recent pause and emphasis context
- preserve continuation-versus-closure state at recent boundaries
- avoid sentence-by-sentence reset behavior

### Enriched Planner Input

This is the output contract consumed by chunk planning.

Responsibilities:

- combine `SpeechDocument`, `BaseSpeechAnnotationSet`, voice/session realization, and `NarrationState`
- expose chunk-plannable units that remain traceable to normalized content

## Relationships

- `BaseSpeechAnnotationSet` depends on `SpeechDocument`.
- voice/session realization depends on `BaseSpeechAnnotationSet`, the active voice, the active rate, and recent narration context.
- `NarrationState` depends on playback history and current enriched context.
- pronunciation planning depends on `SpeechDocument`, `BaseSpeechAnnotationSet`, current voice/session context, and existing lexical resources.
- Chunk planning consumes enriched speech input, not raw normalized text alone.
- the TTS layer consumes pronunciation-aware TTS artifacts, not only raw speech text.
- Rendering does not consume `SpeechAnnotationSet` directly, though future highlighting may use its marks or anchors.

## Data Flow

```text
SpeechDocument
  -> document-time annotation inference
  -> BaseSpeechAnnotationSet
  -> document-time pronunciation planning
  -> cached pronunciation artifacts
  -> voice and session realization
  -> voice/session pronunciation realization
  -> TTS Artifact Set
  -> narration-state update
  -> enriched planner input
  -> chunk planning
```

## Cross-Domain Solutions

### 1. Speech enrichment is separate from display content

The system must preserve display truth and speech truth independently.

Reason:

- the same displayed text may need pronunciation or pause behavior that is not visible on screen
- display rendering should not depend on engine-specific speech markup

### 2. Plain-text and PDF-derived speech need the same enrichment architecture

The system must not treat speech enrichment as a special case only for one source format.

Reason:

- most user documents will not arrive with useful TTS metadata
- imported formats differ visually, but often converge into the same speech problem

### 3. Narration quality requires memory

The system must not treat every sentence as a fully isolated utterance.

Reason:

- long-form naturalness depends on continuity
- the research consistently shows that paragraph and cross-sentence context matter

### 4. Annotation and narration state are engine-agnostic internal concepts

The enrichment layer defines what the app knows about intended speech behavior.

Engine-specific translation happens later.

Reason:

- engines vary in what controls they expose
- the app should not lose inferred speech intent just because the current engine cannot fully express it

### 5. Smoothness depends on a two-pass model

The system must not force all enrichment work to happen at play time.

Reason:

- some speech-side information is generic and reusable across voices
- some speech-side information depends on the active voice and playback context
- mixing both into one pass would make the product feel slower than necessary

### 6. Internal speech intent is richer than Kokoro’s direct control surface

The app must preserve more speech intent than Kokoro can currently express directly.

Reason:

- Kokoro exposes voice, rate, language/accent, chunking, and pronunciation help
- Kokoro does not expose a rich public API for explicit break strength, emphasis strength, or narrator-state injection
- the app still needs to retain those concepts for best-effort realization now and richer engines later

### 7. Pronunciation artifacts are part of speech enrichment, not engine-private state

The system must preserve pronunciation decisions as internal artifacts before runtime generation begins.

Reason:

- pronunciation is part of the app’s speech intent, not only an engine concern
- QA and export need to inspect the same pronunciation decisions as interactive playback
- the runtime becomes more stable when it consumes prepared artifacts instead of inventing pronunciation policy live

## Architectural Rules

- Pause and emphasis inference belong here, not in the UI or the player.
- Pronunciation overrides belong here, not in the importer output.
- Narration state persists across chunk boundaries within one playback session.
- Narration state is small and symbolic; it does not attempt to mirror model-internal acoustic state.
- Enrichment output must remain traceable to normalized segment ids and word ranges.
- Pronunciation artifacts must remain traceable to normalized segment ids, token ranges, and `PositionMap` anchors.
- Base document-time enrichment is cacheable per document.
- Voice/session-time realization is recalculated only for the active playback situation, not for every possible voice up front.
- Final phoneme strings are voice/session-time outputs, not universal whole-document cache content.
- Voice-specific rules are narrow and explicit, centered on pronunciation and realization, not broad hand-authored style tables.
- The TTS layer must consume pronunciation/TTS artifacts produced by this layer rather than reconstructing pronunciation policy from raw text alone.

## Current Implementation Gap

The current codebase now contains an initial implementation of this layer, but the architecture is still ahead of the code in important ways.

At present:

- base speech annotations, narration state, and profile-aware pronunciation realization all exist, but pause/emphasis richness is still limited
- chunk planning consumes speech-side structures, but long-form narration continuity is still relatively light
- profile-aware pronunciation realization exists, but the active rule-module set is still intentionally narrow
- more advanced prosody and emphasis behavior remains largely future work

## Governing Specifications

- [Speech Document](../specifications/speech-document.md)
- [Speech Annotation Set](../specifications/speech-annotation-set.md)
- [Voice and Session Realization](../specifications/voice-session-realization.md)
- [Narration State](../specifications/narration-state.md)
- [Chunk Planning](../specifications/chunk-planning.md)
- [Imported Document Playback](../specifications/imported-document-playback.md)
- [Pronunciation Artifact Model](../specifications/pronunciation-artifact-model.md)
- [Document-Time Pronunciation Planner](../specifications/document-time-pronunciation-planner.md)
- [Voice-Session Pronunciation Realization](../specifications/voice-session-pronunciation-realization.md)
- [TTS Artifact Consumption Contract](../specifications/tts-artifact-consumption-contract.md)
- [Pause and Break Taxonomy](../specifications/pause-and-break-taxonomy.md)
- [Pronunciation Diagnostics and Observability](../specifications/pronunciation-diagnostics-and-observability.md)

## Change Log

- March 30, 2026
  Description: Added the speech enrichment and narration architecture as a first-class architectural document, including a split between cached document-time enrichment and live voice/session realization.
  Reason: Research on prosody, pause control, audiobook-style continuity, and product smoothness showed that natural long-form speech requires a structural layer between normalized text and synthesis, and that not all of that work belongs on the play path.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Refined the architecture with lightweight document-time inference, windowed voice/session realization, a symbolic `NarrationState`, and explicit acknowledgement of Kokoro’s limited direct prosody controls.
  Reason: The follow-up research resolved what belongs in reusable annotations versus active realization, and clarified where the app must own speech intent above the current engine.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Expanded the document to include pronunciation planning and pronunciation-aware TTS artifacts as first-class speech-enrichment outputs.
  Reason: The pronunciation research pass showed that systemic pronunciation control needs its own internal artifact layer rather than ad hoc lexical or runtime-only fixes.
  Feature branch: `main`
  PR reference: `not opened yet`
