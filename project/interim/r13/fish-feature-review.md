## Read Aloud and Drama 3 feature review R13

Reviewed November 4, 2026 Pacific against Read Aloud `b3d16b9` and its pinned
`mlx-audio==0.6.3`. This is a feature definition and reuse decision record, not
runtime qualification. It drives the existing R12 units A–F. R13's progressive
analysis amendment supplies the character/refinement policy.

### Evidence and decision rules

Fish model capability, its official serving stack, the Mac MLX implementation and
Read Aloud's exposed behavior are separate evidence levels. A backend signature
does not prove the running app uses it. Reuse maintained facilities first; implement
only the missing adapter or application policy. Broader upstream features must not
be reduced to the weakest engine's capabilities. Unsupported features remain
preserved content intent or explicitly deferred, not silently discarded.

Sources checked:

- [Fish overview](https://speech.fish.audio/): scenes, expression and long content.
- [Fish inference](https://speech.fish.audio/inference/): caller-supplied speaker
  tags/references, saved-reference endpoints, streaming and runtime requirements.
- [Drama model card](https://huggingface.co/fishaudio/drama-3): multi-reference
  speech and speaker tags; hardware-specific performance is not Mac evidence.
- [Technical report](https://arxiv.org/abs/2610.18010): directed performance,
  multi-turn revision and audio infilling; research capability is not adapter support.
- [Pinned MLX implementation](https://raw.githubusercontent.com/Blaizzy/mlx-audio/v0.6.3/mlx_audio/tts/models/fish_drama3/drama3.py): generation interface and resource ownership.
- [Pinned MLX text/chunk rules](https://raw.githubusercontent.com/Blaizzy/mlx-audio/v0.6.3/mlx_audio/tts/models/fish_drama3/chunking.py): tags, validation and splitting.

### Feature comparison and disposition

| ID / user outcome | Fish or pinned Mac backend | Read Aloud at reviewed baseline | Definition, owner and disposition |
| --- | --- | --- | --- |
| FR01 — Quick cast, then better analysis | Reviewed interfaces produce speech; no structured prose entity/coreference/gender output established. Scene performance alone does not establish attribution accuracy. | Sequential heuristic analysis per fragment; no independently scheduled deeper pass. | **App responsibility unless a native alternative qualifies.** A/#125/#127: fast discovery and deeper refinement into the same deltas. Before adopting a separate component, test any demonstrated Fish analysis facility against the same source-span/quality/latency oracle. Do not build parallel providers for equivalent outcomes. |
| FR02 — Characters and choices survive reopening | Speaker tags identify roles inside a generation request, not a persisted book-character schema. | Cast/evidence and exact-source choices exist; unified work-level aggregate remains planned. | **Retain app ownership.** A/#126: one Character, separate gender evidence, selectedVoice, aliases and one migration. Map IDs to local engine slots. |
| FR03 — Automatic voices fit characters | References condition voice identity; no verified automatic library-to-book-character matcher in reviewed APIs. | Gender matcher exists; reported all-male City behavior is unresolved. | **Repair integrated selection.** A/#126 plus B/#111: trace cue → policy → requested/effective binding → emitted voice. Preserve manual choices. Test catalog permutation, late evidence and the private all-female passage. |
| FR04 — At least five suitable, usable choices | Fish provides reference-based voices and saved-reference facilities. | Shared catalog plus Fish references; declared gender is not acoustic qualification. | **Reuse reference assets and current library.** B/#111: verify downloads, identity, preview and actual playback; rank compatible choices from evidence. No second voice database/server solely for references. |
| FR05 — Efficient multi-character scenes | Native speaker tags and multiple reference inputs. [Inference](https://speech.fish.audio/inference/) | Python adapter supplies one reference per request. | **Adapt the request boundary.** B/#111: bounded turns and reference list from Character selections; A/B/A without reload. Preserve source mapping; demonstrate another engine lowering the same turns. |
| FR06 — Reuse voice conditioning | Pinned MLX owns encoded references and prefix caching. | Resident model calls can already benefit; no measured app cache-hit receipt. | **Reuse existing cache.** B/#111: preserve model lifetime, stable reference sets and content identity; measure hits/memory. Do not add another encoding/KV cache. |
| FR07 — Complete, prompt streamed speech | Native generation/chunking and incremental audio output. | Adapter consumes streaming results and retains final pieces; native acceptance open. | **Retain and qualify.** B/#111 with C/#113: emitted ending, cancellation, continuity and first audio. App bounds scene demand; library owns internal synthesis splitting. |
| FR08 — Consistent delivery across turns | Pinned MLX history is within one generate call. | Small separate requests cannot assume cross-call history. | **Use native bounded scenes first.** B/#111: compare voice continuity before custom history plumbing; only extend cross-call context for a measured unmet need, with revision/cache invalidation. |
| FR09 — Emotion and speech directions | Fish supports natural-language delivery; MLX chunk rules preserve cue/tag boundaries. | Canonical annotations/exact-model adjustment guards exist; MLX capability profile exposes plain-text fallback only. | **Translate and qualify.** B/#111: register exact supported directions, lower at engine boundary, preserve unsupported intent and literal bracketed prose. No custom emotion synthesizer or Kokoro substitutions in Fish text. |
| FR10 — Correct highlighting and seeking | Reviewed synthesis APIs do not establish source-word timestamps. | Source spans, routing and player position are app-owned. | **Retain mapping.** B/#111: consume real alignment when available, otherwise disclose scene-level precision or use bounded turns; do not invent timestamps from speaker tags. |
| FR11 — Listening/export speed works | Pinned MLX rejects non-unit synthesis speed. | Rate is carried in state/cache identity; effective MLX rate path remains open. | **Use existing audio facilities.** B/#111: define playback versus exported speed, implement with maintained player/DSP facilities and measure duration/pitch. Do not pass an unsupported parameter or show a control that has no effect. |
| FR12 — Director revision and local speech edits | Fish documents revision/infilling; Mac/app parity not established. [Report](https://arxiv.org/abs/2610.18010) | No exposed take/revision/infilling workflow verified. | **Future capability, outside current release.** Preserve compatible direction/source identities; evaluate backend before proposing UI or a custom editing engine. No new implementation slice by this review. |
| FR13 — Quality-first local models and hot switching | Model/serving support varies by backend; official CUDA deployment is not Mac deployment. | MLX variants, app downloads and runtime replacement exist; full memory/reuse/switch proof open. | **Retain app lifecycle, reuse loaders/download libraries.** C/#112/#113: exact model/precision identities, resident leases, <=100 GB total and physical-memory admission, dev/reopen reuse, no rebuild/restart. No borrowed GPU benchmark as acceptance. |
| FR14 — Native-quality audio | Drama produces native audio; model output and destination format are separate concerns. | Native-rate PCM/WAV handling exists; integrated playback/export proof open. | **Preserve existing support.** B/#111: actual native-rate output through player/export; conversion only for a destination need. No 24 kHz application ceiling. |
| FR15 — Durable books and reader experience | TTS/reference serving is not Read Aloud's imported document, annotations, navigation or publishing format. | Import, .radoc, player, caching and feedback already exist, with listed gaps. | **Keep and improve current infrastructure.** A/C/F: save per-pass coverage/intent, cancel promptly, truthful progress, reusable reopening and two-second external-launch acceptance. Do not replace the reader with a Fish WebUI or duplicate existing storage. |

### Concrete integration definitions

**Scene request (FR05–FR09):** extend existing TtsSpeakRequest/prepared bindings
with bounded ordered turns, source spans, stable character/selection revisions,
reference identities and canonical directions. In `assets/mlx_tts_worker.py`, adapt
the existing generation call to supported native inputs. Retain current output
framing, error handling and artifact admission. `mlx_speech_worker_processor.dart`
validates binding identity and represents all references; it does not encode them.
EngineCapabilityProfile records exact-runtime tested support. No new voice manager.

**Character and analysis (FR01–FR03):** extend the existing cast/profile/assignment
types and registry/import adapters under R2/R13. Maintain one repository writer and
two separately checkpointed analysis passes. Match the actual engine catalog and
publish a diagnostic reason with automatic choices; no story-wide female default
or name-only inference. The refinement provider remains replaceable. Fish analysis
adoption requires structured output and comparative evidence, not marketing terms.

**Native boundaries:** library speaker/tag limits split only that backend's scenes;
they do not limit a work's cast size. Library-internal chunks do not justify a second
duplicate byte-splitter. Stable source mapping, pause/seek/cancel and resource
admission remain app policies. If existing library behavior fails a requirement,
record the exact gap, prefer an upstream fix/upgrade, and bound any local adaptation.

### Delivery and proof, without duplicate projects

1. During A's minimal Character slice, reproduce the City selection failure and
   test fast/refined deltas; retain the 15 passing source tests as narrow baseline.
2. During B, first qualify the current short audible path, then implement FR05's
   reference-list/scene adapter and FR09 capability lowering. Measure FR06/FR08
   using native facilities before deciding any cache/history change is necessary.
3. C supplies only needed scheduling/asset/lifetime fixes; the same receipts cover
   cancellation, memory and reuse. D removes only duplication left after this work.
4. F reuses compatible evidence and closes native City ending, female automatic
   voices, five usable choices, timing/continuity, export and hardware gates.

There is no claim that the reported City regression is fixed, that native scenes
already work, or that the older staged implementation was recovered. No model was
downloaded or app launched for this review. A separate feature is justified only
by a specific uncovered outcome; no additional parallel plan or release scope is
created. Final architecture updates follow implementation and measured acceptance.
