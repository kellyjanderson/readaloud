# Pronunciation Diagnostics and Observability

Last updated: April 3, 2026
Status: Final specification

## Overview

This specification defines how pronunciation planning and realization expose unresolved, degraded, and resolved cases for QA, export sidecars, and future tooling.

## Backlink

Parent specification:

- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)

## Scope

This specification covers:

- diagnostic codes for pronunciation planning
- realization and engine-translation observability
- export/headless sidecar requirements
- persistent debug trace and probe-support artifacts used for pronunciation QA

This specification does not define general playback instrumentation.

## Behavior

### Required Diagnostic Codes

The first implementation round must support these stable codes:

- `pronunciation.resolved.lexicon`
- `pronunciation.resolved.source_metadata`
- `pronunciation.context_sensitive.pending`
- `pronunciation.context_sensitive.resolved`
- `pronunciation.unresolved.document_time`
- `pronunciation.unresolved.voice_session`
- `pronunciation.translation.approximated`
- `pronunciation.translation.deferred`

### Emission Rule

Diagnostics must be attachable to:

- `PronunciationArtifact`
- `RealizedPronunciationArtifact`
- exported/headless sidecar metadata

### Unresolved Rule

If document-time planning or voice/session realization cannot confidently resolve a pronunciation case, the unresolved condition must remain inspectable through diagnostics rather than disappearing into a silent engine fallback.

### Sidecar Rule

Headless export and interactive audio export sidecars must include pronunciation diagnostics for every chunk or exported session that contains:

- unresolved cases
- context-sensitive resolutions
- approximated or deferred engine translation outcomes

### Runtime Trace Rule

Interactive playback may emit a durable per-session pronunciation trace log for QA.

When present, that trace must preserve enough information to inspect:

- source chunk text
- engine-facing speak text
- payload units or equivalent token-grouping detail
- translated pronunciation artifacts
- final phoneme strings
- both canonical internal and engine-facing phoneme strings when they differ

The trace log path itself must remain visible to the app for inspection.

### Probe Artifact Rule

Pronunciation QA tooling that exports probe WAVs must emit durable manifests and waveform-analysis data that preserve:

- probe case id or sentence identity
- source text
- output WAV path
- sidecar or trace-log references when available
- waveform/hash comparison output when a baseline comparison run is requested

### Metrics Rule

The first implementation round must expose at least these aggregate counters:

- total pronunciation artifacts considered
- count of resolved lexical artifacts
- count of context-sensitive artifacts
- count of unresolved artifacts
- count of approximated engine translations

## Constraints

- pronunciation diagnostics must not require audio generation to exist before they can be emitted
- diagnostic codes must stay stable enough for regression tooling
- pronunciation observability must remain separate from general playback timing instrumentation
- pronunciation QA artifacts should use stable project-owned directories when a project root is available rather than ephemeral app-container-only locations

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The system can surface pronunciation decisions and failures as durable diagnostics.
- Export and headless flows can expose pronunciation state without requiring human inspection of runtime logs.
- Unresolved or approximated pronunciation behavior remains visible for future tuning work.
- Interactive playback and probe harnesses can emit durable pronunciation-trace artifacts for QA review.
