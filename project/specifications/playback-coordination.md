# Playback Coordination

Last updated: March 30, 2026
Status: Final specification

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
- If no prepared audio exists for the current position, `play` enters `bufferingFirstChunk`.
- If prepared audio already exists for the current position, `play` may transition directly to `playing`.

## First-Chunk Startup Behavior

- While the first chunk is buffering, the transport row is the only required place to show startup activity.
- The play icon is replaced by animated dots during `bufferingFirstChunk`.
- Normal first-chunk generation does not trigger a broad global warning banner.

## Queue Behavior

- Playback begins as soon as the first chunk is ready.
- Later chunks queue behind active playback.
- Pausing playback does not delete completed chunk files.
- Changing voice or rate clears the in-memory queue and starts a new generation sequence, but it does not delete cached chunk files.
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

## Constraints

- The controller must expose exactly one primary transport state at a time.
- Queue ownership and cache ownership remain separate concerns.
- There is no stop action in the transport model.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Controller state transitions are defined for play, pause, replay, jump, rate change, voice change, and sleep fade.
- Playback completion and replay semantics are explicit.
- Startup buffering is scoped to the transport controls rather than a broad warning banner.
