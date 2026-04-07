# Document and Speech Pipeline

Last updated: April 3, 2026
Status: Active architecture

## Purpose

This document defines the accepted target structure for how imported content becomes rendered content and spoken audio.

## Accepted Pipeline

```text
source file / pasted text
  -> source-specific importer
  -> normalization
  -> DisplayDocument + SpeechDocument + PositionMap
  -> document-time speech enrichment
  -> cached base speech annotations
  -> document-time cast analysis and document-owned voice attribution
  -> optional background continuation of document-time enrichment
  -> document-time pronunciation planning
  -> cached pronunciation artifacts
  -> voice/session-time realization
  -> voice/session pronunciation realization
  -> TTS artifact set
  -> narration state
  -> chunk planner
  -> runtime chunk request derivation
  -> engine pronunciation expression and capability adaptation
  -> speech runtime messaging boundary
  -> speech worker pipeline
  -> synthesis-boundary policy
  -> chunk cache
  -> playback queue or export assembly
  -> controller state / headless result
  -> UI rendering, saved audio, and future highlighting
  -> optional serialized internal document artifact for debugging and tests
```

## Structural Decisions

### 1. Imported content must be normalized before speech generation

All imported formats must pass through a normalization step that preserves:

- display structure
- speech structure
- stable ids
- offset mappings

Flattening imported content directly into one raw speech string is not an acceptable long-term pipeline.

The document-open path should complete after this normalized structure is available. It must not wait for whole-document synthesis preparation.

### 1a. The normalization path must stay lightweight and explainable

The accepted open-path strategy is:

- rule-based segmentation
- source-structure preservation where available
- conservative line-wrap repair and reading-order recovery
- diagnostics for low-confidence results

Heavy semantic or voice-specific work can continue after the document is already viewable.

When multi-voice reading is enabled, the app may keep the document shell in a visible processing state while document-time cast analysis continues.

### 2. Speech enrichment is a first-class layer between normalization and chunk planning

The system must infer and preserve speech-side information that is not guaranteed to exist in source documents, including:

- phrase boundaries
- pause classes
- emphasis candidates
- pronunciation overrides
- future synchronization marks
- narration continuity state

These concepts must remain structurally separate from display rendering concerns.

### 3. Speech enrichment is split into document-time and voice/session-time passes

The system must distinguish between:

- voice-agnostic enrichment that can be computed once per document and cached
- voice/session-specific realization that depends on the active voice, rate, and narration context

This split exists to keep playback startup fast without losing high-quality voice-specific behavior.

Voice/session realization is windowed around the active playback position. Voice changes must not force whole-document structural recomputation.

### 3b. Document-time cast analysis is part of the imported document artifact

Dialogue attribution, cast identity, and document-owned narrator-versus-character voice attribution belong to the imported internal document state rather than controller-local reconstruction.

Reason:

- playback, export, and headless flows all need the same speaker ownership truth
- quote-versus-narration boundaries should be inspectable and testable without running live playback
- a serialized internal document artifact becomes meaningful only if document-time cast results are first-class data

### 3a. Pronunciation planning is a first-class internal artifact layer

The system must preserve pronunciation decisions as app-owned TTS artifacts attached to the internal speech representation.

Reason:

- pronunciation quality needs more context than isolated word tokenization can provide
- runtime playback should consume prepared pronunciation intent rather than improvising it
- export, headless execution, and QA need access to the same pronunciation truth as interactive playback

### 4. Chunk planning operates on enriched speech content

Chunk planning must use explicit speech segments with sentence and paragraph boundaries plus any available phrase and narration annotations. It must not depend on arbitrary string slicing as the primary strategy.

Sentence boundaries are the default unit. Clause fallback exists only when engine limits force a smaller unit.

### 5. Speech generation crosses a formal runtime boundary

The main isolate is not the home for repeated speech-generation internals such as:

- phonemization
- ONNX inference
- wav serialization
- boundary correction
- chunk cache mutation
- generation diagnostics

These belong behind a formal runtime boundary with explicit commands and events. The worker isolate is one implementation part of that runtime, not the whole architectural boundary by itself.

### 6. Playback is queue-based, not utterance-monolithic

Playback should:

- wait only for the first chunk
- start audio as soon as that first chunk is ready
- queue later chunks behind playback
- preserve generated chunk files for reuse according to cache policy

### 6a. Export reuses finalized chunk outputs

The system must export from the same finalized chunk outputs used for playback preparation.

Reason:

- export must remain comparable to playback
- pronunciation and boundary debugging depend on one shared audio path
- chunk reuse is still valuable during export

### 7. Synthesis-boundary policy is centralized

Pause and silence handling at chunk boundaries must not be left to accidental interaction between:

- inferred linguistic breaks
- model-generated silence
- cached chunk joins
- player behavior

Boundary policy belongs in one architectural place so the system can avoid exaggerated end-of-sentence pauses and boundary artifacts.

The default join strategy is:

- preserve intended boundary class
- trim pathological leading silence on noninitial chunks
- cap combined join silence
- avoid overlap or crossfade unless later evidence justifies them for a specific artifact class

### 8. Progress must map back to normalized content

Every playback update must be able to resolve back to:

- segment id
- word or token range
- source and display ranges where available

This is required for stable future highlighting and precise replay or resume behavior.

The accepted `PositionMap` model is hybrid:

- offsets for fast mapping
- quote-style recovery anchors for resilience
- source-native anchors when available and cheap to preserve

### 9. Playback quality must be observable

The pipeline must produce enough metadata to measure:

- first-audio latency
- real-time factor
- cache hits
- join-silence corrections
- playback underruns
- progress-map confidence

### 10. Internal document artifacts should be serializable for debugging and verification

The normalized internal document state should be serializable to a project-owned format for fixture generation, debugging, and correction workflows.

The first version should optimize for inspectability over compactness so document-time attribution and normalization decisions can be reviewed outside the running app.

## Required Data Flow Boundaries

### Engine-Expression Output

The engine-expression layer may adapt canonical internal IPA to an engine-specific phoneme inventory when direct phoneme payloads are used.

For Kokoro, this means standard internal IPA remains app-owned upstream, while Kokoro/Misaki-specific phoneme symbols are introduced only at the engine adapter edge.

### Importer Output

Importers produce normalized documents and position mapping. They do not emit playback chunks.

### Enrichment Output

The enrichment layer emits:

- cached base speech annotations
- cached base pronunciation artifacts
- voice/session-specific realization data
- voice/session-specific pronunciation realization and TTS artifacts
- narration state input for chunk planning
- enriched planner input derived from normalized speech content

### Chunk Planner Output

The planner emits explicit chunk plans with:

- chunk id
- ordered segment ids
- normalized chunk text
- offset mapping

### Speech Worker Output

The speech worker emits:

- prepared audio chunk path or bytes
- duration
- cache status
- mapping metadata for progress and highlighting
- boundary metadata needed to enforce silence policy
- instrumentation data for latency and join-quality measurement

### Playback Queue Output

The playback coordinator emits UI-consumable state:

- buffering
- playing
- paused
- completed
- current chunk and progress mapping

### Export Output

The export coordinator emits:

- ordered finalized chunk references
- assembled WAV output
- sidecar export metadata
- success or failure result for interactive or headless callers

## Current Implementation Gap

The current implementation now follows this pipeline structurally, but a few compatibility and richness gaps remain:

- importers produce a normalized result envelope with first-class `DisplayDocument`, `SpeechDocument`, `PositionMap`, diagnostics, speech annotations, and pronunciation artifacts
- `ReaderDocument` still publishes compatibility views such as `displayHtml`, `speakableText`, and coarse word spans for current UI and export callers
- chunk planning, runtime chunk derivation, boundary correction, export, and headless probe flows all operate on the normalized speech pipeline, even when compatibility text views are still exposed nearby
- document-time enrichment, narration state, and active realization are now first-class, but their prosody richness and long-form continuity behavior remain lighter than the target architecture
- broader cross-platform validation and future highlighting behavior still remain ahead of the current implementation

## Governing Specifications

- [Normalized Document Model](../specifications/normalized-document-model.md)
- [Display Document](../specifications/display-document.md)
- [Speech Document](../specifications/speech-document.md)
- [Importer Normalization Contract](../specifications/importer-normalization-contract.md)
- [PositionMap](../specifications/position-map.md)
- [Speech Annotation Set](../specifications/speech-annotation-set.md)
- [Voice and Session Realization](../specifications/voice-session-realization.md)
- [Narration State](../specifications/narration-state.md)
- [Pronunciation Artifact Model](../specifications/pronunciation-artifact-model.md)
- [Document-Time Pronunciation Planner](../specifications/document-time-pronunciation-planner.md)
- [Voice-Session Pronunciation Realization](../specifications/voice-session-pronunciation-realization.md)
- [TTS Artifact Consumption Contract](../specifications/tts-artifact-consumption-contract.md)
- [TTS Runtime Chunk Request Derivation](../specifications/tts-runtime-chunk-request-derivation.md)
- [Engine Pronunciation Translation Policy](../specifications/engine-pronunciation-translation-policy.md)
- [Pronunciation Fallback and Traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [Chunk Planning](../specifications/chunk-planning.md)
- [Speech Worker Pipeline](../specifications/speech-worker-pipeline.md)
- [Generated Audio Cache](../specifications/generated-audio-cache.md)
- [Synthesis Boundary Policy](../specifications/synthesis-boundary-policy.md)
- [Playback Coordination](../specifications/playback-coordination.md)
- [Playback Progress and Jump Mapping](../specifications/playback-progress-and-jump-mapping.md)
- [Playback Quality Instrumentation](../specifications/playback-quality-instrumentation.md)
- [Audio Export and Headless Execution](../specifications/audio-export-and-headless-execution.md)

## Related Architecture

- [Normalized Content and Position Mapping](normalized-content-and-position-mapping.md)
- [Speech Enrichment and Narration](speech-enrichment-and-narration.md)
- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)
- [Engine Pronunciation Expression and Capability Adaptation](engine-pronunciation-expression-and-capability-adaptation.md)
- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)
- [Playback Orchestration and Synthesis Boundaries](playback-orchestration-and-synthesis-boundaries.md)

## Change Log

- March 29, 2026
  Description: Accepted the normalized document plus workerized playback pipeline as the target speech architecture.
  Reason: Pronunciation quality, cadence quality, highlighting support, and imported-document performance all depend on the same structural change.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Expanded the pipeline architecture to include position mapping, speech enrichment, narration state, a two-pass enrichment model, and centralized synthesis-boundary policy.
  Reason: Research on natural long-form speech and narration quality showed that normalized text alone is not enough, and that careful separation of cached and live processing is required for a smooth product feel.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Refined the accepted pipeline with a lightweight document-open path, a hybrid `PositionMap` model, sentence-first chunk planning, trim-and-cap boundary policy, and observability requirements.
  Reason: The research pass resolved the main open architectural questions around preprocessing split, mapping granularity, Kokoro control limits, join handling, and quality evaluation.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Inserted the speech runtime messaging boundary into the accepted pipeline between chunk planning and background generation.
  Reason: The Flutter concurrency research showed that repeated speech work needs a first-class message boundary and native queue policy, not just isolated helper calls.
  Feature branch: `main`
  PR reference: `not opened yet`
