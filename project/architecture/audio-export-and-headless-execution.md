# Audio Export and Headless Execution

Last updated: April 3, 2026
Status: Active architecture

## Purpose

This document defines how `Read Aloud` exports spoken audio and how the app can run without its normal UI for command-line, automation, and speech-QA workflows.

## Overview

Audio export and headless execution are product features, not testing-only hooks.

They exist to:

- let users save spoken output as audio
- let desktop users invoke the app from the command line
- let the same speech pipeline run with or without the normal reader UI
- improve iteration speed for speech-quality debugging without creating a second speech implementation
- preserve probe outputs and trace artifacts in durable project-owned paths when the project root is available

The accepted solution is one shared synthesis pipeline with multiple entry modes.

## Components

### App Launch Mode Resolver

Responsibilities:

- parse startup arguments
- decide whether the app should run in normal UI mode, headless export mode, pronunciation-probe mode, or sentence-probe mode
- preserve one consistent option model for desktop automation

### Shared Document Intake Path

Responsibilities:

- import files through the same importer stack used by the interactive app
- produce the same normalized document model used for playback
- avoid separate CLI-only parsing behavior

### Shared Speech Planning Path

Responsibilities:

- derive realization and chunk-planning inputs from the normalized document
- preserve the same voice, rate, normalization, and chunk-planning behavior used by playback
- allow export to remain comparable to what the user would hear in the app

### Audio Export Coordinator

Responsibilities:

- request chunk generation for a whole export span
- collect finalized chunk outputs in order
- assemble one exported WAV file
- emit export-side metadata useful for later inspection

### Interactive Export Workflow

Responsibilities:

- let the user choose an output path from the app
- export using the currently selected voice and speed
- surface export success or failure without requiring command-line usage

### Headless Session Runner

Responsibilities:

- process command-line file inputs without launching the normal reader UI
- run import, synthesis, and export sequentially
- print machine- and human-usable results
- return meaningful process exit status

### Speech QA Harnesses

Responsibilities:

- run short pronunciation probes against the shared speech pipeline
- run sentence-by-sentence probes over real imported documents
- emit manifests, trace references, and waveform-analysis data for before/after comparison

### Stable Test Artifact Store

Responsibilities:

- persist debug trace logs and probe outputs in project-owned directories when possible
- fall back to application-support storage when no project root is available
- keep generated QA artifacts easy to inspect from the editor

## Relationships

- launch mode resolution happens before `runApp`
- UI mode, headless export mode, pronunciation-probe mode, and sentence-probe mode all depend on the same importer, speech planning, and export pipeline
- interactive export is initiated by the reader controller or UI layer
- headless export is initiated by the headless session runner
- speech QA harnesses reuse the same runtime and export behavior rather than creating a second synthesis stack
- durable test-artifact storage supports both live playback trace inspection and headless QA runs

## Data Flow

```text
startup args
  -> launch mode resolver
  -> ui mode, headless export mode, pronunciation probe mode, or sentence probe mode

document input
  -> importer
  -> normalized document model
  -> speech planning
  -> speech runtime boundary
  -> finalized chunk audio
  -> exported audio assembly
  -> wav file + export metadata
```

## Cross-Domain Solutions

### 1. Export uses the same speech path as playback

The accepted solution is to export through the same normalized document, realization, chunk planning, runtime, and boundary-correction pipeline used for playback.

Reason:

- export should sound like the app
- pronunciation debugging only helps if the export path matches the playback path
- a second synthesis pipeline would drift quickly

### 2. Headless mode is a launch mode, not a second product

The accepted solution is one app with multiple execution modes:

- interactive UI mode
- headless export mode
- pronunciation-probe mode
- sentence-probe mode

Reason:

- both modes use the same product logic
- headless mode increases utility for automation and debugging
- the system should not fork into separate desktop and automation implementations

### 3. Export is file-oriented and durable

The accepted export output for `v1` is a WAV file plus export metadata sidecar.

Reason:

- WAV preserves generated audio exactly
- sidecar metadata helps debug pronunciation, chunking, and boundary issues later
- later formats such as compressed audio can be added without invalidating the first export contract

### 4. Headless mode is desktop-oriented in `v1`

The accepted command-line and headless feature target is desktop execution.

Reason:

- mobile platforms do not present the same user-facing command-line model
- the main utility gain right now is desktop automation and fast speech-debug cycles

## Architectural Rules

- export must not bypass normalization, realization, chunk planning, runtime commands, or boundary correction
- exported audio must be assembled from finalized chunk outputs, not from raw pre-correction audio
- UI mode and headless automation modes must agree on voice selection, rate handling, normalization version, and chunk planning
- headless mode must not launch the normal reader UI
- command-line file inputs in UI mode may preload the first document, but they do not create a second importer path
- export metadata must remain local and offline-friendly

## Governing Specifications

- [Audio Export and Headless Execution](../specifications/audio-export-and-headless-execution.md)
- [Audio Export Assembly](../specifications/audio-export-assembly.md)
- [Command-Line Mode Selection](../specifications/command-line-mode-selection.md)
- [Headless Synthesis Session](../specifications/headless-synthesis-session.md)
- [In-App Audio Export Workflow](../specifications/in-app-audio-export-workflow.md)
- [Speech QA Debug Tooling](../specifications/speech-qa-debug-tooling.md)
- [Playback Coordination](../specifications/playback-coordination.md)
- [Speech Runtime Messaging Boundary](../specifications/speech-runtime-messaging-boundary.md)
- [Generated Audio Cache](../specifications/generated-audio-cache.md)

## Change Log

- March 30, 2026
  Description: Added architecture for interactive audio export, command-line launch handling, and headless export execution.
  Reason: Saving spoken output and skipping the UI for automation are real product features that must reuse the same speech pipeline as playback rather than becoming one-off tooling paths.
  Feature branch: `main`
  PR reference: `not opened yet`
- April 3, 2026
  Description: Expanded the architecture to include pronunciation-probe and sentence-probe harnesses plus stable project-owned QA artifact storage.
  Reason: Real pronunciation tuning now depends on comparing emitted audio and inspecting durable traces without launching a second synthesis stack.
  Feature branch: `main`
  PR reference: `not opened yet`
