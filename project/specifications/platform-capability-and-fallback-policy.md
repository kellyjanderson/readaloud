# Platform Capability and Fallback Policy

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines how the speech runtime boundary behaves when platform concurrency or local-engine capability differs across Flutter targets.

## Backlink

Parent specification:

- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)

## Scope

This specification covers:

- runtime capability discovery
- platform-specific concurrency assumptions
- unsupported-engine and degraded-mode behavior

## Behavior

### Facade Stability Rule

The speech runtime facade API must stay stable across platforms even when the underlying implementation differs.

### Capability Discovery Rule

During runtime initialization, the speech subsystem must determine and surface at least:

- whether long-lived background worker execution is supported for the active platform path
- whether background plugin request/response calls are supported for the active platform path
- whether the requested local speech engine is supported on the active platform path

### Native Platform Rule

On native Flutter platforms, the runtime may use:

- long-lived isolates for repeated background work
- background-isolate plugin request/response calls where supported
- platform-specific native background queue policy underneath the adapter

### Web Rule

The web implementation must not assume true background offload from `compute` as its primary responsiveness guarantee.

If the local speech engine cannot meet responsiveness or capability requirements on web, the runtime must surface that as unsupported or degraded rather than pretending parity with native.

### Unsupported Engine Rule

If the requested engine is unavailable on the current platform path, the runtime must emit a deterministic unsupported or unavailable state rather than failing deep inside generation work.

### Fallback Ownership Rule

Selecting an alternate engine after unsupported detection is controller or engine-selection policy, not runtime-worker policy.

The runtime reports capability; it does not silently swap engines on its own.

### Cache Rule

Platform fallback behavior must not corrupt or confuse cache ownership across engines.

Engine-specific caches remain distinct.

## Constraints

- The runtime boundary contract must survive platform variation without becoming platform-specific at the controller call site.
- Unsupported local-engine behavior must be explicit and observable.
- Web behavior must not be specified as if it had native isolate guarantees.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The runtime can report what concurrency and engine capabilities exist on the current platform path.
- Unsupported local-engine cases fail explicitly rather than implicitly.
- Controller-side code can keep one stable facade even when the underlying platform implementation differs.
