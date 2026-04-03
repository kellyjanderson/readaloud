# Speech Runtime Event Protocol

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the events emitted by the speech runtime back toward the controller side of the system.

## Backlink

Parent specification:

- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)

## Scope

This specification covers:

- runtime event envelope shape
- allowed event types
- required event payload fields
- event ordering and ownership rules

## Behavior

### Envelope Rule

Every event must use the DTO envelope defined by:

- [Sendable Runtime DTO Contract](sendable-runtime-dto-contract.md)

The `type` field must be one of the event types defined below.

### Event Types

The initial runtime event set must support:

1. `runtimeInitialized`
2. `sessionActivated`
3. `chunkQueued`
4. `chunkCacheHit`
5. `chunkStageChanged`
6. `chunkReady`
7. `chunkFailed`
8. `sessionCancelled`
9. `runtimeFailed`
10. `runtimeShutdown`

### Common Ownership Fields

The payload for any session-scoped event must include:

- `String sessionId`

The payload for any chunk-scoped event must include:

- `String sessionId`
- `String generationId`
- `String chunkId`

### `runtimeInitialized`

Required payload:

- `String engineId`

### `sessionActivated`

Required payload:

- `String sessionId`
- `String documentId`
- `String voiceId`
- `double rate`

### `chunkQueued`

Required payload:

- `String sessionId`
- `String generationId`
- `String chunkId`

### `chunkCacheHit`

Required payload:

- `String sessionId`
- `String generationId`
- `String chunkId`
- `String audioPath`
- `int durationMillis`

### `chunkStageChanged`

Required payload:

- `String sessionId`
- `String generationId`
- `String chunkId`
- `String stage`

The initial `stage` vocabulary must support:

- `cacheLookup`
- `phonemizing`
- `inferencing`
- `serializing`
- `boundaryCorrecting`

Optional payload:

- `int elapsedMillis`

### `chunkReady`

Required payload:

- `String sessionId`
- `String generationId`
- `String chunkId`
- `String audioPath`
- `int durationMillis`
- `int leadingSilenceMs`
- `int trailingSilenceMs`

Optional payload:

- `bool cacheHit`
- `int joinSilenceBeforeMs`
- `int joinSilenceAfterMs`

`chunkReady` represents playback-ready chunk output after boundary policy has run.

### `chunkFailed`

Required payload:

- `String sessionId`
- `String generationId`
- `String chunkId`
- `String errorCode`

Optional payload:

- `String message`
- `bool fatalForSession`

### `sessionCancelled`

Required payload:

- `String sessionId`

Optional payload:

- `String reasonCode`

### `runtimeFailed`

Required payload:

- `String errorCode`

Optional payload:

- `String message`

### `runtimeShutdown`

Required payload:

- none

### Ordering Rule

For one chunk, terminal outcomes are mutually exclusive. The runtime may emit only one of:

- `chunkReady`
- `chunkFailed`
- `sessionCancelled` for its owning session before completion

### First-Chunk Rule

The first chunk for an active generation must become observable through:

- `chunkQueued`
- optional intermediate stage events
- terminal `chunkReady` or `chunkFailed`

before later-plan chunk readiness is allowed to overtake it.

### Stale Event Rule

The controller may ignore any event whose:

- `sessionId`
- `generationId`

no longer matches current ownership.

The event protocol must make that possible without side channels.

## Constraints

- Events must remain sendable DTOs.
- `chunkReady` must refer to finalized playback-ready output, not pre-correction intermediate output.
- Event ownership must be explicit enough to reject stale background results deterministically.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The runtime can report initialization, session activation, chunk lifecycle, failures, cancellation, and shutdown through one typed event protocol.
- The controller can derive current runtime state from event ownership and event type without hidden shared state.
