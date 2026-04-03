# PositionMap Granularity and Anchor Model — 2026-03-30

Last updated: March 30, 2026
Status: Active research notes

## Topic

This document answers the architecture question: what is the minimum useful `PositionMap` for `Read Aloud` that is stable enough for highlighting and progress mapping without becoming too expensive to build?

## Findings

### 1. Prior art favors hybrid anchors, not a single locator type

The W3C Web Annotation model distinguishes:

- `TextPositionSelector`
  - offset-based start and end positions
- `TextQuoteSelector`
  - exact text plus optional prefix and suffix context
- `RangeSelector`
  - composed start and end selectors for a range

This is a strong clue for `Read Aloud`:

- offsets are efficient
- quote-based anchors are resilient when offsets shift
- paired anchors are more robust than either one alone

### 2. EPUB prior art supports preserving source-native anchors when they are cheap to carry

EPUB already has stable structural location ideas:

- navigation documents
- page-list
- landmarks
- EPUB CFI as a location expression mechanism

Inference for `Read Aloud`:

- when source-native anchors are available and cheap to preserve, we should keep them as optional source anchors
- they should complement, not replace, our normalized display/speech mapping

### 3. The minimum useful mapping unit is block-to-segment plus offsets

For the app’s actual needs, we do not need a full DOM-range engine as the base representation.

The smallest mapping that still supports future highlighting and jump behavior is:

- display block id
- block-local normalized text offsets
- speech segment id
- speech-segment-local word or character offsets
- optional quote anchor for recovery
- optional source-native anchor

This is enough for:

- mapping playback back into visible content
- identifying the current displayed block
- eventually highlighting the spoken range
- resuming from a stable content anchor

### 4. PDFs need page-aware anchors, not just text offsets

PDF extraction is more brittle than EPUB or HTML.

The research on PDF text extraction emphasizes that reading order can be wrong, especially in complex layouts and multi-column documents.

Inference for `Read Aloud`:

- PDF position mapping should preserve page identity
- it should also preserve a normalized text anchor inside that page or extracted block
- the mapping should never rely only on global flat-text offsets for PDFs

### 5. Quote anchors are the right recovery mechanism for lossy imports

When import is lossy or later normalization changes offsets, the best lightweight recovery mechanism is the same one the Web Annotation model uses:

- exact text
- prefix
- suffix

Inference for `Read Aloud`:

- `PositionMap` entries should include a normalized quote anchor for important ranges
- this matters most for resume, highlighting recovery, and importer revisions

## Working Answer

The minimum useful `PositionMap` for `Read Aloud` should be a hybrid map with:

### Required Fields

- `documentId`
- `displayBlockId`
- `speechSegmentId`
- `displayStart`
- `displayEnd`
- `speechStartWord`
- `speechEndWord`

### Strongly Recommended Fields

- normalized `exact` text
- `prefix`
- `suffix`
- block type
- confidence score

### Optional Source-Specific Fields

- EPUB CFI or equivalent source anchor
- PDF page index plus source-block identifier
- source-parser location metadata when available

### Granularity Rule

Build the map at the range level, usually one or more speech segments to one visible display block or subrange. Do not try to store a full global per-character cross-product map.

## Implications

### Architecture Implications

- the `PositionMap` should be its own first-class data structure
- mapping is an anchor set, not a derived afterthought

### Specification Implications

Future specs should define:

- normalized offset semantics
- quote-anchor normalization rules
- PDF page/block anchor format
- EPUB source-anchor format
- recovery behavior when source and normalized positions disagree

### Implementation Implications

- build mapping during normalization, not later from flat strings
- use offsets for speed and quote anchors for resilience
- prefer block-level mapping plus subrange offsets over global character coordinates

## References

- W3C Web Annotation Data Model: https://www.w3.org/TR/annotation-model/
- EPUB 3.3: https://www.w3.org/TR/epub-33/
- EPUB Canonical Fragment Identifier 1.1: https://idpf.org/epub/linking/cfi/epub-cfi.html
- Improving the Extraction of Text in PDFs by Simulating the Human Reading Order: https://www.jucs.org/jucs_18_5/improving_the_extraction_of/jucs_18_05_0623_0649_hasan.pdf
