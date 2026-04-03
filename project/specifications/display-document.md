# Display Document

Last updated: March 30, 2026
Status: Final specification

## Scope

This specification defines the rendering-side normalized document structure consumed by the reader surface.

## Backlink

Parent specification:

- [Normalized Document Model](normalized-document-model.md)

## Purpose

`DisplayDocument` exists to preserve document structure for presentation without forcing playback code to depend on renderer-specific details.

## Required Dart Types

### DisplayDocument

`DisplayDocument` must contain:

- `String documentId`
- `String sourceType`
- `Uri? sourceUri`
- `String title`
- `List<DisplayBlock> blocks`
- `Map<String, DisplayAsset> assets`
- `Map<String, String> metadata`
- `String normalizationVersion`

`documentId` format for `v1`:

- `doc_{sha256(sourceType + ":" + canonicalSourceFingerprint).substring(0, 16)}`

### DisplayBlock

Every `DisplayBlock` must contain:

- `String blockId`
- `DisplayBlockKind kind`
- `List<DisplayInline> inlines`
- `Map<String, String> attributes`
- `String? assetId`
- `String? parentBlockId`
- `int ordinal`

Supported `DisplayBlockKind` values for `v1`:

- `heading`
- `paragraph`
- `orderedList`
- `unorderedList`
- `listItem`
- `blockquote`
- `codeBlock`
- `image`
- `audio`
- `video`
- `table`
- `pageBreak`
- `separator`
- `unsupported`

`blockId` format for `v1`:

- `b_{ordinal}`

### DisplayInline

Every `DisplayInline` must contain:

- `DisplayInlineKind kind`
- `String text`
- `Map<String, String> attributes`

Supported `DisplayInlineKind` values for `v1`:

- `text`
- `emphasis`
- `strong`
- `link`
- `inlineCode`
- `lineBreak`
- `superscript`
- `subscript`

### DisplayAsset

Every `DisplayAsset` must contain:

- `String assetId`
- `DisplayAssetKind kind`
- `Uri resolvedUri`
- `String? mimeType`
- `Map<String, String> metadata`

Supported `DisplayAssetKind` values for `v1`:

- `image`
- `audio`
- `video`
- `attachment`

`assetId` format for `v1`:

- `a_{ordinal}`

## Invariants

- `documentId` must match the paired `SpeechDocument.documentId`.
- `blockId` values must be unique within a document.
- `assetId` values must be unique within a document.
- `ordinal` values must be contiguous in reading order.
- `unsupported` blocks must preserve source placement even when content cannot be fully rendered.
- Inline text must remain in source order.

## Constraints

- `DisplayDocument` is renderer input, not renderer-owned state.
- Importers must not emit duplicate `blockId` or `assetId` values.
- The canonical display form must remain independent from any internal HTML conversion used by the reader surface.

## Rendering Contract

- The reader surface consumes `DisplayDocument`, not importer-specific raw HTML blobs.
- The renderer may convert `DisplayDocument` into HTML or widget structures internally, but that conversion is a presentation concern and must not become the canonical document form.
- Blocks with media assets must preserve enough metadata for future rich interaction even if `v1` renders them as placeholders.

## Importer Rules

- Importers must preserve headings, paragraph structure, list structure, and explicit media references when the source format exposes them.
- Importers may degrade unsupported structures into `unsupported` blocks, but they must not silently discard them without a diagnostic.
- Page boundaries discovered during PDF extraction must be represented as `pageBreak` blocks.

## Non-Goals

- This specification does not define how highlighting is painted.
- This specification does not require generated descriptions for non-text media.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Importers can emit a complete rendering-side normalized structure using `DisplayDocument`.
- Renderer-facing code can consume `DisplayDocument` without using importer-specific HTML blobs as canonical state.
- Media and unsupported structures preserve source placement and metadata well enough for later product expansion.
