# Playback Progress and Jump Mapping

Last updated: March 30, 2026
Status: Final specification

## Scope

This specification defines how playback progress is recorded and how 30-second jumps map back into normalized speech content.

## Backlink

Parent specification:

- [Imported Document Playback](imported-document-playback.md)

## Required Runtime Record

The coordinator must maintain a `SpokenChunkRecord` for every completed or active chunk with:

- `String chunkId`
- `String documentId`
- `List<String> segmentIds`
- `int startWordIndex`
- `int endWordIndex`
- `int wordCount`
- `Duration audioDuration`
- `Duration playbackOffset`
- `String voiceId`
- `double rate`
- `bool completed`

## Progress Event Contract

Every progress event emitted toward the UI must include:

- `documentId`
- `chunkId`
- `segmentId`
- `wordStartIndex`
- `wordEndIndex`
- `elapsedInChunk`
- `voiceId`
- `rate`

## Timing Model

- The system maintains a rolling words-per-second estimate for the active `(voiceId, rate)` pair.
- The estimate is computed from completed chunk records.
- The initial fallback estimate before enough real data exists is `2.8` words per second.
- The rolling estimate uses a weighted moving average biased toward the most recent `5` completed chunks.

## Jump Algorithm

### Input

- current absolute word index
- desired jump delta in seconds
- active `(voiceId, rate)` timing estimate

### Output

- target absolute word index
- target `segmentId`
- restart position for chunk planning

### Required Steps

1. Convert the desired time delta into a word delta using the active words-per-second estimate.
2. Add or subtract that word delta from the current absolute word index.
3. Clamp the target index to the document word range.
4. Snap the result to the nearest valid segment boundary at or before the target index.
5. Request a new chunk plan beginning at that target segment.

If no completed chunk records exist yet:

- use the fallback words-per-second estimate
- still snap to the nearest valid segment boundary

## Highlighting Readiness

- The progress payload must already be sufficient for future word-level or segment-level highlighting.
- Future highlighting must not require reparsing cached audio text or reparsing raw importer output.

## Completion Rule

- When playback is completed, the current word index remains at the end-of-document position until the next `play` action resets it.

## Constraints

- Jump calculations must use the active `(voiceId, rate)` timing model.
- Progress payloads must remain sufficient for future highlighting.
- Mapping must resolve against normalized content, not importer raw text.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app can compute forward and backward 30-second jumps from chunk timing history.
- Progress events remain mappable to segment and word ranges.
- Completed-at-end behavior is compatible with replay-on-next-play semantics.
