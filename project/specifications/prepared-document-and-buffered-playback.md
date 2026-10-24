# Prepared Document and Buffered Playback

## Architecture ownership

- [system overview](../architecture/system-overview.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the active ACD/plan.

Date: October 24, 2026
Status: Final target contract; implementation and verification pending

## Parent Architecture

[Document Preparation and Execution Contexts](../acd/prepared-document-runtime.acd)

## Scope

This leaf specifies the integrated readiness handoff from document preparation to buffered playback. Character schema, runtime lifecycle and cache details remain owned by their existing specifications.

## Behavior

- Viewing a document is permitted before its speech preparation completes.
- Playback eligibility requires a complete instrumented document revision, resolved character voice bindings (including explicit unresolved-speaker fallback), resident required voice resources and sufficient contiguous finalized startup audio.
- Whole-document waveform generation is not a prerequisite. A bounded scheduler generates ahead of the playhead using configurable startup, low and high watermarks measured in playable time. All remaining audio ready is sufficient for a short document.
- Ordinary character boundaries select prepared resident context without session invalidation, model reload or transport restart.
- User assignment changes publish a new binding revision at a future safe boundary after replacement audio is ready. Pending and effective assignments are distinguishable. Only the latest revision can begin initial playback.
- Main-isolate work is limited to UI/control and bounded state acceptance. Full-document analysis, realization, planning, inference, audio serialization and export are worker-owned. Platform-thread requirements do not authorize heavy main-thread processing.
- Revision ownership guards success, error, cancellation and cleanup. Unexpected worker exit and timeout terminate outstanding requests; resource cleanup is awaitable.

## Acceptance

The paired [test specification](../test-specifications/prepared-document-and-buffered-playback.md) must demonstrate readiness gates, continuous A/B/A playback, bounded lead and resources, assignment commits, stale-reload rejection, UI responsiveness and failure recovery. Native audio/resource tests and running-app evidence supplement deterministic unit tests. No implementation completion is asserted by finalizing this contract.
