# Spoken Text Highlighting and Follow-Along Sync — 2026-04-03

## Topic

Research on how `Read Aloud` should advance visible reading position and highlight the text currently being spoken.

## Findings

### 1. The current system already has most of the hard data needed for highlighting

The codebase already contains the two critical halves of a follow-along system:

- runtime progress events that identify the active spoken word range
- normalized display/speech mapping that can relate speech progress back to visible content

Today, `TtsProgressUpdate` already carries:

- `segmentId`
- `wordStartIndex`
- `wordEndIndex`
- `startOffset`
- `endOffset`

And the normalized document model already carries:

- `SpeechSegment.wordSpans`
- `SpeechSegment.displayAnchor`
- `PositionMap`
- `DisplayDocument` block identity

That means the missing feature is not “how do we get timing.” It is “how do we derive stable reader-surface highlight state from the timing we already have.”

### 2. Highlighting should be derived from normalized mappings, not from HTML substring search

The app currently still exposes compatibility surfaces such as `displayHtml` and flattened `speakableText`, but those are the wrong foundation for robust follow-along rendering.

Highlighting should be mapped from:

- normalized speech progress
- normalized segment identity
- display block offsets and anchors

It should not depend on:

- reparsing generated HTML
- substring searching the flattened reader text
- guessing visual position from PCM timing alone

### 3. The feature actually contains three different problems that should stay separate

To keep the implementation clean, the app should distinguish:

1. spoken-range derivation  
   What speech span is active right now?

2. visible highlight selection  
   Which display block or inline range should be painted as active?

3. reading-focus movement  
   When should the viewport move, and how aggressively should it follow playback?

Those problems are related, but not identical.

### 4. Word-level precision should be preferred, but the system needs graceful fallbacks

The app already has the prerequisites for word-level highlighting on the main Kokoro path, but a durable architecture should support degraded modes:

- exact current-word highlight when segment/word mapping is available
- segment-range highlight when only segment confidence is high
- block-level focus when word-level mapping is missing or uncertain

This keeps highlighting available even when a source format or engine path is lower-fidelity.

### 5. Auto-follow should not recenter the viewport on every spoken word

A good reading experience is not the same thing as maximum positional accuracy.

The system should separate:

- highlight updates, which can be frequent
- viewport motion, which should be throttled and stateful

The viewport should:

- follow the active region with sentence or block awareness
- avoid jitter from per-word recenters
- temporarily yield when the user manually scrolls
- resume follow mode only when playback or the user explicitly asks for re-centering

### 6. Progress mapping is already designed to support this feature

The current `Playback Progress and Jump Mapping` specification already says progress payloads must be sufficient for future highlighting.

So this feature is aligned with the current architecture rather than requiring a reversal of earlier design decisions.

## Decision

Implement follow-along reading as a normalized-content feature built on top of existing progress events and mapping models, with separate contracts for:

- spoken-range state
- visible highlight state
- viewport follow policy

## Architectural Direction

The implementation should introduce:

- a controller-owned spoken selection model derived from progress updates
- a progress-to-display mapper that resolves normalized word ranges to visible ranges
- a reader-surface highlight painter
- a viewport-follow policy that is distinct from highlight updates

## Implementation Notes

This research points toward:

- a `SpokenTextSelection` or equivalent derived state object
- word-to-display resolution through `SpeechSegment.wordSpans`, `DisplayAnchor`, and `PositionMap`
- a UI fallback ladder from word to segment to block focus
- scroll-follow semantics that pause when the user takes control of the viewport

## References

- Current app implementation and specifications:
  - `lib/src/services/tts_engine.dart`
  - `lib/src/services/kokoro_tts_engine.dart`
  - `lib/src/models/speech_document.dart`
  - `lib/src/models/reader_document.dart`
  - `project/specifications/playback-progress-and-jump-mapping.md`
  - `project/specifications/position-map.md`
