# Playback Orchestration and Synthesis Boundaries

Last updated: April 4, 2026
Status: Active architecture

## Purpose

This document defines how enriched speech input becomes generated audio, how playback sessions are coordinated, and how chunk-boundary artifacts are controlled.

## Overview

The product’s playback experience depends on more than chunk generation speed.

It also depends on:

- whether generic speech enrichment was already cached before playback started
- how playback sessions are organized
- how chunks are prioritized and cached
- how silence and pauses are handled at synthesis boundaries
- how progress is mapped back into content

This architecture defines that orchestration.

## Components

### Playback Session Controller

Responsibilities:

- own the active playback session id
- own current reading position
- persist and restore file-backed resume position when session continuity applies
- own replay, pause, jump, and sleep-timer transitions
- coordinate queue resets on voice, rate, or position changes

### Generation Scheduler

Responsibilities:

- prioritize the first chunk for the active session
- consume cached document-time enrichment instead of recomputing it on the play path
- schedule later chunks behind playback
- cancel stale generation when the session changes

### Speech Runtime Boundary

Responsibilities:

- accept explicit generation and playback-preparation commands from the controller side
- own long-lived background runtime execution for repeated chunk work
- return explicit events rather than mutating controller state directly
- keep isolate and plugin queue concerns behind one subsystem boundary

### Speech Worker Pipeline

Responsibilities:

- run cache lookup
- translate prepared TTS artifacts into engine-consumable synthesis input
- synthesize
- serialize audio
- return generated chunk metadata

This is the heavy execution path and belongs behind the runtime boundary rather than directly in controller code.

### Synthesis-Boundary Policy

Responsibilities:

- interpret chunk-boundary metadata
- prevent exaggerated silence at joins
- trim or cap pathological leading and trailing silence
- preserve a small boundary taxonomy such as weak, sentence, paragraph, and section
- preserve intended linguistic breaks without stacking unintended silence
- treat initial and resumed chunks as special cases

### Generated Audio Cache

Responsibilities:

- preserve reusable generated chunks
- retain metadata required for progress mapping and playback continuity
- support replay without unnecessary regeneration

### Playback Queue

Responsibilities:

- hold prepared chunk sequence for the current session
- start when the first chunk is ready
- continue while later chunks are still being prepared

### Progress Mapper

Responsibilities:

- translate active playback back into segment ids and word ranges
- support visible spoken-text highlighting
- support 30-second jump estimation and recovery

## Relationships

- The playback session controller owns the scheduler and queue for the active session.
- The controller reaches heavy speech work only through the speech runtime boundary.
- The scheduler owns the order in which chunks are requested from the worker.
- The worker produces chunks plus metadata.
- The synthesis-boundary policy runs on chunk output before the queue treats the chunk as playback-ready.
- The cache stores finalized chunk output for future sessions.
- The progress mapper uses queue metadata and normalized mappings, not raw audio guesses alone.

## Data Flow

```text
enriched planner input
  -> pronunciation-aware TTS artifacts
  -> chunk planner
  -> generation scheduler
  -> speech runtime boundary
  -> speech worker pipeline
  -> synthesis-boundary policy
  -> generated-audio cache
  -> playback queue
  -> audio player
  -> progress mapper
  -> controller state and UI
```

## Cross-Domain Solutions

### 1. Startup latency and continuity are solved together

The system must not choose between:

- starting quickly
- sounding coherent

The architecture therefore uses first-chunk priority with later-chunk background generation.

It also relies on earlier document-time enrichment so that the live play path can focus on only the active voice/session realization and chunk generation.

### 2. Boundary artifacts are handled structurally

Chunk-boundary quality must not depend on ad hoc fixes spread across:

- chunk planning
- model output
- player behavior
- UI timing

Boundary handling belongs in one architectural layer.

Reason:

- otherwise long pauses and join artifacts become hard to reason about
- the app can accidentally combine multiple silence sources into one audible defect

The default correction strategy is trim-and-cap. Overlap or crossfade is not the default architectural answer for speech joins.

### 3. Playback identity is session-based

Voice changes, rate changes, jumps, replay, and document changes all create a new playback session identity.

Reason:

- stale chunk-generation results must not mutate current playback state
- queue control and cancellation need one authoritative ownership concept

### 3a. Heavy work crosses one official runtime boundary

The system must not spread background execution concerns across:

- controller methods
- ad hoc isolate helpers
- plugin call sites
- player callbacks

Reason:

- ownership becomes unclear quickly
- sendability problems become easier to introduce
- native queue problems become invisible until the UI stalls

The accepted solution is a subsystem-local speech runtime boundary with explicit commands and events.

### 4. Cache ownership is independent from queue ownership

Prepared audio may outlive the current in-memory queue.

Reason:

- replay should reuse completed chunks
- cache lifetime should not be tied to short-lived UI state

### 5. Quality and observability are architectural concerns

The system must expose enough metadata to understand:

- first-audio latency
- cache-hit rate
- chunk-boundary corrections
- pause behavior at joins
- progress-mapping quality

Reason:

- narration quality must be evaluated in paragraph and session context, not only in isolated chunk generation
- subjective listening review needs runtime metrics to stay actionable during implementation

## Architectural Rules

- The first playback action waits only for first-chunk readiness.
- Generic document-time enrichment must not be recomputed synchronously on every play action.
- Chunk planning is sentence-first, with clause fallback only when engine limits require it.
- Background generation never owns playback state directly.
- Controller code never invokes heavy speech plugins directly.
- File-backed reading continuity should preserve the user's last known heard position across app relaunch when recovery is possible.
- The runtime consumes prepared pronunciation/TTS artifacts and must not invent new pronunciation policy as a side effect of live playback.
- Completed chunks are not deleted just because playback is paused, replayed, or jumped.
- Boundary policy is applied before a chunk is treated as final cache content.
- Boundary policy uses trim-and-cap joins by default and does not add blind player-level gaps.
- Progress mapping stays tied to normalized content ids, not only elapsed audio time.
- Highlighting and reading-focus behavior consume progress mapping output rather than reparsing display HTML.

## Current Implementation Gap

The current implementation now satisfies most of this architecture for the active engine path, with a few remaining gaps:

- first-chunk startup, background preparation, finalized chunk reuse, boundary correction, and playback instrumentation are all first-class in code
- document-open priming and runtime scheduling now keep playback smooth, but long-form prosody richness remains narrower than the target architecture
- queue, cache, and progress behavior are implemented for the current Kokoro/native path; broader cross-platform validation remains future work
- the progress mapper now drives spoken highlighting and reading-focus behavior on the reader surface
- file-backed continuity now restores the last heard reading position when recovery is possible, and watched-file live input preserves playing-versus-paused semantics across refresh
- current controller code still leans on compatibility text views in `ReaderDocument` while normalized mappings remain the underlying source of truth

## Governing Specifications

- [Imported Document Playback](../specifications/imported-document-playback.md)
- [Chunk Planning](../specifications/chunk-planning.md)
- [Speech Worker Pipeline](../specifications/speech-worker-pipeline.md)
- [Generated Audio Cache](../specifications/generated-audio-cache.md)
- [Synthesis Boundary Policy](../specifications/synthesis-boundary-policy.md)
- [Playback Coordination](../specifications/playback-coordination.md)
- [Playback Progress and Jump Mapping](../specifications/playback-progress-and-jump-mapping.md)
- [Spoken Text Highlighting and Reading Focus](../specifications/spoken-text-highlighting-and-reading-focus.md)
- [Playback Quality Instrumentation](../specifications/playback-quality-instrumentation.md)

## Change Log

- March 30, 2026
  Description: Added the playback orchestration and synthesis-boundary architecture as a first-class architectural document, including the startup role of cached document-time enrichment versus live voice/session processing.
  Reason: The product’s target speech quality depends not only on synthesis, but on how chunks are generated, joined, cached, and evaluated across a playback session while still feeling smooth at play time.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Refined the architecture with sentence-first chunking, trim-and-cap join policy, initial-chunk special handling, and explicit quality instrumentation.
  Reason: The research pass resolved the likely boundary-policy shape and the need to evaluate long-form playback with both listening review and runtime metrics.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Added the speech runtime boundary as an explicit orchestration component between controller logic and repeated speech generation work.
  Reason: The Flutter concurrency and queueing research showed that process decoupling needs one official subsystem boundary spanning Dart isolates and native plugin queue policy.
  Feature branch: `main`
  PR reference: `not opened yet`
