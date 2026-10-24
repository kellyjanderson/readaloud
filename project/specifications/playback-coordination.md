# Playback Coordination

## Architecture ownership

- [document speech pipeline](../architecture/document-speech-pipeline.md)
- [speech runtime messaging boundary](../architecture/speech-runtime-messaging-boundary.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)
- [system overview](../architecture/system-overview.md)
- [audio export and headless execution](../architecture/audio-export-and-headless-execution.md)
- [playback orchestration and synthesis boundaries](../architecture/playback-orchestration-and-synthesis-boundaries.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the active ACD/plan.

Last updated: October 24, 2026
Status: Final specification

Issue anchor:

- GitHub issue `#20`

## Scope

This specification defines controller-level playback behavior for imported documents.

## Backlink

Parent specification:

- [Imported Document Playback](imported-document-playback.md)

## Required Controller States

The playback coordinator must expose exactly one primary state at a time:

- `idle`
- `bufferingFirstChunk`
- `playing`
- `paused`
- `completed`
- `failed`

The coordinator may also expose side-channel state such as:

- `isBackgroundBuffering`
- `activeGenerationId`
- `activeChunkId`
- `completedAtEndOfDocument`

## Transport Actions

Supported actions:

- `play`
- `pause`
- `jumpBackward30`
- `jumpForward30`
- `setRate`
- `setVoice`
- `setSleepTimer`
- `cancelSleepTimer`

There is no stop action.

Unsupported action:

- `stop`

## Play Semantics

- If the state is `idle`, `play` begins from the current reading position.
- If the state is `paused`, `play` resumes from the current reading position.
- If the state is `completed`, `play` resets the reading position to the beginning and starts replay.
- After whole-document preparation, if contiguous audio lead is below the configured startup target, `play` enters `bufferingFirstChunk` (the retained state name now covers startup lead preparation). Before document readiness, the document processing state owns progress.
- If document readiness and startup lead are satisfied, `play` may transition directly to `playing`; a short document may start when all remaining audio is ready.

## First-Chunk Startup Behavior

- While the first chunk is buffering, the transport row is the only required place to show startup activity.
- The play icon is replaced by animated dots during `bufferingFirstChunk`.
- Normal first-chunk generation does not trigger a broad global warning banner.

## Queue Behavior

- Playback begins after document readiness and contiguous startup lead; [Document Preparation and Execution Contexts](../acd/prepared-document-runtime.acd) defines watermark and short-document semantics.
- Audio is generated ahead of the playhead; finalized contiguous chunks append to the active queue without restart.
- Later routed chunks must continue forward playback without requiring a user pause/play recovery cycle.
- Pausing playback does not delete completed chunk files.
- Ordinary character voice transitions do not invalidate the session or queue. User voice/rate edits prepare a replacement revision, then commit a future queue boundary only when replacement lead is ready. Preserve current audio; show a pending assignment until effective. If safe tail replacement is unsupported, defer application or expose explicit rebuffering rather than silently restarting. During startup, only the newest requested revision may start.
- Jumping clears the in-memory queue from the old position and requests a new plan from the jump target.

## Completion Behavior

- Reaching the end of the document sets the state to `completed`.
- Reaching the end of the document does not automatically reset the reading position.
- The reset happens on the next `play` action.

## Sleep Timer Behavior

- Sleep timer expiry fades playback out rather than stopping abruptly.
- Initial fade duration is `3` seconds.
- Fade completion ends playback in the same way as a user pause unless the end of document is reached during the fade.
- Fade state must not discard prepared chunk files.

## Error Behavior

- A chunk-generation failure moves the coordinator to `failed` only if playback cannot continue from already prepared audio.
- Recoverable later-chunk failures may surface an error while preserving current playback until the queue is exhausted.
- Silent progress/highlight loops over already-spoken content are not a valid recovery mode.

## Constraints

- The controller must expose exactly one primary transport state at a time.
- Queue ownership and cache ownership remain separate concerns.
- There is no stop action in the transport model.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Verification Status

The October 24 changes are target behavior, not verified implementation. Paired scenarios are in [Prepared Document and Buffered Playback](../test-specifications/prepared-document-and-buffered-playback.md).

## Acceptance

- Controller state transitions are defined for play, pause, replay, jump, rate change, voice change, and sleep fade.
- Playback completion and replay semantics are explicit.
- Startup buffering is scoped to the transport controls rather than a broad warning banner.
- Queued routed playback does not require manual pause/play intervention to continue after the first chunk.
