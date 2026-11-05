# ModernBookNLP capabilities and Read Aloud reuse

Reviewed November 5, 2026 against the installed, hash-checked CPU adaptation of
upstream `84f1f34f6f0ec7c6e9c558b4371e61ea2354d95b`. This is a source capability
assessment, not literary-quality or mobile-performance acceptance. Execution scope
and sequencing are owned by [#110](https://github.com/kellyjanderson/readaloud/issues/110)
and [#127](https://github.com/kellyjanderson/readaloud/issues/127).

## Findings

ModernBookNLP is a BookNLP fork replacing quotation attribution with a ModernBERT
system. It retains the surrounding linguistic pipeline. Read Aloud currently runs
`entity,quote,coref`, joint scoring, the big models, and spaCy `en_core_web_sm` on
CPU in a separate resident process. Much of the useful information is therefore
already calculated; the previous worker reduced it to person mentions, quote
spans, and a token count before deleting its temporary files.

| Capability / upstream artifact | What the pinned implementation supplies | Reuse and boundary |
| --- | --- | --- |
| Tokenization, sentences, paragraphs, lemmas, POS and dependency syntax (`.tokens`) | spaCy-backed word positions, sentence/paragraph membership and syntactic heads | Reuse in deeper language analysis and source evidence. Keep original import/display anchors and fast first speech; NLP token boundaries are not audio alignment. Upstream `byte_onset/offset` are actually Python codepoint positions in this version; map explicitly to Dart UTF-16. |
| Typed entities (`.entities`) | Proper, nominal and pronoun mentions; people, places, facilities, geopolitical entities, organizations and vehicles, with nested spans | Avoid treating every capitalized name/place as a Character. Preserve all entity categories; promote suitable people into the existing Character owner. Mention frequency alone is not admission. |
| Name clustering and coreference | Alias grouping, first-person narrator clustering, pronoun resolution, local cluster IDs | Reuse upstream clustering instead of duplicating it inside every window. Read Aloud must still reconcile IDs across independently processed windows and enforce manual corrections. Default pronominal-only mode intentionally avoids some common-noun/name merges; switching to full coreference can conflate people and needs separate qualification. |
| Quote detection and attribution (`.quotes`) | Quote spans, attributed mention spans/text and the resolved cluster; ModernBERT joint scoring | Map to canonical Character IDs and future routes. Preserve unknowns. The exported winning speaker is not a calibrated confidence. Sparse dialogue and references outside the bounded window remain important tests. |
| Referential gender (`.book`, generated during coreference) | Pronoun-category estimates updated from coreference, using configurable prior information | Preserve as inferred/referential evidence with provenance. It does not establish explicit gender identity, presented gender, vocal age, or timbre. Default historic name priors must not defeat explicit story evidence or user selection; evaluate priors separately before changing them. |
| Character summaries (`.book`) | Proper/common/pronominal mention counts, actions as agent/patient, possessions and descriptive modifiers, with token references | Populate evidence on the existing Character aggregate; do not create another character database. `.book` omits characters seen only once, so `.entities` remains necessary. Modifiers/actions are candidates, not definitive biography, relationships, age or acting instructions. |
| Event tagging (optional `event`) | Tokens labeled for asserted events | Useful later as contextual evidence for delivery and narrative navigation. It does not output an ordered audiovisual timeline or timestamps. Currently disabled. |
| Supersense tagging (optional `supersense`) | Coarse lexical semantic spans such as communication, cognition or motion | Useful evidence for later interpretation, not an emotion/prosody classifier. Currently disabled. The existing multi-task entity tagger contains these heads, but extra work/resources and offline dependencies still require measurement. |
| Annotated HTML and debug pickles | Diagnostic renderings and intermediate Python objects | Do not persist or execute these as book content. Retain data-only artifacts and render a controlled UI if needed. |

The source executes tokenization → entity/optional semantic tagging → quote
attribution → name clustering/referential gender → coreference → updated gender
and character syntax summaries. Quotation attribution is therefore only one part
of the existing pipeline. `coref` requires both `entity` and `quote`; stages cannot
be arbitrarily scheduled as independent jobs. Our admission tokenizer currently
runs before upstream processing tokenizes again; removing that duplicate requires
a supported bounded upstream handoff, not dropping the pre-inference bound.

The full upstream process consumes a file and resets IDs per invocation. Keeping
its model resident does not retain a book-wide character graph. Read Aloud must
continue to own bounded rolling context, source/revision checks, cancellation,
coverage, stable book identity, corrective edits, voice selection, and `.radoc`
persistence. Window overlap and cross-window reconciliation need measured recall
and collision tests; full-book processing must never gate first speech.

## Implications

The durable record should retain the data-only `.tokens`, `.entities`, `.quotes`
and `.book` artifacts that are already generated, with exact source, provider,
model, adapter and feature provenance. These are immutable evidence, not a second
set of mutable Characters. Consumers must validate coordinates and map local IDs
before promotion. Older records may be retained for provenance without being
reused under incompatible dependencies. A disabled stage is distinct from a
completed stage with zero findings.

Deep character extraction, aliases, pronoun inference, descriptors and dialogue
attribution should use one coordinated upstream result. Existing fast discovery
can provide provisional startup results; qualified neural reconciliation supersedes
its deep rules rather than layering several competing authorities. Explicit user
voice choices and corrections take precedence. Keep separate explicit, implied,
and presented gender fields. Upstream pronoun distributions are evidence for one
aspect of that model, not values to copy into all three fields.

Fish remains responsible for speech realization using native references and
supported performance controls. Read Aloud owns durable casting and canonical
performance intent. Neither Fish nor ModernBookNLP replaces document import,
illustration preservation, playback scheduling, native-rate audio, rendered-asset
caching, or the shared continuous-period timeline. Events and semantic tags can
support a later evidence-based interpretation layer, with unsupported intentions
retained rather than blindly converted to Fish prompts.

Future qualification must cover sparse dialogue (Rosalina), City characters,
place/person discrimination, aliases crossing windows, single-mention people,
unknown speakers, differing pronoun/name evidence, and stable selected voices.
Independent labels and per-function errors are required; the paper's benchmark
scores do not establish accuracy in our windowing, CPU adaptation or stories.

## References

- [Pinned ModernBookNLP source](https://github.com/gasmichel/ModernBookNLP_QA/tree/84f1f34f6f0ec7c6e9c558b4371e61ea2354d95b/ModernBookNLP): `english_booknlp.py` (`process`, `get_syntax`), `entity_tagger.py`, `gender_inference_model_1.py`, `name_coref.py`.
- [Fork description](https://github.com/gasmichel/ModernBookNLP_QA/tree/main/ModernBookNLP) and [BookNLP capability/output definitions](https://github.com/booknlp/booknlp).
- [Paper](https://arxiv.org/abs/2608.02359): joint quotation attribution, not a replacement for all BookNLP models.
- Local integration: [worker](../../assets/modernbooknlp_worker.py), [provider contract](../../lib/src/services/modernbooknlp_provider.dart), [Character adapter](../../lib/src/services/modernbooknlp_character_adapter.dart), [runtime guide](../../docs/modernbooknlp-provider.md).
