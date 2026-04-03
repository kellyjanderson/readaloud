# Speech Document

Last updated: March 30, 2026
Status: Final specification

## Scope

This specification defines the speech-side normalized document structure consumed by chunk planning, playback progress mapping, and future highlighting.

## Backlink

Parent specification:

- [Normalized Document Model](normalized-document-model.md)

## Purpose

`SpeechDocument` is the canonical speech contract. No new playback code should depend on a monolithic flattened string as its primary input.

## Required Dart Types

### SpeechDocument

`SpeechDocument` must contain:

- `String documentId`
- `String sourceType`
- `String languageTag`
- `List<SpeechSegment> segments`
- `Map<String, int> segmentIndexById`
- `int totalWordCount`
- `String normalizationVersion`

`documentId` must match the paired `DisplayDocument.documentId`.

### SpeechSegment

Every `SpeechSegment` must contain:

- `String segmentId`
- `String blockId`
- `int ordinal`
- `int paragraphIndex`
- `int sentenceIndex`
- `String normalizedText`
- `int wordCount`
- `SourceRange? sourceRange`
- `DisplayAnchor? displayAnchor`
- `List<SpeechWordSpan> wordSpans`

`segmentId` format for `v1`:

- `s_{ordinal}`

### SourceRange

When present, `SourceRange` must contain:

- `int startOffset`
- `int endOffset`
- `String coordinateSpace`

### DisplayAnchor

When present, `DisplayAnchor` must contain:

- `String blockId`
- `int startInlineOffset`
- `int endInlineOffset`

`DisplayAnchor` is an optional convenience hint only. `PositionMap` remains the authoritative cross-domain mapping structure.

### SpeechWordSpan

Every `SpeechWordSpan` must contain:

- `int wordIndexWithinSegment`
- `int startUtf16`
- `int endUtf16`
- `String text`

## Normalization Rules

- Leading and trailing whitespace must be trimmed.
- Internal whitespace runs must collapse to a single space unless a line break carries explicit speech meaning.
- Punctuation that affects pronunciation or cadence must be preserved.
- Empty segments are not allowed.
- Decorative content with no speech value must not become segments.

## Segment Boundary Rules

- The default segment unit is a sentence.
- A paragraph containing multiple sentences may emit multiple ordered segments.
- A heading may emit its own speech segment.
- A single segment may span less than a full sentence only when importer output already lacks reliable sentence boundaries or later planner fallback rules require further splitting.

## Inclusion Rules

- Visible body text becomes speech segments.
- Heading text becomes speech segments.
- List item text becomes speech segments in reading order.
- Captions become speech segments when present.
- Explicit textual alternatives may become speech segments when directly attached to rendered content.

## Exclusion Rules

- Purely decorative images do not create speech segments.
- Raw URLs do not become standalone speech segments unless they are visible body content.
- Navigation scaffolding, hidden HTML, scripts, and styles never become speech segments.
- Generated media descriptions are out of scope for `v1`.

## Mapping Rules

- `blockId` must reference a block in the paired `DisplayDocument`.
- `displayAnchor` must point to the block and offset range that best corresponds to the segment when such mapping is known.
- `PositionMap` remains authoritative if a convenience `displayAnchor` and `PositionMap` ever disagree.
- `segmentId` values must be deterministic from normalized order, not random runtime ids.
- `ordinal` values must be contiguous in reading order.
- `wordCount` must equal `wordSpans.length`.

## Constraints

- `SpeechDocument` must remain engine-agnostic.
- It must not contain final engine-specific phoneme output.
- It must preserve enough word-level structure for timing and future highlighting.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance Criteria

- Chunk planning can operate over `List<SpeechSegment>` without needing to recover structure from plain text.
- A future highlighter can map progress to a `segmentId` and word span without reparsing segment text.
