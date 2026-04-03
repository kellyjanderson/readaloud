# Boundary Candidate Metadata Contract

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines the metadata contract required for a chunk to enter synthesis-boundary correction.

## Backlink

Parent specification:

- [Synthesis Boundary Policy](synthesis-boundary-policy.md)

## Scope

This specification covers:

- boundary taxonomy
- required per-chunk boundary metadata
- measurement fields carried into boundary correction and later observability

This specification does not define numeric silence thresholds or the correction algorithm itself.

## Behavior

### Boundary Taxonomy

The first implementation round must support these boundary classes:

- `none`
- `weak`
- `sentence`
- `paragraph`
- `section`

### Required Chunk Metadata

Every chunk candidate entering boundary correction must provide:

- `String chunkId`
- `BreakClass boundaryClass`
- `Duration leadingSilence`
- `Duration trailingSilence`
- `bool isInitialChunk`
- `bool isResumedChunk`

### Measurement Rule

- `leadingSilence` and `trailingSilence` represent measured silent spans from generated chunk audio
- these measurements must remain distinguishable from intended linguistic boundary class
- metadata must remain available for debug instrumentation and export sidecars after correction

## Constraints

- chunk-boundary metadata must remain deterministic for the same audio input and measurement policy
- metadata must stay independent from player-level buffering state
- the contract must remain small enough to cross runtime and cache boundaries cheaply

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Boundary correction begins from an explicit metadata contract instead of ad hoc chunk inspection.
- Intended boundary class stays distinct from measured audio silence.
- The system has a stable boundary vocabulary shared across planning, correction, and observability.
