# Normalized Content and Position Mapping

Last updated: March 31, 2026
Status: Active architecture

## Purpose

This document defines how imported content becomes stable internal content for both rendering and speech, and how positions are mapped between those domains.

## Overview

`Read Aloud` must support documents whose display structure and speech structure are related but not identical.

The architecture therefore requires three paired outputs from import and normalization:

- `DisplayDocument`
- `SpeechDocument`
- `PositionMap`

These outputs together form the normalized content layer.

## Components

### Source Artifact

The source artifact is the raw input:

- pasted text
- plain text file
- HTML
- EPUB
- PDF
- DOCX
- RTF

It is never the canonical runtime document model.

### DisplayDocument

`DisplayDocument` is the canonical display-side representation.

Responsibilities:

- preserve reading order for rendering
- preserve headings, paragraphs, lists, tables, and media references
- support future rich display behavior without depending on source-format-specific parsers at render time

### SpeechDocument

`SpeechDocument` is the canonical speech-side representation.

Responsibilities:

- preserve sentence-first speech segments
- preserve paragraph order
- preserve word spans and stable ids
- provide the input contract for speech enrichment and chunk planning

### PositionMap

`PositionMap` is the bridge between display and speech.

Responsibilities:

- map display blocks and offsets to speech segments and word ranges
- preserve a hybrid anchor model based on offsets plus recovery anchors
- preserve source-native anchors when they are cheap and useful
- map playback progress back into rendered content
- preserve enough information for future highlighting, jump behavior, and resume logic

### ImportDiagnostics

Diagnostics are part of normalized content, not an afterthought.

Responsibilities:

- record lossiness and unsupported content
- preserve importer decisions that may affect rendering or speech quality

## Relationships

- `DisplayDocument` and `SpeechDocument` share one `documentId`.
- `PositionMap` references ids from both sides; it is not an independent document tree.
- Speech-specific enrichment must attach to `SpeechDocument` and `PositionMap`, not mutate `DisplayDocument`.
- Rendering reads `DisplayDocument`.
- Playback reads `SpeechDocument`, later enriched by speech-side layers.

## Data Flow

```text
source artifact
  -> parser
  -> cleanup and normalization
  -> DisplayDocument
  -> SpeechDocument
  -> PositionMap
  -> rendering / speech enrichment
```

## Cross-Domain Solutions

### 1. One document, two canonical views

The architecture must not force display and speech into the same structure.

Reason:

- PDFs often preserve visible layout poorly for speech extraction
- EPUB and HTML may carry display structure that does not map one-to-one onto speakable units
- future speech annotations must not corrupt the display representation

### 2. Mapping is first-class, not reconstructed ad hoc

The system must not try to rediscover display-to-speech mapping later from raw strings.

Reason:

- highlighting must be stable
- jump behavior depends on stable word ranges
- source formats vary too much for reliable late reconstruction

### 3. Normalized content is immutable input to later layers

Later layers may enrich speech behavior, but they do so by attaching sidecar state, not by redefining the normalized source content in place.

Reason:

- rendering, speech enrichment, and playback need a common stable base
- diagnostics and mappings need to remain explainable

### 4. Position mapping is hybrid, not purely offset-based

The system must not depend on only one locator style for mapping.

Reason:

- offsets are efficient
- quote-style anchors are better recovery tools when normalization shifts content
- EPUB and PDF may provide source-native anchors worth preserving

### 5. PDFs require page-aware mapping

PDF position mapping must preserve page identity and extracted block identity where possible.

Reason:

- PDF reading order is more fragile than EPUB or HTML
- global flat offsets are not a reliable sole anchor for PDF-derived content

## Current Implementation Gap

The current codebase now implements the normalized layer directly, but still carries a smaller compatibility surface:

- normalized import results, display/speech documents, importer diagnostics, and hybrid `PositionMap` data are first-class outputs
- `ReaderDocument` still exposes compatibility views such as `displayHtml`, `speakableText`, and coarse word spans for current UI and export callers
- some importer and controller code still consumes those compatibility views directly even though the normalized models are the underlying source of truth
- richer source-native anchors remain uneven by format, especially around PDF and EPUB edge cases

## Governing Specifications

- [Normalized Document Model](../specifications/normalized-document-model.md)
- [Display Document](../specifications/display-document.md)
- [Speech Document](../specifications/speech-document.md)
- [Importer Normalization Contract](../specifications/importer-normalization-contract.md)
- [Import Diagnostics Taxonomy](../specifications/import-diagnostics-taxonomy.md)
- [Line Wrap and Paragraph Recovery](../specifications/line-wrap-and-paragraph-recovery.md)
- [PositionMap](../specifications/position-map.md)

## Change Log

- March 30, 2026
  Description: Added the normalized content and position-mapping architecture as a first-class architectural document.
  Reason: The product now requires an explicit explanation of how one document can support both rich display and high-quality speech with stable mapping between them.
  Feature branch: `main`
  PR reference: `not opened yet`
- March 30, 2026
  Description: Refined `PositionMap` into a hybrid anchor architecture using offsets, recovery anchors, and optional source-native anchors, with page-aware handling for PDFs.
  Reason: The research pass resolved the minimum useful mapping granularity and the need for resilience beyond raw offsets.
  Feature branch: `main`
  PR reference: `not opened yet`
