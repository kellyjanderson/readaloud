# High-Quality TTS and Narration Gap — 2026-03-30

Last updated: March 30, 2026
Status: Active research notes

## Topic

This document records research on what is required to move from merely good speech synthesis to speech that sounds polished, natural, and closer to an audiobook narrator.

The specific focus is:

- eliminating awkward end-of-sentence pause behavior
- improving inflection and expressiveness
- understanding what separates well-formed TTS from coherent long-form narration

## Findings

### 1. The remaining gap is mostly prosody, not basic intelligibility

Once a TTS system already has good timbre and clear pronunciation, the remaining artifacts are mostly prosodic:

- pauses that are too long, too short, or placed incorrectly
- flat or averaged intonation
- weak emphasis
- sentence-by-sentence style drift
- loss of coherence across paragraphs

This pattern is visible across both standards and research papers.

- SSML 1.1 explicitly centers paragraph structure, sentence structure, breaks, prosody, marks, and phoneme control as the levers that shape natural spoken output.
- FastSpeech 2 treats duration, pitch, and energy as explicit variation information rather than leaving all variation implicit.

The practical implication is that “good audio quality” and “good narration quality” are not the same problem.

### 2. Overlong sentence-end pauses are a phrasing problem first, and a silence-policy problem second

Pause length is not just punctuation rendering.

- PauseSpeech argues that natural speech requires a phrasing structure that groups words into phrases based on semantic information, and predicts a pause sequence that separates text into phrases.
- The duration-aware pause insertion paper explicitly frames pause insertion and phrase break prediction as essential to rhythm and intelligibility, and argues for predicting both pause placement and pause duration.

There is also useful evidence on what listeners actually notice.

- Google’s 2024 study on inter-sentence pauses in long-form American English found that raters are not very sensitive to pause-length variation unless it deviates strongly from what the speech context makes them expect.

My inference from those sources is:

- we do not need pause timing to be mathematically perfect
- we do need pause classes that are contextually appropriate
- we should not allow model output plus application behavior to accidentally stack into exaggerated silence

For a chunked app like `Read Aloud`, this strongly suggests a two-layer solution:

- linguistic pause prediction before synthesis
- bounded silence trimming and pause policy after synthesis

### 3. Inflection comes from explicit prosody modeling, not from punctuation alone

“Inflection” in this context is mostly about prosody:

- where pitch rises and falls
- where energy increases or softens
- where durations stretch or compress
- where emphasis lands

FastSpeech 2 is useful prior art here because it explicitly models:

- duration
- pitch
- energy

instead of treating them as hidden side effects of text alone.

Related Google work on prosody also reinforces that:

- style tokens can capture expressive variation
- fine-grained prosody priors improve naturalness
- BERT-based text context improves prosody because text alone, or text plus shallow linguistic features, leaves prosody underdetermined

The practical implication is that punctuation is necessary, but not sufficient.

To get beyond “reads correctly” and into “sounds intentionally performed,” the system needs a prosody layer that can represent and carry more than plain text boundaries.

### 4. The audiobook narrator gap is mostly a long-form context problem

Several audiobook-focused papers point in the same direction.

- Context-aware Coherent Speaking Style Prediction for Audiobook Speech Synthesis says the hard problem is generating contextually appropriate and coherent speaking style for multi-sentence text, and uses both text-side context and prior speech-side style information.
- Improving Speech Prosody of Audiobook TTS with Acoustic and Textual Contexts says preceding acoustic context plus bilateral textual context materially improves prosody.
- Text-aware and Context-aware Expressive Audiobook Speech Synthesis says the remaining challenge is capturing diverse narrator styles and coherent prosody without requiring manually labeled reference speech.

There is also a useful evaluation lesson here.

- Google’s long-form TTS evaluation paper found that evaluating sentences in isolation is not enough, and that sentence-level ratings do not reliably match paragraph-level judgments.

This means audiobook quality is not just “better per-sentence synthesis.”

It requires:

- coherence across sentences
- stability of style across paragraphs
- memory of what just happened acoustically
- adaptation to discourse and narrative context

### 5. Long-form narration needs style memory, not just per-utterance style control

Global Style Tokens are important prior art because they show that expressive style can be modeled as a reusable latent representation and transferred across text.

That is useful, but audiobook papers go further:

- style needs to remain coherent over time
- style should respond to both current text and previous context
- sentence-by-sentence generation must not reset the speaking style every time

My inference is that a production narration system needs some form of persistent narration state, even if it is simple at first.

That state might include:

- current style embedding
- current prosody trend
- recent pause behavior
- recent pitch/energy statistics
- current paragraph or section mode

Without that, even a strong single-sentence model tends to sound locally good but globally inconsistent.

### 6. Text-side semantics matter more than raw punctuation

Pause and emphasis decisions are driven partly by syntax and semantics, not only punctuation marks.

- PauseSpeech uses a pre-trained language model for phrasing.
- The duration-aware pause insertion paper uses BERT for pause insertion and duration prediction.
- Google’s BERT prosody paper says prosody is unnatural when the model only has text or only shallow linguistic enrichment, and improves when a pretrained language model is incorporated.

This is strong evidence that the front end should not stop at:

- sentence splitting
- word splitting
- punctuation preservation

It should also try to infer:

- clause boundaries
- likely phrase groups
- emphasis candidates
- dialogue or quotation context

### 7. Prior art also supports explicit alignment and timing hooks

OS and browser APIs support the idea that speech can expose timing and range information back to the app.

- MDN’s `SpeechSynthesisUtterance` exposes `boundary` and `mark` events.
- Android’s `UtteranceProgressListener` can expose text ranges and frame offsets, and the docs explicitly call out highlighting as a use case.
- Android’s `TtsSpan` is prior art for attaching speech-specific semantic metadata to text when plain text is not enough.

This matters because it reinforces that:

- speech-side enrichment is normal
- progress-to-text mapping is normal
- future highlighting and timing-aware jumping are compatible with established TTS design patterns

## Implications

### Product Implications

From a product standpoint, “audiobook narrator quality” should be treated as a different bar from “good speech.”

The system should aim for these product qualities:

- no obviously awkward pauses
- no repetitive sentence-reset feel
- enough expressive variation to avoid monotony
- stable narrative style over longer spans of reading

### Architecture Implications

The research suggests the internal speech model should eventually represent more than normalized text.

Likely required speech-side concepts:

- pause class
- pause duration hint or pause strength
- emphasis hint
- pronunciation override
- prosody/style state
- alignment marks for progress mapping

That does not mean all of these need to be implemented immediately, but the architecture should leave room for them.

### Chunking Implications

Chunking for high-quality speech should follow this order of thought:

1. preserve sentence and phrase boundaries
2. preserve contextual continuity between adjacent chunks
3. avoid double-counting pauses at chunk joins
4. trim or cap pathological leading/trailing silence

The research strongly argues against naive chunk joins where:

- one chunk ends with model-generated long silence
- the next chunk begins with another leading pause
- the app adds an additional queue or playback gap on top

### Evaluation Implications

If we care about narration quality, we should not evaluate only:

- isolated sentences
- one-off short samples

We should also evaluate:

- whole paragraphs
- transitions across chunk boundaries
- paragraph-to-paragraph style continuity
- pause naturalness in context

### Likely Smallest Useful New Architectural Unit

The smallest additional unit that seems justified by this research is not a new renderer or a new vocoder.

It is a speech annotation layer on top of `SpeechDocument`.

That annotation layer would allow the app to represent:

- inferred phrase boundaries
- break strength
- emphasis candidates
- pronunciation corrections
- future style and narration hints

## Working Conclusion

To bridge the gap between well-formed TTS and audiobook-like narration, the system needs more than accurate text normalization and a good voice model.

It needs:

- phrase-aware pause prediction
- explicit duration, pitch, and energy control or modeling
- long-form contextual coherence across sentences and paragraphs
- persistent style or narration state
- bounded silence policy at synthesis boundaries
- evaluation in paragraph context, not only sentence isolation

The simplest useful mental model is:

- intelligible speech comes from text normalization and pronunciation
- natural speech comes from prosody
- narrator-like speech comes from prosody plus long-form context plus stable style memory

## References

- SSML 1.1: https://www.w3.org/TR/speech-synthesis11/
- MDN `SpeechSynthesisUtterance`: https://developer.mozilla.org/en-US/docs/Web/API/SpeechSynthesisUtterance
- Android `UtteranceProgressListener`: https://developer.android.com/reference/android/speech/tts/UtteranceProgressListener
- Android `TtsSpan`: https://developer.android.com/reference/android/text/style/TtsSpan
- FastSpeech 2: https://arxiv.org/abs/2006.04558
- PauseSpeech: https://arxiv.org/abs/2306.07489
- Duration-aware pause insertion: https://arxiv.org/abs/2302.13652
- Global Style Tokens: https://research.google/pubs/style-tokens-unsupervised-style-modeling-control-and-transfer-in-end-to-end-speech-synthesis/
- Improving Prosody with BERT: https://research.google/pubs/improving-prosody-of-rnn-based-english-text-to-speech-synthesis-by-incorporating-a-bert-model/
- Inter-sentence Pause Sensitivity: https://research.google/pubs/a-study-of-raters-sensitivity-to-inter-sentence-pause-durations-in-american-english-speech/
- Evaluating Long-form TTS: https://research.google/pubs/evaluating-long-form-text-to-speech-comparing-the-ratings-of-sentences-and-paragraphs/
- Context-aware Coherent Speaking Style Prediction for Audiobooks: https://arxiv.org/abs/2304.06359
- Improving Audiobook Prosody with Acoustic and Textual Contexts: https://arxiv.org/abs/2211.02336
- Text-aware and Context-aware Expressive Audiobook Speech Synthesis: https://arxiv.org/abs/2406.05672
