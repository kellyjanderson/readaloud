# Target document-to-speakers architecture

The reader should consume the same typed book ranges whether someone opens an EPUB for the first time, resumes an interrupted conversion or opens a published audio book. The first useful range can feed the reader while later ranges are being prepared. Full conversion is a separate offline action. A complete text graph, complete chapter analysis, complete audio coverage and a published archive are four different facts.

```text
source adapter / saved book / verified checkpoint
              → revisioned prepared range → display and navigation
                        ↓
         chapter evidence + authored directions + cast edits
                        ↓
          linguistic cut candidates → voice/model render plan
                        ↓
          verified saved audio OR Flutter/Dart native engine
                        ↓
          decoded PCM + frame intervals → device queue / export
```

| Boundary | Producer, contract and acceptance |
| --- | --- |
| Intake → prepared book | One import owner maps source to stable anchors, UTF-16 display/spoken offsets, authored directions and range coverage. A version adapter reads old books. Admit a contiguous prefix or a validated seek window. Check source identity before every persisted reuse. Publish revisions atomically. |
| Evidence → phrase decisions | ModernBookNLP contributes sentences, tokens, syntax, quote and coreference links with provenance. Map into canonical coordinates. Evaluate linguistic cuts and speaker accuracy separately against annotated fixtures. Use a bounded provisional opening only under the agreed chapter admission policy. Late evidence can revise future uncommitted plans. User voice choices and authored emphasis outrank inferred candidates. |
| Phrase decisions → synthesis | Dart chooses among linguistic boundaries under per-model context, voice, turn and resource limits. Preserve unsupported directions for another rendition. Keep tempo requested at synthesis, listening rate and exported tempo distinguishable. Reference voice and pronunciation overrides control different aspects of accent. |
| Synthesis → assets | Flutter/Dart exposes a typed backend and capability result on every supported platform. Reuse maintained bindings or write the missing thin plugin/FFI bridge to a compiled implementation. The first proof uses the exact Fish 4-bit checkpoint and voice references. Model loading, reference encoding and generation run on an owned native lane. Optional NLP has an independent portability decision. [Platform directive](../../../AGENTS.md#flutterdart-platform-and-native-bindings) |
| Assets → device or export | Store placements as half-open sample-frame intervals with explicit source and output rates. Splitting a continuous render anywhere, including inside a word, implies zero gap. Semantic timing is counted once. A cut between two independent inferences can change the sounds themselves. Use model continuation or a bounded shared-context rerender when alignment fails. Overlap only where a validated placement calls for it. Both sinks consume identical placements. |
| Persistent media | Compare FLAC, ALAC and NARALAC against identical PCM. The manifest owns the book timeline, range-to-frame map and rendition provenance. Optional per-asset metadata can carry verified identities and local offsets. Generated speech needs a declared time origin before choosing NARALAC recording fields. Old WAV-backed packages retain their reader. A new format needs explicit version negotiation and atomic publication. |

**Execution ownership.** The Flutter main isolate owns UI and commands. The preparation supervisor grants bounded range credit. The analysis owner admits chapter/window requests keyed by source and analysis revision. The speech owner admits native generation under memory and packet credit. The audio owner grants bounded decoded-frame credit against the output clock. Each owner rejects stale success, failure, progress and late packets. Cancel revokes output immediately, wakes blocked producers, and drains or quarantines native resources on timeout. Quit verifies owned process exit. Persistence stages each attempt and publishes only verified coverage. Progress counts completed ranges, scenes or frames, names an unknown total or wait honestly, and keeps retry actionable.

**Migration decisions.** Preserve v1–v5, existing saved audio, reference digests and explicit voice edits throughout. All Kokoro-specific paths are deprecated. Retire those paths only after saved selections and unsupported-platform fallbacks have a qualified migration. Native libraries may differ per platform behind the same Dart API. A successful Apple Silicon Fish proof is evidence for one checkpoint and deployment target. Alternatives for Qwen, Voxtral, MOSS and optional ModernBookNLP each require their own compatibility result. Python remains useful for offline comparison tooling.

**Release boundaries.** #122 already includes chapter-first analysis, Fish blocks, dynamic audio-only publication, basic continuity and selective regeneration. #158 has a working branch and an unresolved opening-admission tradeoff. #135 owns advanced timing and multimedia. Architecture R1 proposes portable bindings and lossless assets for scheduling by the coordinator. FLAC is the first candidate for comparison. The chosen codec, public version, per-engine support and scope of optional NLP migration each require evidence and a release decision.

[Chapter release amendment](https://github.com/kellyjanderson/readaloud/issues/122#issuecomment-6990848671) · [Following release](https://github.com/kellyjanderson/readaloud/issues/135) · [Existing Kokoro removal design](https://github.com/kellyjanderson/readaloud/issues/165)
