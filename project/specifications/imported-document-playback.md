# Imported Document Playback

Last updated: April 8, 2026
Status: Draft specification

## Scope

This is the umbrella specification for imported-document playback.

It defines the end-to-end playback contract for imported documents and delegates implementation detail to smaller focused specifications.

## Backlink

Parent architecture:

- [Document and Speech Pipeline](../architecture/document-speech-pipeline.md)

Detailed implementation specifications:

- [First-Chunk Startup Contract](first-chunk-startup-contract.md)
- [Imported Playback Responsiveness Policy](imported-playback-responsiveness-policy.md)
- [Voice and Session Realization](voice-session-realization.md)
- [Narration State](narration-state.md)
- [Chunk Planning](chunk-planning.md)
- [Speech Worker Pipeline](speech-worker-pipeline.md)
- [Generated Audio Cache](generated-audio-cache.md)
- [Synthesis Boundary Policy](synthesis-boundary-policy.md)
- [Playback Coordination](playback-coordination.md)
- [Audio-Authoritative Playback Synchronization](audio-authoritative-playback-synchronization.md)
- [Playback Progress and Jump Mapping](playback-progress-and-jump-mapping.md)
- [Document Replacement Playback Reset And Stale Event Rejection](document-replacement-playback-reset-and-stale-event-rejection.md)
- [Playback Quality Instrumentation](playback-quality-instrumentation.md)
- [Reader Session Continuity and Live Input](reader-session-continuity-and-live-input.md)

## Behavior

The imported-playback branch now delegates detailed startup, responsiveness, generation, boundary, and transport behavior to focused child specifications.

In particular:

- first-chunk startup behavior belongs to its own leaf
- responsiveness policy for ordinary imported documents belongs to its own leaf
- realization, generation, boundary, progress, and controller transport behavior belong to their respective leaves
- audio-authoritative playback synchronization belongs to its own branch because uninterrupted speech requires stricter coordination rules than ordinary transport state alone
- file-backed reader continuity and watched-file live input belong to their own leaf because they change how imported content is refreshed without changing the shared speech pipeline
- remembered last-heard position and startup resume belong to the reader-continuity branch rather than being left implicit

This parent specification keeps only the branch-level rule that imported playback is an end-to-end path over normalized speech content rather than a separate flat-string playback system.

## Refinement Status

This is a draft umbrella specification. Its child specifications are expected to carry most implementation detail.

## Child Specifications

- [First-Chunk Startup Contract](first-chunk-startup-contract.md)
- [Imported Playback Responsiveness Policy](imported-playback-responsiveness-policy.md)
- [Voice and Session Realization](voice-session-realization.md)
- [Narration State](narration-state.md)
- [Chunk Planning](chunk-planning.md)
- [Speech Worker Pipeline](speech-worker-pipeline.md)
- [Generated Audio Cache](generated-audio-cache.md)
- [Synthesis Boundary Policy](synthesis-boundary-policy.md)
- [Playback Coordination](playback-coordination.md)
- [Audio-Authoritative Playback Synchronization](audio-authoritative-playback-synchronization.md)
- [Playback Progress and Jump Mapping](playback-progress-and-jump-mapping.md)
- [Document Replacement Playback Reset And Stale Event Rejection](document-replacement-playback-reset-and-stale-event-rejection.md)
- [Playback Quality Instrumentation](playback-quality-instrumentation.md)
- [Reader Session Continuity and Live Input](reader-session-continuity-and-live-input.md)

## Acceptance Criteria

- Imported playback does not require a whole-document synthesis pass before audio starts.
- Imported playback does not depend on a legacy monolithic `speakableText` field.
- Progress, replay, and jump behavior can be defined in terms of chunk ids, segment ids, and word ranges.
- Imported playback exposes enough metrics to evaluate latency, cache reuse, and boundary quality.
- The remaining imported-playback work is represented by final leaf specifications.
