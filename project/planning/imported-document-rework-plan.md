# Imported Document Rework Plan

Last updated: March 29, 2026
Status: Active plan

## Objective

Replace the current flat-string imported-document playback path with a normalized, segment-aware, workerized pipeline.

## Driving Specifications

- [Normalized Document Model](../specifications/normalized-document-model.md)
- [Display Document](../specifications/display-document.md)
- [Speech Document](../specifications/speech-document.md)
- [Importer Normalization Contract](../specifications/importer-normalization-contract.md)
- [Chunk Planning](../specifications/chunk-planning.md)
- [Speech Worker Pipeline](../specifications/speech-worker-pipeline.md)
- [Generated Audio Cache](../specifications/generated-audio-cache.md)
- [Playback Coordination](../specifications/playback-coordination.md)
- [Playback Progress and Jump Mapping](../specifications/playback-progress-and-jump-mapping.md)

## Why This Plan Exists

Current imported-document playback issues share the same root causes:

- weak internal document structure
- chunk planning against flattened strings
- insufficient boundary awareness for pronunciation and cadence
- heavy speech work occurring on the main isolate

## Execution Order

### Phase A: Normalized document types

Deliverables:

- `DisplayDocument`
- `SpeechDocument`
- stable segment and block ids
- mapping primitives for future highlighting

### Phase B: One importer end-to-end

Recommended first importer:

- plain text or pasted text

Deliverables:

- importer emits normalized documents
- controller consumes normalized speech structure
- no dependency on the old flat-string-only path for that importer

### Phase C: Segment-aware chunk planner

Deliverables:

- planner accepts `SpeechDocument`
- chunk boundaries prefer sentence and paragraph structure
- planner output includes chunk ids, segment ids, and offset maps

### Phase D: Workerized speech pipeline

Deliverables:

- phonemization off the UI isolate
- ONNX inference off the UI isolate
- wav serialization off the UI isolate
- explicit playback job and queue events back to the controller

### Phase E: Imported format migration

Recommended migration order:

- pasted text and plain text
- HTML
- EPUB
- DOCX / RTF
- PDF refinement

## Immediate Next Slice

The next implementation slice should be:

- define normalized document types
- wire one importer through them
- adapt playback planning to those types before more Kokoro behavior changes

## Risks

- importer migration will temporarily require coexistence between old and new document models
- PDF extraction quality remains format-dependent
- worker isolation may require careful serialization boundaries for model inputs and outputs

## Success Criteria

- imported content no longer depends on one flat `speakableText` field as the only speech contract
- playback starts after first-chunk preparation rather than whole-tail synthesis
- later chunks prepare without freezing the interface
- the new model is ready for future highlighting
