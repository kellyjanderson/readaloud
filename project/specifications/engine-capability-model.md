# Engine Capability Model

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines the app-owned model that describes what a speech engine can directly express, approximate, or only defer.

## Backlink

Parent specification:

- [Engine Pronunciation Expression and Capability Adaptation](engine-pronunciation-expression-and-capability-adaptation.md)

## Scope

This specification covers:

- required engine-capability fields
- capability identity and lookup behavior
- direct and approximable representation declarations

This specification does not define how a translated engine payload is physically built.

## Behavior

### Required Fields

An engine capability model must contain at least:

- `String capabilityProfileId`
- `String engineId`
- `String platformFamily`
- `String capabilityVersion`
- `Set<String> directRepresentationTypes`
- `Set<String> approximableRepresentationTypes`
- `bool supportsPlainTextFallback`

### Identity Rule

`capabilityProfileId` must be stable enough to appear in:

- diagnostics
- runtime trace metadata
- export sidecars
- future QA reports

### Lookup Rule

Capability lookup must be deterministic for the same:

- engine id
- platform family
- capability version selector inputs

### Representation Rules

If a representation type appears in:

- `directRepresentationTypes`, it may be expressed directly by the adapter
- `approximableRepresentationTypes`, it may be expressed only through an approximation path

If a representation type appears in neither set, the engine must treat it as deferred or unsupported rather than silently assuming direct support.

### Current-Engine Rule

For the first Kokoro-capable native path, the capability model must make explicit at least:

- direct support for `phoneme_string`
- approximation handling for `normalized_spoken_text`
- plain-text fallback availability

## Constraints

- Capability data must be app-owned rather than inferred implicitly from scattered adapter code.
- Capability lookup must not depend on synthesis success as a discovery mechanism.
- The capability model must remain engine-agnostic enough that future engines can provide their own capability profiles.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The system has one explicit app-owned model for engine pronunciation capability.
- Direct, approximable, and deferred expression paths are grounded in explicit capability data.
- Runtime and export traces can identify the capability profile that shaped expression behavior.
