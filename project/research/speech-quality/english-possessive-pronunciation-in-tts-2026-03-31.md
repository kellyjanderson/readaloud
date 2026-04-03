# English Possessive Pronunciation in TTS — 2026-03-31

## Topic

Broad research on how English possessive forms should be pronounced, and how general TTS systems typically support or fail to support that behavior.

## Findings

### 1. The possessive `’s` uses the same allomorph system as plural `-s`

The broad linguistic picture is consistent:

- `/ɪz/` after sibilants
- `/s/` after voiceless non-sibilants
- `/z/` otherwise

This is not a special rule for names. It is the same phonological system used by:

- plural noun endings
- third person singular present tense endings
- the genitive/possessive ending

One accessible phonetics source states the rule explicitly and notes that it applies to the plural, third person singular, and genitive endings together.

Another summary source on English possessive states that the possessive is pronounced the same way as the plural ending and gives the same `/ɪz/`, `/s/`, `/z/` distribution.

### 2. Productive possessive handling belongs in the front end, not in a giant static lexicon

Vendor and standards documentation consistently describe lexicons and custom pronunciations as mappings for words or short phrases, not as a productive morphology engine.

- W3C PLS defines pronunciation lexicons as mappings between words or short phrases and pronunciations.
- Amazon Polly lexicons are described as a way to customize the pronunciation of words.
- Google Cloud custom pronunciations require an exact phrase match in the input.
- Azure supports inline phoneme markup for single entities and custom lexicons for multiple entities.

This is useful for:

- names
- acronyms
- unusual terms
- known irregular cases

It is not, by itself, the right core mechanism for productive suffix behavior like English possessive allomorphy.

### 3. Traditional TTS front ends treat this as text normalization / linguistic front-end work

MaryTTS’s architecture description places structure, number meaning, and linguistic interpretation in the front end before signal generation.

That matches the broader TTS architecture pattern:

- text normalization
- pronunciation / lexical stress / phonetic transcription
- sentence structure and prosody
- acoustic generation

The implication is that productive English suffix rules should be handled in the linguistic front end or G2P layer, not improvised late in synthesis.

### 4. Phrase-level custom pronunciation features are helpful but not sufficient

Google Cloud’s custom pronunciations are exact-phrase based. Azure and SSML phoneme tags allow direct control for individual entities. PLS lexicons and Polly lexicons support word/phrase mappings.

These are useful escape hatches, but they are still not a full replacement for:

- morphological analysis
- part-of-speech or syntactic disambiguation
- suffix allomorph realization

For a system like `Read Aloud`, this suggests:

- planner-owned general rules for productive morphology
- lexicon/custom-pronunciation support for irregulars and named entities
- engine-specific pronunciation injection only as an adapter layer

### 5. The current remaining problem is likely not the rule itself, but how the engine receives it

Given the research and the app’s behavior:

- our current planner can select the right possessive allomorph class
- but a spoken-text approximation like `Johnz` or `Someonez` may still not reliably force the desired voiced realization in the engine

That points to a likely implementation gap:

- the planner is choosing a better linguistic representation
- but the engine translation layer may still need a more explicit pronunciation-expression mechanism than approximate orthography

## Implications

### Short-term

Do not keep adding name-specific possessive rules.

The correct structure is:

- one general English `s`-allomorph rule
- separate contraction handling
- separate named-entity/base-word lexicon support

### Medium-term

The likely next technical step is not more document-time text rewriting.

The likely next step is:

- preserve the planner’s suffix/allomorph decision as an explicit TTS artifact
- make the engine adapter express that decision more directly if the engine supports it

That could mean:

- phrase-level pronunciation injection
- token-level phoneme injection
- engine lexicon augmentation

depending on the control surface available on the active engine path

### Architectural implication

This reinforces the current architecture direction:

- productive morphology belongs in pronunciation planning / realization
- lexicons are supporting resources, not the whole strategy
- engine adapters should consume explicit planner output instead of reconstructing suffix behavior from raw text

## References

- W3C Pronunciation Lexicon Specification (PLS) 1.0  
  https://www.w3.org/TR/pronunciation-lexicon/

- Amazon Polly: Managing lexicons  
  https://docs.aws.amazon.com/polly/latest/dg/managing-lexicons.html

- Microsoft Azure Speech: Pronunciation with SSML  
  https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-synthesis-markup-pronunciation

- Google Cloud Text-to-Speech `SynthesisInput` reference  
  https://docs.cloud.google.com/text-to-speech/docs/reference/rest/v1/SynthesisInput

- Google Cloud Text-to-Speech `CustomPronunciationParams` reference  
  https://docs.cloud.google.com/text-to-speech/docs/reference/rest/Shared.Types/CustomPronunciationParams

- MaryTTS Architecture Walkthrough  
  https://marytts.github.io/documentation/module-architecture.html

- An Introduction to American English Phonetics: “The plural, third person singular, and genitive endings”  
  https://opentextbooks.rug.nl/americanenglishphonetics2/chapter/2-1-the-plural-third-person-singular-and-genitive-endings/

- English possessive overview and references to Oxford/Cambridge grammars  
  https://en.wikipedia.org/wiki/English_possessive
