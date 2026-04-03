# Native Engine Queue Policy

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines how native speech-engine adapter work must be queued so Flutter responsiveness does not depend on lucky default plugin threading.

## Backlink

Parent specification:

- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)

## Scope

This specification covers:

- platform-channel handler queue rules
- native background-dispatch rules for heavy work
- session-affinity rules for native engine work

## Behavior

### General Rule

Heavy native work must not run on the main UI thread by default.

Heavy native work includes:

- ONNX session creation
- inference
- large tensor conversion
- large file I/O
- audio serialization
- session teardown if the engine requires meaningful cleanup work

### Apple Embedder Rule

On iOS and macOS, when the embedder supports background task queues for method channels, engine adapters or plugins that may do heavy synchronous work must use a background task queue for their method handlers.

### Background Dispatch Rule

If a plugin handler still contains heavy native sections after request receipt, those sections must dispatch onto a dedicated background queue or executor before running the heavy work.

### Serial Session Rule

For one runtime instance and one native engine instance, heavy native engine operations must execute on one dedicated adapter queue unless a later engine-specific specification explicitly allows safe parallelism.

That queue owns:

- session open
- inference calls
- session close or disposal

### Result Delivery Rule

Results may return to the framework-facing callback thread only for response delivery.

Heavy computation must already be complete before returning to that thread.

### Plugin Isolation Rule

Controller code and widget code must not call heavy native engine APIs directly.

All such work must pass through the speech runtime and native engine adapter.

### Request/Response Rule

Background-isolate plugin usage must assume request/response semantics only.

The native engine adapter must not depend on unsolicited host-to-isolate callbacks as part of its normal execution contract.

## Constraints

- Queue policy must be explicit in the adapter or plugin implementation.
- “Off the UI isolate” is not sufficient if the plugin still performs heavy work on a UI-relevant native thread.
- The initial implementation remains sequential per runtime instance.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Native queue policy is explicitly defined for heavy engine work.
- The runtime architecture no longer relies on default plugin threading as an unspoken assumption.
- One runtime instance can perform engine work without blocking the Flutter UI thread by policy.
