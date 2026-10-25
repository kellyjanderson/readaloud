# Speech Worker Pipeline

## Architecture ownership

- [document speech pipeline](../architecture/document-speech-pipeline.md)
- [speech runtime messaging boundary](../architecture/speech-runtime-messaging-boundary.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)
- [system overview](../architecture/system-overview.md)
- [playback orchestration and synthesis boundaries](../architecture/playback-orchestration-and-synthesis-boundaries.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Last updated: October 24, 2026
Status: Final specification

## Scope

This specification defines the background execution pipeline that turns `ChunkSpec` values into generated audio assets.

## Backlink

Parent specification:

- [Imported Document Playback](imported-document-playback.md)

## Primary Goal

Heavy speech generation work must not block the UI isolate.

## Worker Ownership

The worker pipeline owns:

- cache lookup
- phonemization
- model inference
- waveform serialization
- cache write
- generation diagnostics

The controller does not own these steps.

## Required Commands

`SpeechWorkerCommand` must support:

- `prepareChunk`
- `preparePlan`
- `cancelGeneration`
- `shutdown`

## Required Events

`SpeechWorkerEvent` must support:

- `queued`
- `cacheHit`
- `phonemizing`
- `inferencing`
- `serializing`
- `completed`
- `failed`
- `cancelled`

Every event must include:

- `String generationId`
- `String chunkId`
- `DateTime emittedAt`
- `String stage`

## Concurrency Rules

- The initial implementation uses one active inference worker per engine instance.
- The first chunk for the active playback request has strict priority over all later chunks.
- Background generation for later chunks may continue while playback is running.
- Document replacement invalidates the old preparation revision. Ordinary character changes select resident voice context without cancellation. User assignment/rate edits generate a replacement future revision and commit it only after contiguous replacement audio is ready.
- Background generation stays sequential in `v1`; it does not fan out multiple inference jobs in parallel.

## Document and Buffer Contract

The worker consumes a fully analyzed instrumented document and resident character voice bindings. It does not infer speakers while rendering. The runtime worker and model session are long-lived; inference tensors are released per request. Realization, route derivation and chunk planning run in this worker rather than the UI controller.

Scheduling uses bounded contiguous playable-time watermarks, with active refill ahead of export/speculative work. First-chunk priority does not bypass the startup lead gate. Worker exit, timeout, cancellation and shutdown must resolve owned requests. [Document Preparation and Execution Contexts](https://github.com/kellyjanderson/readaloud/issues/48) defines execution lanes and handoffs.

## Stage Rules

### Cache Lookup

- Check the generated-audio cache before phonemization.
- On cache hit, emit `cacheHit` and then `completed` without inference.

### Phonemization

- Operate on `ChunkSpec.speakText`.
- Emit instrumentation timing.

### Inference

- Run model inference off the UI isolate.
- Emit instrumentation timing.

### Serialization

- Write the final audio file to cache storage.
- Emit final duration metadata.
- Emit the written audio path in the `completed` event.

## Cancellation Rules

- Cancelling a generation sequence does not delete completed chunk files.
- Cancelling a sequence suppresses stale completion events from mutating controller state.

## Failure Rules

- One chunk failure fails that chunk and surfaces a structured error event.
- Later chunks in the same generation sequence may be cancelled after a fatal worker failure.
- Failed chunks do not poison previously cached chunks.

## Constraints

- Heavy speech generation must remain off the UI isolate.
- Worker cancellation must suppress stale result ownership changes.
- The first chunk must retain scheduling priority over later chunks.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Speech generation can be driven through worker commands and events rather than UI-thread inference.
- Cache hits bypass unnecessary inference.
- Sequence cancellation prevents stale completions from mutating active playback state.
