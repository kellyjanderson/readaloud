# Long-Form TTS Evaluation and Instrumentation — 2026-03-30

Last updated: March 30, 2026
Status: Active research notes

## Topic

This document answers the architecture question: what evaluation method is realistic for `Read Aloud` if sentence-level quality scores are not enough?

## Findings

### 1. Sentence-level evaluation is not enough for this product

The long-form TTS evaluation literature is clear that sentence-level ratings do not reliably predict paragraph-level listener judgment.

That matters directly for `Read Aloud`, because the product experience is:

- multi-sentence
- chunked
- interruptible
- replayable
- sensitive to join artifacts and continuity

Inference for `Read Aloud`:

- our evaluation set has to include paragraphs and chunk transitions

### 2. The app needs both listening tests and product metrics

Research papers focus on subjective listening quality, but product work also needs operational instrumentation.

The most useful pairing is:

- listening-based quality review for naturalness and narration continuity
- runtime metrics for latency, cache behavior, and boundary corrections

### 3. A realistic listening suite should include targeted failure classes

The test corpus should not only contain “nice prose”.

It should include:

- dialogue and nested quotes
- headings and section transitions
- lists
- dates, times, numbers, and currency
- abbreviations and honorifics
- acronyms and initialisms
- parentheticals
- captions and figure references
- PDF-extracted prose with repaired line wraps

Inference for `Read Aloud`:

- we need a regression corpus designed to trigger our likely failures

### 4. Boundary evaluation deserves its own pass

Chunk joins are a product-specific quality problem.

They should be evaluated separately for:

- too much pause
- too little pause
- audible join clicks or cuts
- sentence-reset feel after the join

Inference for `Read Aloud`:

- add a boundary-focused listening pass, not just a whole-paragraph score

### 5. The right runtime metrics are about smoothness and continuity

The most useful product metrics appear to be:

- first-audio latency
- real-time factor for generated audio
- prefetch lead time
- chunk cache-hit rate
- boundary-correction count
- measured join silence before correction
- measured join silence after correction
- playback underrun count
- progress-map confidence and correction rate

These metrics let us see whether a change improved quality by:

- better chunking
- better caching
- better boundary policy
- better normalization

## Working Answer

The evaluation model for `Read Aloud` should have three layers:

### 1. Paragraph Listening Suite

Score:

- naturalness
- continuity
- pause appropriateness
- emphasis quality
- monotony versus expressiveness

### 2. Chunk-Boundary Listening Suite

Score:

- join audibility
- overlong pause
- under-pause
- sentence-reset artifact

### 3. Product Telemetry

Track:

- first-audio latency
- real-time factor
- cache-hit rate
- chunk regeneration rate
- boundary-correction metrics
- underruns
- progress-map quality

## Implications

### Architecture Implications

- observability is part of the architecture, not optional polish
- chunk metadata and boundary metadata need to survive long enough to be measured

### Specification Implications

Future specs should define:

- evaluation corpus shape
- scoring rubric
- runtime metric names and units
- thresholds for “good enough” playback smoothness

### Implementation Implications

- the app should log structured playback-generation metrics in debug builds
- the regression corpus should include imported-document cases, not just bundled sample text
- future pronunciation and boundary changes should be checked against the same suite

## References

- Evaluating Long-form Text-to-Speech: Comparing the Ratings of Sentences and Paragraphs: https://research.google/pubs/evaluating-long-form-text-to-speech-comparing-the-ratings-of-sentences-and-paragraphs/
- A Study of Raters’ Sensitivity to Inter-sentence Pause Durations in American English Speech: https://research.google/pubs/a-study-of-raters-sensitivity-to-inter-sentence-pause-durations-in-american-english-speech/
- Context-Aware Coherent Speaking Style Prediction for Audiobook Speech Synthesis: https://arxiv.org/abs/2304.06359
- Improving Speech Prosody of Audiobook TTS with Acoustic and Textual Contexts: https://arxiv.org/abs/2211.02336
- Text-aware and Context-aware Expressive Audiobook Speech Synthesis: https://arxiv.org/abs/2406.05672
