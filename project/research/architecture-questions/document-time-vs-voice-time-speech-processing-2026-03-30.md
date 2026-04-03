# Document-Time vs Voice-Time Speech Processing — 2026-03-30

Last updated: March 30, 2026
Status: Active research notes

## Topic

This document answers three related architecture questions:

- what speech processing is safe to do once at document-ingestion time
- what must be recomputed per voice, rate, or playback session
- how much preprocessing can happen proactively without making the app feel slow

It also covers the related question of which normalization heuristics are reliable enough for plain-text, PDF, and DOCX import.

## Findings

### 1. The best document-time work is structural, linguistic-light, and reusable

The strongest candidates for document-time processing are the parts that do not depend on a selected voice or current playback state.

Good document-time work:

- reading-order recovery
- block and paragraph detection
- sentence segmentation
- tokenization and word-boundary indexing
- heading, list, table, and quote detection
- normalization of whitespace, line wraps, and repeated layout artifacts
- detection of semiotic classes such as numbers, dates, times, currency, ordinals, and abbreviations
- candidate phrase-boundary and pause-boundary inference
- importer diagnostics and confidence scoring
- display-to-speech mapping

This lines up with Unicode text-boundary prior art:

- UAX #29 defines default word and sentence boundary rules
- ICU exposes those boundaries through `BreakIterator` and explicitly supports sentence-break filters

It also lines up with EPUB and PDF realities:

- EPUB provides structural reading-order and navigation information
- PDF extraction research consistently treats reading order and paragraph reconstruction as separate problems from later speech realization

Inference for `Read Aloud`:

- document-time processing should produce a normalized structural base that later voice/session layers consume
- that base should be cacheable with the imported document

### 2. Voice-time work should be limited to realization, not rediscovery

The parts that should remain voice-time or session-time are the ones that genuinely depend on accent, rate, selected voice, or immediately surrounding narration context.

These include:

- final grapheme-to-phoneme conversion when accent or voice family matters
- pronunciation override selection when multiple pronunciations are valid
- realization of pause strength into chunk boundaries and join policy
- realization of emphasis candidates
- chunk sizing for the active voice and rate
- nearby look-ahead around the current playback position
- session-local narration continuity

The important distinction is:

- document-time decides what the text likely means structurally
- voice-time decides how that meaning should be realized for the active voice

Inference for `Read Aloud`:

- voice changes should not force us to recompute the full document structure
- they should trigger only the realization pass for the relevant upcoming window

### 3. Final phoneme strings are not safely document-time for English voices

Kokoro uses Misaki as its G2P layer, and Misaki’s English configuration distinguishes American and British behavior. Misaki also explicitly supports fallback behavior and notes unresolved homograph work as future or advanced work.

That makes final phoneme output a poor candidate for a single document-wide cache when the same text may later be read by:

- American versus British voices
- different pronunciation override policies
- future improved G2P logic

Inference for `Read Aloud`:

- cache pronunciation candidates and the text spans they apply to at document time
- generate finalized phoneme strings at voice/session time
- keep the phoneme cache windowed to the upcoming playback region rather than the entire document

### 4. PDF and DOCX normalization should be heuristic, not aspirational

The research does not support pretending that PDFs and DOCX files carry reliable speech structure by default.

What is safe:

- preserve extracted reading order if the source already provides strong order signals
- merge visual line breaks inside a paragraph when the evidence suggests the break is layout-driven
- keep blank-line paragraph breaks
- preserve list markers, headings, tables, and figure captions as separate structural units
- detect multi-column and likely broken-order extraction as diagnostics

What is risky:

- inventing clause structure from visual line breaks alone
- trusting PDF line order when extraction already looks disordered
- aggressively flattening headings, bullets, and captions into surrounding prose

Inference for `Read Aloud`:

- normalization should be conservative and diagnostics-aware
- phrase inference should happen after paragraph and sentence recovery, not directly from raw extracted lines

### 5. The most predictive text features for phrasing and emphasis are above punctuation alone

The prosody literature and TTS front-end prior art point in the same direction: punctuation is necessary but not sufficient.

The most useful features appear to be:

- sentence boundaries
- clause boundaries
- quote and dialogue markers
- headings and section transitions
- list structure
- parentheticals and appositives
- discourse markers such as “however”, “therefore”, and “meanwhile”
- semiotic classes such as dates, times, numbers, acronyms, and measurements
- ambiguous-word or homograph candidates

Inference for `Read Aloud`:

- document-time enrichment should carry these as annotations or candidates
- voice-time realization should decide how strongly to realize them

### 6. On older hardware, the open path should stay rule-based and linear

The app needs to feel responsive on a 2017 Intel MacBook Pro, and later on mobile devices.

That rules out doing heavy ML inference on the document-open path for every import.

The source material supports a layered strategy:

- use rule-based sentence and word boundaries first
- use format structure and lightweight heuristics for headings, lists, and line-wrap repair
- defer heavier work to background processing or the play path only where it materially changes output

Inference for `Read Aloud`:

- document open should perform only the reusable structural pass plus light annotation inference
- deeper enrichment can continue in the background after the document is already viewable
- voice selection should never block on whole-document reprocessing

## Working Answer

The best split for `Read Aloud` is:

### Document-Time

- normalize source structure
- recover reading order
- build `DisplayDocument`, `SpeechDocument`, and `PositionMap`
- segment into paragraphs, sentences, and words
- infer structural annotation candidates
- classify semiotic spans
- attach importer diagnostics

### Voice-Time / Session-Time

- finalize G2P and accent-specific pronunciation
- realize pause and emphasis candidates for the selected voice and rate
- maintain light narration continuity
- plan chunks for the current playback window
- synthesize and cache audio

### Performance Rule

Do reusable structural work early, but keep the open path linear, rule-based, and diagnostics-driven. Do not run whole-document voice realization or heavy semantic inference before the user can start reading.

## Implications

### Architecture Implications

- the two-pass model in architecture is supported by the research
- `BaseSpeechAnnotationSet` should be document-time and cacheable
- voice/session realization should be windowed, not full-document

### Specification Implications

The future specs should separate:

- structural normalization
- base speech annotations
- voice realization
- session-local narration state

### Implementation Implications

- file open should complete after normalized structure is available, not after all speech enrichment finishes
- PDF and DOCX import should emit diagnostics when structure confidence is low
- voice switching should invalidate only future realization and chunk caches, not structural normalization

## References

- Unicode Text Segmentation (UAX #29): https://www.unicode.org/reports/tr29/
- ICU Boundary Analysis: https://unicode-org.github.io/icu/userguide/boundaryanalysis/
- EPUB 3.3: https://www.w3.org/TR/epub-33/
- Improving the Extraction of Text in PDFs by Simulating the Human Reading Order: https://www.jucs.org/jucs_18_5/improving_the_extraction_of/jucs_18_05_0623_0649_hasan.pdf
- kokoro README: https://github.com/hexgrad/kokoro
- misaki README: https://github.com/hexgrad/misaki
- Misaki English phoneme inventory: https://github.com/hexgrad/misaki/blob/main/EN_PHONES.md
- Homograph Disambiguation with Contextual Word Embeddings for TTS Systems: https://assets.amazon.science/c3/db/23ca18d7450d8dbb5b80a11fcdd3/homograph-disambiguation-with-contextual-word-embeddings-for-tts-systems.pdf
- PauseSpeech: https://arxiv.org/abs/2306.07489
- Duration-Aware Pause Insertion for Text-to-Speech Systems: https://arxiv.org/abs/2302.13652
