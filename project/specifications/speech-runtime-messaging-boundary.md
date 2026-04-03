# Speech Runtime Messaging Boundary

Last updated: March 30, 2026
Status: Draft specification

## Overview

This specification defines the formal runtime boundary between controller/UI code and repeated background speech work.

## Backlink

Parent architecture:

- [Speech Runtime Messaging Boundary](../architecture/speech-runtime-messaging-boundary.md)

## Scope

This specification covers:

- the runtime-facing command/event boundary
- the sendable DTO rules for that boundary
- runtime lifecycle and ownership
- native engine queue policy
- platform capability and fallback behavior

This specification does not define chunk planning, cache keys, or playback UI state.

## Behavior

### Boundary Rule

The controller must reach repeated speech work only through a runtime facade that exchanges explicit commands and events.

### Message Rule

The runtime boundary must carry only sendable DTOs and stable identifiers.

### Lifecycle Rule

The runtime owns long-lived background execution and session-scoped generation ownership.

### Native Queue Rule

Heavy native engine work must follow explicit queue policy rather than inheriting whatever thread the default plugin handler uses.

### Platform Rule

The runtime facade contract must stay stable across platforms even when implementation capability differs underneath.

## Constraints

- This boundary remains local to the speech subsystem, not the whole app.
- The runtime boundary must remain explicit even if helper utilities such as `compute` are used inside the implementation.
- Child specifications must refine protocol shape, payload rules, lifecycle ownership, native queue policy, and platform fallback behavior.

## Refinement Status

This specification requires further refinement.

## Child Specifications

- [Sendable Runtime DTO Contract](sendable-runtime-dto-contract.md)
- [Speech Runtime Lifecycle and Ownership](speech-runtime-lifecycle-and-ownership.md)
- [Speech Runtime Command Protocol](speech-runtime-command-protocol.md)
- [Speech Runtime Event Protocol](speech-runtime-event-protocol.md)
- [Native Engine Queue Policy](native-engine-queue-policy.md)
- [Platform Capability and Fallback Policy](platform-capability-and-fallback-policy.md)

## Acceptance

- The system has one explicit specification parent for the speech runtime boundary.
- DTO rules, lifecycle rules, protocol rules, native queue policy, and platform policy are delegated to focused child specifications.
