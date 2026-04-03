# Speech Runtime Lifecycle and Ownership

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines runtime instance lifecycle, playback-session ownership, and generation ownership inside the speech runtime boundary.

## Backlink

Parent specification:

- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)

## Scope

This specification covers:

- runtime instance states
- session ownership
- generation ownership
- cancellation and shutdown semantics

## Behavior

### Runtime State Model

The runtime instance must expose exactly one primary lifecycle state at a time:

- `uninitialized`
- `initializing`
- `idle`
- `sessionActive`
- `shuttingDown`
- `disposed`
- `failed`

### Instance Rule

The initial implementation uses one speech runtime instance per active TTS engine instance.

### Session Rule

The runtime may own at most one active playback session at a time.

`sessionId` is the controller-visible ownership token for:

- active document playback
- selected voice
- selected rate
- active replay/jump context

### Session Invalidation Rule

A new `sessionId` is required when:

- document changes
- voice changes
- rate changes
- playback jumps to a new target
- replay begins after completion

Pausing and resuming without changing playback identity must not require a new `sessionId`.

### Generation Rule

`generationId` represents one runtime preparation sequence inside a session.

All chunk work emitted for the same preparation sequence must carry the same `generationId`.

A new `generationId` is required when:

- the active session is replaced
- the existing generation is explicitly cancelled and restarted
- a stale plan must be abandoned in favor of a new preparation sequence

### Ownership Rule

The runtime owns:

- active generation bookkeeping
- in-flight background work
- runtime-local queue preparation state
- cache mutation for generated speech output

The controller owns:

- visible transport state
- user intent
- current reading position as app state
- final interpretation of runtime events into UI state

### Cancellation Rule

Cancelling a session or generation must:

- prevent later stale events from mutating the active session
- cancel not-yet-started queued work for that owner
- allow already completed chunk files to remain cached

### Shutdown Rule

Shutdown must:

- stop accepting new commands
- cancel or drain in-flight work according to implementation safety
- emit one terminal runtime shutdown event
- release runtime-owned background resources

### Failure Rule

Fatal runtime failure moves the instance to `failed` until the runtime is explicitly reinitialized or recreated.

Recoverable chunk-level failures do not automatically destroy the runtime instance.

## Constraints

- Session ownership and generation ownership must remain explicit string ids.
- Stale results must be rejectable using ownership checks alone.
- Cache lifetime must remain independent from session lifetime.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The runtime has a stable lifecycle model.
- Session and generation ownership are explicit and separable.
- Cancellation and shutdown rules prevent stale ownership from mutating current playback.
