# System Overview

Last updated: April 3, 2026
Status: Active architecture

## Purpose

This document defines the major system layers and responsibility boundaries for `Read Aloud`.

## System Summary

`Read Aloud` is a Flutter-based document reader that:

- accepts documents from native open, share, drag-and-drop, and paste flows
- accepts desktop command-line startup inputs
- renders a rich reading surface
- converts normalized document content into speech
- infers speech structure and narration hints from plain or lightly structured text
- separates document-time speech enrichment from voice/session-time realization
- carries pronunciation and TTS artifacts in the internal speech representation rather than inventing pronunciation policy in the live runtime
- adapts app-owned pronunciation artifacts through explicit engine capability-aware expression
- routes repeated speech work through an explicit runtime messaging boundary
- keeps the document-open path lightweight enough to feel responsive on older desktop and future mobile targets
- coordinates playback, navigation, export, pronunciation QA tooling, and future highlighting

## Major Layers

### Platform Integration

Responsibilities:

- native file open events
- share-in flows
- desktop command-line startup arguments
- local storage paths
- app sandbox and entitlement boundaries

This layer delivers file or text input into the intake layer. It does not parse or normalize document content.

### Document Intake and Import

Responsibilities:

- file type detection
- source-specific parsing for text, HTML, EPUB, PDF, DOCX, and RTF
- rule-based structural normalization and importer diagnostics on the document-open path
- production of normalized internal document representations

This layer must preserve enough structure for both rendering and speech, rather than flattening all imported content into one raw text string.

### Normalized Content Layer

Responsibilities:

- maintain a stable internal representation of display structure
- maintain a stable internal representation of speech structure
- maintain a hybrid position map based on offsets plus recovery anchors
- preserve ids, offsets, and mapping needed for playback and future highlighting

This layer is the contract boundary between importers and the speech/rendering systems.

### Speech Enrichment and Narration

Responsibilities:

- infer phrase boundaries, pause classes, emphasis candidates, and pronunciation hints from normalized speech content
- perform document-time, voice-agnostic enrichment that can be cached with the document
- perform voice/session-specific realization only for the active playback window
- preserve speech-side annotations separately from display structure
- maintain a small symbolic narration state across sentences, chunks, and paragraphs
- prepare enriched speech input for chunk planning and synthesis

This layer is where the system bridges the gap between well-formed text and natural long-form speech.

### Pronunciation Planning and TTS Artifacts

Responsibilities:

- perform document-time pronunciation analysis over normalized speech content
- produce durable pronunciation artifacts attached to the internal representation
- realize pronunciation decisions for the active voice and session window
- provide TTS artifacts that the runtime and engine adapter consume without re-deciding pronunciation from raw text alone

This layer exists so pronunciation becomes an app-owned part of the speech model instead of an unstable side effect of live runtime tokenization.

### Engine Pronunciation Expression and Capability Adaptation

Responsibilities:

- derive runtime-ready chunk requests from chunk plans and TTS artifacts
- model what the active engine can directly express
- translate app-owned pronunciation intent into engine-expressible input
- preserve direct, approximated, and deferred pronunciation outcomes
- translate canonical internal IPA to engine-specific phoneme inventories only at the engine boundary when the active engine requires it

This layer bridges canonical speech intent and the narrower control surface of the active engine.

### Speech Planning and Generation

Responsibilities:

- sentence-first chunk planning from enriched speech content, with clause fallback only when necessary
- define the inputs consumed by the speech runtime

Heavy speech work does not belong directly in controller or UI code.

### Speech Runtime Boundary

Responsibilities:

- expose a command/event façade between controller code and background speech work
- own long-lived worker lifecycle for repeated generation work
- keep isolate boundaries DTO-only and sendable
- coordinate native engine adapter calls and queue policy
- contain phonemization, model inference, wav generation, synthesis-boundary handling, cache operations, and generation diagnostics behind one runtime contract

This layer exists because “run some work in an isolate” is not, by itself, a stable subsystem architecture in Flutter.

### Playback Coordination

Responsibilities:

- queue prepared audio chunks
- start playback once the first chunk is ready
- generate later chunks behind playback
- map progress back to normalized speech segments
- support jump timing, replay, and future highlighting

### Audio Export and Headless Execution

Responsibilities:

- resolve launch mode between interactive UI and headless export
- export spoken output to durable files
- assemble finalized chunk audio into one saved result
- run automation-oriented pronunciation probe and sentence-probe harnesses through the same speech pipeline
- reuse the same importer, planning, runtime, and boundary-correction path in both interactive and headless flows

### Presentation and Control

Responsibilities:

- reader UI
- transport controls
- buffering and playback state presentation
- document rendering
- settings and voice selection
- live file-fed document refresh and current-session TTS trace inspection

The UI layer consumes derived state. It should not own importer parsing or heavy inference work.

Headless execution reuses the same system layers but bypasses presentation.

## Cross-Layer Rules

- Importers do not call Kokoro directly.
- The UI does not decide chunk boundaries.
- The controller does not call speech plugins or native speech adapters directly.
- Pause, emphasis, and narration inference are not UI responsibilities.
- Pronunciation policy is not a live runtime improvisation concern.
- Document open completes after normalized content, mapping, and base importer diagnostics are available; deeper enrichment may continue in the background.
- Heavy voice-agnostic enrichment should happen before the user presses play whenever practical, but should remain rule-based and linear on the open path.
- Voice/session-specific realization must be windowed tightly enough that first-audio latency remains low.
- Repeated speech work must flow through the runtime messaging boundary rather than ad hoc per-call closure offloads.
- Exported audio is assembled from finalized chunk outputs after boundary correction, not from a separate raw synthesis path.
- `PositionMap` uses offsets for speed and recovery anchors for resilience.
- Internal speech intent may be richer than the current engine can directly express; engine adapters perform best-effort translation.
- Pronunciation artifacts belong to the internal speech representation and are passed into the TTS layer as inputs, not reconstructed from scratch inside engine adapters.
- Engine capability and pronunciation-expression policy must be explicit and inspectable, not hidden in ad hoc adapter behavior.
- Standard IPA may be used internally, but engine-specific phoneme alphabets must remain an adapter-boundary concern rather than a canonical app data format.
- Synthesis-boundary policy is centralized and must not be recreated independently in the player or the UI.
- Synthesis-boundary policy uses trim-and-cap join handling by default, not blind overlap or player-added gaps.
- Playback progress must remain traceable to stable normalized segment ids.
- Display structure and speech structure must be related but not collapsed into one raw string.

## Current Implementation Gap

The current codebase now follows most of this architecture, with a smaller set of deliberate compatibility shims and still-narrow feature areas:

- normalized importer output, display/speech documents, position mapping, speech annotations, pronunciation artifacts, runtime messaging, boundary correction, export, and speech QA tooling are all first-class in code
- `ReaderDocument` still exposes compatibility views such as `displayHtml`, `speakableText`, and coarse word spans for current UI and export callers even though normalized models are the underlying source of truth
- speech enrichment, narration continuity, and profile-aware pronunciation behavior are implemented, but prosody richness and long-form delivery variation remain narrower than the target architecture
- engine capability modeling and adapter-boundary pronunciation expression are explicit for the current Kokoro path, including canonical IPA to Kokoro/Misaki inventory adaptation, but broader multi-engine support remains future work
- runtime, export, and debugging flows are well represented on current native targets, while broader cross-platform verification still trails the architectural target

## Governing Specifications

### Normalized Content Layer

- [Normalized Document Model](../specifications/normalized-document-model.md)
- [Display Document](../specifications/display-document.md)
- [Speech Document](../specifications/speech-document.md)
- [Importer Normalization Contract](../specifications/importer-normalization-contract.md)
- [PositionMap](../specifications/position-map.md)

### Speech Enrichment and Narration

- [Speech Annotation Set](../specifications/speech-annotation-set.md)
- [Voice and Session Realization](../specifications/voice-session-realization.md)
- [Narration State](../specifications/narration-state.md)

### Pronunciation Planning and TTS Artifacts

- [Pronunciation Artifact Model](../specifications/pronunciation-artifact-model.md)
- [Document-Time Pronunciation Planner](../specifications/document-time-pronunciation-planner.md)
- [Voice-Session Pronunciation Realization](../specifications/voice-session-pronunciation-realization.md)
- [TTS Artifact Consumption Contract](../specifications/tts-artifact-consumption-contract.md)

### Engine Pronunciation Expression and Capability Adaptation

- [TTS Runtime Chunk Request Derivation](../specifications/tts-runtime-chunk-request-derivation.md)
- [Engine Pronunciation Translation Policy](../specifications/engine-pronunciation-translation-policy.md)
- [Pronunciation Fallback and Traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [Engine Intent Translation Policy](../specifications/engine-intent-translation-policy.md)
- [Platform Capability and Fallback Policy](../specifications/platform-capability-and-fallback-policy.md)

### Speech Planning and Generation

- [Imported Document Playback](../specifications/imported-document-playback.md)
- [Chunk Planning](../specifications/chunk-planning.md)
- [Speech Worker Pipeline](../specifications/speech-worker-pipeline.md)
- [Generated Audio Cache](../specifications/generated-audio-cache.md)
- [Synthesis Boundary Policy](../specifications/synthesis-boundary-policy.md)
- [Playback Quality Instrumentation](../specifications/playback-quality-instrumentation.md)

### Speech Runtime Boundary

- [Speech Runtime Messaging Boundary](../specifications/speech-runtime-messaging-boundary.md)
- [Sendable Runtime DTO Contract](../specifications/sendable-runtime-dto-contract.md)
- [Speech Runtime Lifecycle and Ownership](../specifications/speech-runtime-lifecycle-and-ownership.md)
- [Speech Runtime Command Protocol](../specifications/speech-runtime-command-protocol.md)
- [Speech Runtime Event Protocol](../specifications/speech-runtime-event-protocol.md)
- [Native Engine Queue Policy](../specifications/native-engine-queue-policy.md)
- [Platform Capability and Fallback Policy](../specifications/platform-capability-and-fallback-policy.md)

### Playback Coordination

- [Playback Coordination](../specifications/playback-coordination.md)
- [Playback Progress and Jump Mapping](../specifications/playback-progress-and-jump-mapping.md)

### Reader Session and Live Input

- [Reader Session Continuity and Live Input](../specifications/reader-session-continuity-and-live-input.md)

### Audio Export and Headless Execution

- [Audio Export and Headless Execution](../specifications/audio-export-and-headless-execution.md)
- [Speech QA Debug Tooling](../specifications/speech-qa-debug-tooling.md)

## Related Architecture

- [Normalized Content and Position Mapping](normalized-content-and-position-mapping.md)
- [Speech Enrichment and Narration](speech-enrichment-and-narration.md)
- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)
- [Engine Pronunciation Expression and Capability Adaptation](engine-pronunciation-expression-and-capability-adaptation.md)
- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)
- [Playback Orchestration and Synthesis Boundaries](playback-orchestration-and-synthesis-boundaries.md)
- [Audio Export and Headless Execution](audio-export-and-headless-execution.md)

## Change Log

- March 29, 2026
  Description: Established the initial project architecture documents and accepted the normalized-document plus workerized speech pipeline direction.
  Reason: Imported-document playback quality and performance issues require structural guidance before further implementation.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Expanded the system architecture to include normalized position mapping, speech enrichment, narration state, a two-pass enrichment model, and synthesis-boundary management as first-class concerns.
  Reason: The product and research now require an architectural picture that explains how natural long-form speech is produced smoothly, not just how text is rendered and spoken.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Added an explicit speech runtime messaging boundary between controller code and repeated background speech work.
  Reason: Research and implementation friction showed that Flutter isolate helpers and native plugin threading need one subsystem-level boundary, not ad hoc offloading patches.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Added pronunciation planning and TTS artifacts as a first-class system layer.
  Reason: Research and implementation friction showed that systemic pronunciation control must live in the internal representation and be passed into the TTS layer, not improvised inside the live runtime path.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Expanded the system architecture to include audio export, command-line launch inputs, and headless execution as first-class system behavior.
  Reason: Saving spoken output and running the same speech pipeline without the UI are product features that need one shared architecture rather than testing-only utility code.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 31, 2026
  Description: Added explicit engine pronunciation-expression and capability-adaptation architecture and aligned the governing specification references with the current architecture tree.
  Reason: The next pronunciation-quality work depends on a complete system-level picture of how planner-owned speech intent is expressed through real engine control surfaces.
  Feature branch: `main`
  PR reference: `not opened yet`
