# Sendable Runtime DTO Contract

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines what data may cross the speech runtime boundary and how runtime messages must be represented.

## Backlink

Parent specification:

- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)

## Scope

This specification covers:

- allowed runtime message value types
- forbidden cross-boundary objects
- required envelope fields
- representation rules for ids, enums, timestamps, and large payloads

## Behavior

### Allowed Value Rule

Runtime message payloads may contain only:

- `null`
- `bool`
- `int`
- `double`
- `String`
- `Uint8List`
- `List` of allowed values
- `Map<String, Object?>` composed only of allowed values

All command and event DTOs must be reducible to those shapes.

### Forbidden Value Rule

Runtime messages must not carry:

- closures or tear-offs
- `Future`, `Completer`, `Stream`, `StreamController`, `Sink`, or subscription objects
- controller, widget, engine, player, or plugin instances
- `File`, `Directory`, or other live I/O handles
- isolate ports except as part of the runtime implementation internals
- arbitrary object graphs that do not serialize into the allowed value set

### Envelope Rule

Every runtime command and runtime event must serialize as an envelope with:

- `String protocolVersion`
- `String runtimeId`
- `String messageId`
- `String type`
- `int issuedAtMillis` or `int emittedAtMillis`
- `Map<String, Object?> payload`

### Version Rule

The initial protocol version string is:

- `speech-runtime-v1`

Every command and event on one runtime channel must use the same protocol version.

### Identifier Rule

Cross-boundary identity values must be represented as strings, including:

- `runtimeId`
- `sessionId`
- `generationId`
- `documentId`
- `chunkId`
- `voiceId`
- `planId`

### Enum Rule

Enums must cross the boundary as stable lowercase strings, not ordinal integers.

### Timestamp Rule

Timestamps must cross the boundary as UTC epoch milliseconds.

### Large Payload Rule

The boundary must prefer references over bulk payloads.

Required preferences:

- send generated audio file paths, not audio bytes, for prepared chunks
- send document or chunk ids, not controller-owned objects
- send only the realization or chunk window needed for active work, not whole-document runtime copies

If raw binary transfer becomes necessary later, it must use a boundary-specific binary contract rather than ad hoc object passing.

### Serialization Rule

All runtime DTOs must have deterministic `toMap` / `fromMap` behavior or the equivalent typed serialization layer.

## Constraints

- The runtime boundary must not depend on closure capture.
- DTOs must remain valid for isolate messaging and background plugin request/response paths.
- The representation must be stable enough to support future tracing and test fixtures.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Runtime commands and events can be reduced to a sendable envelope plus sendable payload.
- No controller-owned or engine-owned live objects are required to cross the boundary.
- The protocol has one stable version string and stable string ids for ownership.
