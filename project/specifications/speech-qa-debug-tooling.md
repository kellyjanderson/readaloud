# Speech QA Debug Tooling

Last updated: April 3, 2026
Status: Final specification

## Overview

This specification defines the developer-facing tooling that lets `Read Aloud` inspect and compare real speech output without introducing a second synthesis implementation.

## Backlink

Parent specification:

- [Audio Export and Headless Execution](audio-export-and-headless-execution.md)

## Scope

This specification covers:

- pronunciation probe mode for short phrase lists
- sentence-probe mode over real imported documents
- waveform/hash comparison for before/after verification
- persistent trace and probe artifact storage
- interactive TTS debug trace logging and live-tail inspection

This specification does not redefine general playback metrics or end-user export behavior.

## Behavior

### Stable-Artifact Rule

When a project root can be resolved, QA artifacts must be written to durable project-owned directories under:

- `project/test-artifacts/tts-debug-traces/`
- `project/test-artifacts/pronunciation-probes/`
- `project/test-artifacts/sentence-probes/`

If no project root can be resolved, the app may fall back to application-support storage.

### Pronunciation-Probe Rule

Pronunciation-probe mode must accept:

- a phrase list file
- inline repeated probe text values

Each probe case must export one WAV through the shared importer, realization, runtime, and export path and must emit a run manifest that records:

- case id
- source text
- output WAV path
- sidecar path
- waveform/hash analysis summary

### Comparison Rule

When a probe run is compared against an earlier run, the harness must emit a comparison report that can distinguish:

- changed audio
- unchanged audio
- missing baseline cases
- missing current cases

Identical PCM output counts as "no audio change" for regression purposes.

### Sentence-Probe Rule

Sentence-probe mode must import a real source document through the shared importer, extract ordered speech segments or sentences, and export one WAV per sentence case.

The run must emit:

- a manifest
- a combined run log
- one per-sentence WAV and sidecar
- the trace-log path used for each sentence export when available

### Interactive-Trace Rule

Interactive playback must be able to create a per-session TTS debug trace log named by:

- session start time
- selected voice id

The trace must preserve enough detail to inspect:

- source chunk text
- engine-facing speak text
- payload units
- pronunciation artifacts
- final phoneme strings
- canonical internal and engine-facing phoneme strings when they differ

### Live-Tail Rule

The running app may surface a live tail of recent trace lines plus the durable trace-log path for the current session.

## Constraints

- QA tooling must reuse the shared synthesis pipeline rather than a separate testing-only synthesis path.
- Probe tooling must remain useful offline and must not depend on network telemetry infrastructure.
- Stable artifact storage must prefer non-ephemeral project-owned paths when available.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Developers can run phrase probes and sentence probes through the real speech pipeline.
- Before/after waveform comparison can detect unchanged audio and therefore catch ineffective pronunciation fixes.
- Interactive playback can emit durable trace logs that remain easy to inspect from the editor.
- Probe and trace artifacts remain in stable project-owned directories when the project root is available.
