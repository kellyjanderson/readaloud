# PositionMap

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the normalized mapping contract between display content and speech content.

## Backlink

Parent architecture:

- [Normalized Content and Position Mapping](../architecture/normalized-content-and-position-mapping.md)

## Scope

This specification covers:

- `PositionMap`
- `PositionMapEntry`
- recovery anchors
- optional source-native anchors
- the minimum mapping granularity required for progress, resume, and future highlighting

This specification does not define playback timing or jump estimation logic.

## Behavior

### Required Types

`PositionMap` must contain:

- `String documentId`
- `String mappingVersion`
- `List<PositionMapEntry> entries`

Every `PositionMapEntry` must contain:

- `String entryId`
- `String displayBlockId`
- `String speechSegmentId`
- `int displayStart`
- `int displayEnd`
- `int speechStartWord`
- `int speechEndWord`
- `double confidence`

### Offset Semantics

- `displayStart` is inclusive.
- `displayEnd` is exclusive.
- `speechStartWord` is inclusive.
- `speechEndWord` is exclusive.
- Offsets refer to normalized block and segment text, not raw source bytes.

### Recovery Anchor

Every `PositionMapEntry` should include a recovery anchor with:

- `String exact`
- `String? prefix`
- `String? suffix`

`exact` must be normalized text matching the mapped speech range.

### Source-Native Anchors

`PositionMapEntry` may include one source-native anchor when available:

- `EpubSourceAnchor`
- `PdfSourceAnchor`
- `HtmlSourceAnchor`

`PdfSourceAnchor` should preserve:

- `int pageIndex`
- `String? sourceBlockId`

`EpubSourceAnchor` should preserve:

- `String? spineItemId`
- `String? cfi`

### Granularity Rule

The default mapping unit is a display block subrange to one speech segment or contiguous speech-segment span.

The system must not require a full global per-character map across the entire document.

### Ordering Rule

- Entries must be ordered by display reading order.
- Entries must also be monotonic in speech order.
- If a source format forces lossy or uncertain mapping, the entry must still exist with reduced `confidence` and matching diagnostics.

### Recovery Rule

When exact offsets no longer resolve after internal revision:

1. try the normalized recovery anchor
2. try the source-native anchor if present
3. surface a mapping-confidence downgrade

## Constraints

- `PositionMap` must be built during normalization, not reconstructed later from flat strings.
- PDFs must preserve page-aware anchors.
- Mapping data must remain engine-agnostic.
- A `PositionMap` entry must never point to ids outside the paired `DisplayDocument` and `SpeechDocument`.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Importers can emit a `PositionMap` without relying on legacy `speakableText`.
- Playback progress can resolve from speech segment id to visible display block range.
- The mapping model supports offset-based lookup and quote-anchor recovery.
- PDF imports preserve page-aware mapping data.
