# Chunk Planning

Last updated: March 30, 2026
Status: Final specification

## Scope

This specification defines how `SpeechDocument` content becomes ordered speech chunks for playback generation.

## Backlink

Parent specification:

- [Imported Document Playback](imported-document-playback.md)

## Required Input

`ChunkPlannerInput` must contain:

- `SpeechDocument speechDocument`
- `String startSegmentId`
- `String voiceId`
- `double rate`
- `String engineId`
- `String engineVersion`

## Required Output

`ChunkPlan` must contain:

- `String planId`
- `List<ChunkSpec> chunks`

Every `ChunkSpec` must contain:

- `String chunkId`
- `List<String> segmentIds`
- `String speakText`
- `int startSegmentIndex`
- `int endSegmentIndex`
- `int estimatedWordCount`
- `String cacheKey`
- `int startWordIndex`
- `int endWordIndex`

## Planner Targets

- First chunk target duration: approximately `4` to `6` seconds of speech.
- Steady-state chunk target duration: approximately `8` to `12` seconds of speech.
- Initial planning targets must prioritize semantic boundaries over maximum chunk size.
- Initial `v1` heuristics use a soft target of `35` to `55` words per steady-state chunk and a hard cap of `75` words before fallback splitting is required.

## Boundary Priority Order

Chunks must prefer to end at:

1. paragraph boundaries
2. sentence boundaries
3. clause punctuation boundaries
4. token boundaries

## Required Planning Algorithm

### Normal Case

- Start at `startSegmentId`.
- Pack whole ordered segments until the first strong boundary that satisfies the current target window.
- Emit a chunk only from ordered normalized segment text.
- Never reorder segments.

### Oversize Segment Fallback

If a single segment is too large for the target window:

- first split by sentence boundary if available
- then split by clause punctuation such as comma, semicolon, colon, or dash
- finally split by token boundary as a last resort

If a fallback split produces two partial segments, the planner must assign derived ids using:

- `{originalSegmentId}_part_{n}`

### Forbidden Shortcut

- Raw fixed-width character slicing must not be the primary chunking strategy.

## Context Rule

- Spoken chunk text must be exactly the text intended for audio output.
- Hidden context prefixes or suffixes are not part of the initial implementation unless the speech engine supports non-spoken conditioning explicitly.
- Until such support exists, chunk quality must come from semantic boundary choice rather than silent overlap text.

## Cache Key Rule

The planner must compute a stable cache key from:

- engine id
- engine version
- voice id
- rate
- normalization version
- normalized `speakText`

`cacheKey` format for `v1`:

- `{engineId}:{engineVersion}:{voiceId}:{rate.toStringAsFixed(2)}:{normalizationVersion}:{sha256(speakText)}`

## Constraints

- Planning must remain deterministic for the same input payload.
- Planner output must remain restartable from any valid `startSegmentId`.
- The planner must not use raw fixed-width character slicing as its normal strategy.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance Criteria

- The planner can describe every chunk in terms of ordered `segmentIds`.
- The planner can restart from an arbitrary `startSegmentId`.
- The planner never requires reconstructing structure from a monolithic flattened string.
