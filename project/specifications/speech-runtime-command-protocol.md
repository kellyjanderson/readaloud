# Speech Runtime Command Protocol

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the commands that controller-side code may send into the speech runtime.

## Backlink

Parent specification:

- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)

## Scope

This specification covers:

- runtime command envelope shape
- allowed command types
- required command payload fields
- command ordering and ownership rules

## Behavior

### Envelope Rule

Every command must use the DTO envelope defined by:

- [Sendable Runtime DTO Contract](sendable-runtime-dto-contract.md)

The `type` field must be one of the command types defined below.

### Command Types

The initial runtime command set must support:

1. `initializeRuntime`
2. `activateSession`
3. `preparePriorityChunk`
4. `prepareChunkPlan`
5. `cancelSession`
6. `shutdownRuntime`

### `initializeRuntime`

Purpose:

- bootstrap runtime resources needed before the first speech request

Required payload:

- `String engineId`

Optional payload:

- `String preferredVoiceId`

### `activateSession`

Purpose:

- establish or replace the active playback session identity before chunk preparation begins

Required payload:

- `String sessionId`
- `String documentId`
- `String engineId`
- `String voiceId`
- `double rate`
- `String startSegmentId`
- `String normalizationVersion`

Optional payload:

- `bool isReplay`
- `bool isResumedPlayback`
- `Map<String, Object?> narrationState`

### `preparePriorityChunk`

Purpose:

- request first-chunk work with strict session-local priority

Required payload:

- `String sessionId`
- `String generationId`
- `Map<String, Object?> chunk`

Optional payload:

- `int previousTrailingSilenceMs`
- `bool isInitialChunk`
- `bool isResumedChunk`

`chunk` must be a sendable DTO representation of the chunk request for one chunk.

### `prepareChunkPlan`

Purpose:

- request sequential preparation of later chunks for the active generation

Required payload:

- `String sessionId`
- `String generationId`
- `List<Map<String, Object?>> chunks`

### `cancelSession`

Purpose:

- cancel all not-yet-completed work owned by one session

Required payload:

- `String sessionId`

Optional payload:

- `String reasonCode`

### `shutdownRuntime`

Purpose:

- stop future command acceptance and tear down runtime resources

Required payload:

- none

### Ordering Rule

The controller or facade must not send:

- `preparePriorityChunk`
- `prepareChunkPlan`

for a session that has not first been established with `activateSession`.

### Replacement Rule

If `activateSession` is sent with a new `sessionId`, the runtime must treat any prior active session as replaced.

### Ownership Rule

All preparation commands must include:

- `sessionId`
- `generationId`

so stale work can be rejected deterministically.

### Command Idempotency Rule

- `cancelSession` for an already inactive session is allowed and must be harmless.
- `shutdownRuntime` after shutdown has begun is allowed and must be harmless.

## Constraints

- Commands must remain sendable DTOs.
- The initial command set must be sufficient to bootstrap a session, request first-chunk priority, request later-plan work, cancel stale work, and shut down the runtime.
- Command semantics must not require controller-side object sharing.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Controller-side code can express runtime initialization, session activation, priority first-chunk work, plan work, cancellation, and shutdown through explicit commands.
- Every chunk-preparation command carries enough ownership identity to reject stale work.
