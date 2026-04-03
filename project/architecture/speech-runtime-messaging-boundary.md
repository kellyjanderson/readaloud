# Speech Runtime Messaging Boundary

Last updated: March 31, 2026
Status: Active architecture

## Purpose

This document defines the official concurrency and process boundary between Flutter UI/control code and the speech-generation runtime.

## Overview

`Read Aloud` needs more than “some work in an isolate.”

It needs a structural runtime boundary that:

- keeps the Flutter UI responsive during repeated speech work
- prevents controller and engine state from leaking across isolate boundaries
- contains native plugin queue policy as part of the design
- gives the speech subsystem an explicit command/event contract

The accepted model is an actor-like, subsystem-local runtime boundary.

This is not a global event bus for the entire app.

## Components

### Playback Session Controller

Responsibilities:

- own visible transport state
- translate user intent into runtime commands
- consume runtime events and derive UI state
- preserve app-level reading position, replay behavior, jump behavior, and settings

This component stays on the main Flutter isolate.

### Speech Runtime Facade

Responsibilities:

- expose a stable async API to the controller
- serialize commands into sendable runtime messages
- deserialize runtime events into controller-consumable updates
- hide platform/runtime implementation differences behind one interface

This is the only layer the controller talks to for speech work.

### Speech Runtime Worker

Responsibilities:

- own long-lived background execution for repeated speech work
- receive runtime commands
- perform scheduling, realization, generation, boundary correction, cache operations, and diagnostics
- emit runtime events

This worker is long-lived. It is not recreated per chunk by default.

### Runtime Command Protocol

Responsibilities:

- define the allowed requests into the speech runtime
- constrain payloads to sendable DTOs only
- preserve session and generation ownership explicitly

This protocol exists so controller state is not smuggled into background work through closures or object references.

### Runtime Event Protocol

Responsibilities:

- define the allowed outputs from the speech runtime
- surface state transitions, progress, cache status, readiness, failure, and cancellation
- keep UI derivation separate from worker internals

### Native Engine Adapter

Responsibilities:

- translate runtime work into engine-specific native/plugin calls
- isolate Kokoro or future engines from controller code
- enforce native queue policy for heavy work

### Platform Channel Queue Policy

Responsibilities:

- ensure plugin handlers do not perform heavy work on the wrong thread
- use background task queues where supported
- avoid assuming that a Dart isolate boundary alone is sufficient

## Relationships

- The controller talks only to the speech runtime façade.
- The façade converts controller intent into runtime commands.
- The worker owns repeated background speech work.
- The worker uses a native engine adapter when plugin or host code is required.
- The worker emits events back through the façade.
- The controller derives visible state from those events.

## Data Flow

```text
UI intent
  -> controller
  -> speech runtime facade
  -> runtime command
  -> speech runtime worker
  -> native engine adapter
  -> runtime event
  -> speech runtime facade
  -> controller state
  -> UI
```

## Cross-Domain Solutions

### 1. The speech subsystem is actor-like, not callback-entangled

The accepted solution is a message boundary rather than ad hoc callback chains and background helpers.

Reason:

- Dart isolates are message-passing units
- closure-based background helpers can accidentally capture unsendable or oversized state
- repeated speech work is a stateful runtime workflow, not one isolated calculation

### 2. The runtime worker is long-lived

The accepted solution is a long-lived worker for repeated generation work.

Reason:

- repeated short-lived isolates add spawn and copy overhead
- playback needs multiple messages over time
- the runtime has a durable identity during one playback session

### 3. The boundary carries only sendable DTOs

The accepted solution is an explicit DTO contract using:

- ids
- file paths
- numeric metadata
- small immutable message payloads

The boundary must not carry:

- closures
- controller references
- plugin objects
- engine instances
- large accidental object graphs

Reason:

- Dart message passing has sendability restrictions
- send cost can grow with the transitive object graph
- closures can capture more state than they appear to need

### 4. Native queue policy is part of the runtime architecture

The accepted solution includes native task-queue and background-dispatch policy as part of the speech runtime.

Reason:

- heavy native/plugin work can still block responsiveness if the plugin handles requests on the wrong queue
- “off the UI isolate” is not enough if the platform-thread work remains synchronous and heavy

### 5. The runtime boundary is local to speech, not global to the whole app

The accepted solution is a subsystem boundary around speech generation and playback preparation.

Reason:

- the rest of the app does not need the complexity of a global message bus
- the problem we are solving is concentrated in one performance-sensitive subsystem

### 6. Platform capability differences are hidden below the façade

The accepted solution preserves one architectural shape while allowing implementation differences by platform.

Reason:

- native Flutter platforms support true isolate offload
- Flutter web does not provide the same isolate behavior through `compute`
- local TTS engine capability may differ by platform

## Architectural Rules

- The controller must not call Kokoro plugins or native speech adapters directly.
- Repeated speech work must not depend on per-chunk closure-based isolate helpers as the primary runtime structure.
- The speech runtime boundary must remain explicit and message-based.
- Runtime commands and events must be versionable and typed.
- Background workers must not depend on `rootBundle`, `dart:ui`, or unsolicited host-platform event streams.
- Native engine adapters must use background task queues or equivalent native background dispatch for heavy handler work where supported.
- Runtime events describe state; they do not directly mutate controller-owned state.
- Queue ownership, cache ownership, and controller ownership remain separate concerns even when they are coordinated by one playback session.

## Current Implementation Gap

The current codebase now implements this boundary directly, with a smaller remaining gap surface:

- the app has first-class runtime commands, events, session descriptors, chunk payload DTOs, lifecycle state, and platform capability detection
- the Kokoro path uses this runtime boundary and worker pipeline for playback and export rather than ad hoc per-call helper work
- native queue policy is explicit for the current engine path, but broader platform/runtime capability coverage remains limited to current supported targets
- some orchestration detail still lives in engine/controller coordination layers rather than a thinner pure-facade split

## Governing Specifications

- [Speech Runtime Messaging Boundary](../specifications/speech-runtime-messaging-boundary.md)
- [Sendable Runtime DTO Contract](../specifications/sendable-runtime-dto-contract.md)
- [Speech Runtime Lifecycle and Ownership](../specifications/speech-runtime-lifecycle-and-ownership.md)
- [Speech Runtime Command Protocol](../specifications/speech-runtime-command-protocol.md)
- [Speech Runtime Event Protocol](../specifications/speech-runtime-event-protocol.md)
- [Native Engine Queue Policy](../specifications/native-engine-queue-policy.md)
- [Platform Capability and Fallback Policy](../specifications/platform-capability-and-fallback-policy.md)
- [Speech Worker Pipeline](../specifications/speech-worker-pipeline.md)
- [Playback Coordination](../specifications/playback-coordination.md)
- [Generated Audio Cache](../specifications/generated-audio-cache.md)
- [Synthesis Boundary Policy](../specifications/synthesis-boundary-policy.md)
- [Playback Progress and Jump Mapping](../specifications/playback-progress-and-jump-mapping.md)

## Related Research

- [Flutter Concurrency, Message Boundaries, and Runtime Decoupling — 2026-03-30](../research/architecture-questions/flutter-concurrency-message-boundaries-and-runtime-decoupling-2026-03-30.md)

## Related Architecture

- [Engine Pronunciation Expression and Capability Adaptation](engine-pronunciation-expression-and-capability-adaptation.md)
- [Playback Orchestration and Synthesis Boundaries](playback-orchestration-and-synthesis-boundaries.md)

## Change Log

- March 30, 2026
  Description: Added a first-class speech runtime messaging boundary architecture centered on a long-lived worker, DTO-only commands and events, and explicit native queue policy.
  Reason: Kokoro integration exposed that isolate helpers alone do not provide a stable decoupling model in Flutter, especially when repeated work, plugin constraints, and native threading all interact.
  Feature branch: `main`
  PR reference: `not opened yet`
