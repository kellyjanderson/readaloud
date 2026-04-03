# Audio Export Assembly

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines how finalized chunk audio becomes one exported audio file.

## Backlink

Parent specification:

- [Audio Export and Headless Execution](audio-export-and-headless-execution.md)

## Scope

This specification covers:

- ordered chunk collection for export
- exported WAV file assembly
- export metadata sidecar creation
- output naming defaults

## Behavior

### Input Rule

Audio export assembly consumes finalized chunk outputs only.

Each input chunk must already have:

- synthesis completed
- boundary correction applied
- a stable output WAV path
- duration metadata

### Ordering Rule

Chunks must be assembled in chunk-plan order.

Late-arriving chunk completion events must not reorder the exported output.

### Output Format Rule

The initial exported audio format is:

- one PCM WAV file

The exported WAV must preserve:

- sample rate used by the engine output
- single-channel PCM layout
- concatenated finalized chunk PCM data with no added player gap

### Format Consistency Rule

All chunks assembled into one exported file must have matching:

- sample rate
- channel count
- PCM format

If the chunk set is not format-compatible, export must fail with a clear error instead of producing a malformed file.

### Sidecar Rule

Every exported WAV must have a JSON sidecar written adjacent to it.

The sidecar must include:

- `exportId`
- `createdAt`
- `engineId`
- `engineVersion`
- `documentId`
- `documentTitle`
- `voiceId`
- `rate`
- `normalizationVersion`
- `chunkCount`
- `durationMillis`
- `outputPath`
- `sourceDescription`
- ordered chunk metadata list containing:
  - `chunkId`
  - `cacheKey`
  - `audioPath`
  - `durationMillis`
  - `segmentIds`
  - `startWordIndex`
  - `endWordIndex`

### Default Naming Rule

If the caller does not provide an explicit output path, the export system must derive:

- `{sourceBaseName} - {voiceId}.wav`

and write the sidecar as:

- `{sourceBaseName} - {voiceId}.json`

### Failure Rule

If any chunk required for export fails, the assembly step must fail the export and must not write a partial final WAV.

## Constraints

- exported output must reflect finalized chunk audio, not pre-correction chunk audio
- assembly must remain local and offline-friendly
- export metadata must be small, structured, and human-inspectable

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- one full-document WAV can be assembled from finalized chunk files in stable order
- each exported WAV has a JSON sidecar with enough metadata to inspect chunk provenance later
- malformed mixed-format chunk sets fail clearly instead of producing broken output
