# English Pronunciation Dictionary Backstop and Special Cases — 2026-04-02

## Topic

Research on how to cover broad, well-documented English pronunciation special cases in `Read Aloud` without turning the live TTS path into an unbounded pile of one-off rules.

## Findings

### 1. A pronunciation dictionary is the right backbone for lexical English special cases

The user concern is broader than contractions. English has many lexicalized pronunciation forms that are not safely recoverable from spelling alone:

- contractions
- possessive pronouns and related lexical forms
- apostrophe-bearing forms
- irregular or non-transparent word pronunciations
- common abbreviations and special vocabulary

For that class of problem, the right supporting resource is a pronunciation dictionary rather than a growing hand-maintained exception list.

### 2. CMUdict is a practical source for the current app

The CMU Pronouncing Dictionary is an established American English pronunciation dictionary and is a good fit for the app’s current English-first path.

From the downloaded upstream dictionary now vendored into the app:

- the asset contains `135166` entries
- it includes many apostrophe-bearing and lexicalized forms
- local inspection of the downloaded source confirmed coverage for forms such as:
  - `can't`
  - `won't`
  - `it's`
  - `we're`
  - `they're`
  - `one's`
  - `dog's`
  - `dogs'`
  - `jenny's`

That makes it a strong backstop for the “special cases of the language” problem the user called out.

### 3. A broad dictionary still should not replace the whole planner

Using a dictionary for lexical special cases is not the same thing as handing all pronunciation control over to a static lexicon.

There are still language behaviors that need planning or rule modules:

- productive suffix allomorphy
- accent/profile-specific behavior
- prosodic reduction
- phrase-sensitive choices for function words

This means the right architecture is:

- planner and rule modules first
- curated app overrides next
- dictionary backstop after that
- engine default only when nothing stronger exists

### 4. Dictionary citation pronunciations can fight natural reduction

A full American English pronunciation dictionary usually records lexical or citation pronunciations, not every reduced conversational reading.

That matters for words like:

- `to`
- `the`
- `for`
- `of`

If we force those through a static dictionary path everywhere, we risk flattening natural prosody and making narration less fluid.

So the dictionary backstop should be broad, but not indiscriminate. The practical policy is:

- allow lexicalized apostrophe forms through the dictionary backstop
- allow uncovered content words through the dictionary backstop
- skip common reduction-sensitive function words unless another higher-priority artifact resolved them

### 5. The right implementation point is the engine translation layer

Merging a full `135k`-entry dictionary into the document-time resource layering map on every import would be wasteful.

That would make import-time merging do extra work even for documents that never touch most of the dictionary.

The better implementation shape is:

- preload the dictionary once as an app service
- keep manual resource layers small and intentional
- consult the dictionary selectively during engine translation for uncovered tokens

This gives us:

- broad lexical coverage
- low per-document overhead
- compatibility with the existing planner/resource architecture

### 6. This does not literally solve all of English

This is a strong systemic improvement, but it is not magic.

It should materially improve:

- contractions
- apostrophe-bearing lexical forms
- many irregular or non-transparent word pronunciations
- many plural and possessive lexical forms already present in the dictionary

It does not by itself solve:

- context-dependent reductions
- phrase-level stress choices
- accent-specific realization differences beyond the underlying dictionary/accent profile
- every heteronym or syntax-dependent pronunciation choice

So this is best understood as a major lexical pronunciation layer, not the end of pronunciation work.

## Decision

Adopt CMUdict as an English pronunciation backstop for uncovered lexical items in the Kokoro translation path, while preserving:

- planner-owned pronunciation artifacts
- manual app lexicon overrides
- reduction-sensitive exemptions for common function words

## Implementation Notes

This research led directly to the following implementation direction:

- vendored `assets/cmudict.dict`
- vendored `third_party/cmudict/LICENSE`
- added `EnglishPronunciationDictionaryService` as a singleton preload service
- added dictionary-backed pronunciation translation for uncovered tokens
- kept guardrails for reduction-sensitive function words

## References

- CMU Pronouncing Dictionary repository  
  https://github.com/cmusphinx/cmudict

- CMUdict source dictionary  
  https://raw.githubusercontent.com/cmusphinx/cmudict/master/cmudict.dict

- CMUdict license  
  https://raw.githubusercontent.com/cmusphinx/cmudict/master/LICENSE
