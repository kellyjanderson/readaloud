## Review coverage R11

Assessment frozen November 4, 2026 Pacific at `a2fdb4c`. This covers the actionable
findings and retention decisions in reviews #111–#116, #119, #120 and #124, plus
the expressly inherited #83/#91/#55 acceptance gates. It does not claim a new
line-by-line code audit or expand scope to every historical specification.
Superseded observations are mapped to completed repairs or retained verification;
they are not silently reintroduced as new defects. Each row has an implementation
owner, plan step and closure requirement. Conditional extractions require a
recorded implement/defer decision; they cannot disappear from reconciliation.

Status at this baseline: **Done** = the bounded stated work is completed;
**Partial** = some implementation exists; **Verify** = code exists but the relevant
acceptance is still missing; **Planned** = designed, remaining implementation has
not started; **Conditional** = intentionally contingent on net benefit;
**Gate** = release evidence/decision remains open. These are evidence assessments,
not GitHub Project status or completion percentages.

### Drama integration — review #111

Source: [minimum architectural change](https://github.com/kellyjanderson/readaloud/issues/111#minimum-architectural-change), fiction acceptance and modern-model extension. Design: ACD-S1, M1, R1.

| ID / reviewed point | Step / owner | Progress and explicit closure |
| --- | --- | --- |
| F01 shared descriptor; neutral orchestration; preserve existing player/artifacts | 3, 6, 7 / #113, #111, #112 | Partial. Complete descriptor/session extraction once, with per-engine providers. |
| F02 maintained MLX/Hub; pinned prequantized variants and actual identity | 2, 7 / #112 | Partial. Existing backend/downloads retained; validate complete snapshot and variant identity. |
| F03 all generated results, empty final markers, ordered bounded streaming | 2, 6 / #111 | Partial. Complete-result/final-marker fixes integrated; early incremental piece admission and native ending still require proof. |
| F04 native audio format through validation/correction/playback/export | 2, 8 / #111, #114 | Verify. Native-rate implementation exists; actual Drama output/export and format fixtures close it. No forced 24 kHz. |
| F05 bounded native multi-reference scenes, speaker limits, literal control-tag text | 6 / #111 | Planned. Native limit splitting and safe literal-text encoding are explicit supplement requirements. |
| F06 source mapping, uncertain speakers, single-voice mode, binding invalidation | 1, 4, 6 / #125, #126, #111 | Partial. Preserve current routing; prove scene alignment/fallback and only affected future bindings invalidated. |
| F07 stop/cancel/seek/export and switch while active | 2, 3, 7 / #111, #113, #112 | Partial. Existing lifecycle fixes need complete adjacent-owner/native stress. |
| F08 five usable choices per character, reference provenance/identity, full City ending and sustained fiction | 2, 6, 10 / #111, #122 | Partial. Catalog/reference bank exists; counts alone do not qualify previews, distinction, matching or repeated identity. |
| F09 other modern models through the same qualified contract | 6, 7 / #111, #112 | Planned. Demonstrate a second engine; Qwen/MOSS/reference and fixed-preset limits remain explicit. No blanket support claim. |

### Model lifecycle and hardware — review #112

Source: [catalog/compatibility](https://github.com/kellyjanderson/readaloud/issues/112#catalog-and-compatibility-contract), hardware policy, transition and migration. Design: ACD-M1.

| ID / reviewed point | Step / owner | Progress and explicit closure |
| --- | --- | --- |
| M01 family/variant/runtime schema, capability/codec/notice qualification | 6, 7 / #112 | Partial. Replace remaining repeated lists with one versioned descriptor. |
| M02 validated data-only catalog refresh and incompatible-runtime handling | 7 / #112 | Planned. Preserve last valid catalog; no executable-code refresh; supported variants require no rebuild. |
| M03 quality first, <=100 GB total and physical headroom; no bf16 transient for quantized loads | 7 / #112 | Partial. Measure entire process tree and native/GPU use; enforce admission before load. |
| M04 real M3 identification and smaller compatible fallback | 7, 10 / #112, #122 | Gate. Exact secondary hardware is unknown; no M3 certification from M5 simulation. |
| M05 persistent model cache, complete offline reuse, partial resume/corruption/disk-space failure | 2, 7 / #112 | Partial. Existing local-first reuse and later offline producer evidence retained; complete app/rebuild/retry matrix open. Never auto-fetch both large variants or delete another installed variant. |
| M06 latest-wins live transition, selected versus active, retry/rollback/quit | 3, 7 / #113, #112 | Partial. Existing live replacement retained; A/B/A and A/B/C through read/preview/export/load remain unqualified. |
| M07 legacy preference aliases including Voxtral full/4-bit; keep weights separate from audio | 7 / #112 | Planned. Explicit migration preserves meaning; valid audio requires matching full conditioning/configuration. |
| M08 matched model source lineage and honest quality comparison | 7 / #112 | Gate. Compare matched revisions or report confound; bigger precision alone is not quality evidence. |

### Concurrency — review #113

Source: [original findings](https://github.com/kellyjanderson/readaloud/issues/113#findings-requiring-repair), ownership, cancellation and proof scenarios. Original line numbers predate integrated repairs. Design: ACD-R1.

| ID / reviewed point | Step / owner | Progress and explicit closure |
| --- | --- | --- |
| R01 cancellation capability forwarding and exact lease/request isolation | 3 / #113 | Partial. Prove playback cancellation cannot terminate another export/load lease; retain non-preemptible Kokoro semantics. |
| R02 out-of-band stop before transition/drain waits; timeout is not cancellation | 3, 7 / #113 | Partial. Verify cancellation under actual load and bounded termination/reaping. |
| R03 delayed start/close, idempotent start/close, late child creation | 3 / #113 | Verify. Process refactor exists; inspect handles/settlement in delayed-start and duplicate-close tests. |
| R04 child-owned streams/pending/cleanup; old exit cannot damage successor | 3 / #113 | Verify. Late stdout/stderr/exit and stale success/failure assertions plus native replacement. |
| R05 malformed/oversized reply, duplicate final, crash/timeout then load attestation | 3 / #113 | Verify. Existing retirement/load-replay code retained; add missing adversarial cases and native recovery proof. |
| R06 actual snapshot/codec/runtime/configuration identity in cache | 2, 6, 7 / #111, #112 | Partial. Content identity implemented; scene context and new rate realization need complete identity coverage. |
| R07 artifact reads/hashes/fsync off the UI isolate | 3, 8 / #113, #114 | Verify. Offload exists; native cache-hit-under-scroll and admitted I/O bounds remain acceptance. |
| R08 download callback accounting and thread-safe aggregation | 2, 7 / #119, #112 | Partial. Old shared-map implementation changed; test current aggregate progress under parallel/resumed callbacks, not a hypothetical old race. |
| R09 one app shutdown bridge, 12-second native fallback budget, zero orphan | 3, 10 / #113 | Partial. Explicit whole-close budget and TERM-ignoring child proof added to supplement. |
| R10 million-chunk MLX planning, duplicate eager engine, all producer bounds | 3 / #113 | Planned. Million-chunk path remains; replace it with bounded demand and preserve existing admission/credits. |
| R11 normal/cancel/failure/reload/seek/export/preview interleavings | 2, 3, 7, 10 / #113, #122 | Verify. Source/fake-process results never replace native resource, response and audible continuity evidence. |

### Consolidation and library decisions — review #114

Source: [C01–C09 inventory](https://github.com/kellyjanderson/readaloud/issues/114#consolidation-inventory-r8), library table and correctness findings. Design: ACD-D1; no new duplicate-code discovery task.

| ID / reviewed point | Step / owner | Progress and explicit closure |
| --- | --- | --- |
| C01 catalog/capability/voice metadata | 6, 7 / #111, #112 | Partial. Implemented once by S1/M1, not again in consolidation. |
| C02 neutral buffered engine/session and eager construction | 3 / #113 | Partial. Shared runtime/player already exists; remove remaining backend coupling and unneeded construction. |
| C03 RIFF/PCM structure, random access and distinct consumer policies | 8 / #114 | Planned. Shared chunk walker/header writer with corrupt/odd/metadata/native-rate fixtures and bounded export. |
| C04 text/DOCX/EPUB/HTML adapter parity and metadata/source mapping | 8 / #114 | Planned. Common events preserve richer path; retain shared RTF, archive/xml/html and pdfrx; no custom parser replacement. |
| C05 data-only document envelope, no JSON round trip | 8 after 4 / #114 | Planned. Keep codec validation, snapshots and writer ownership separate; preserve schema and PDF inclusion options. |
| C06 adjacency traversal versus distinct casting merge predicates | 8 / #114 | Conditional. Extract only for demonstrated simplification; record reason if retained. |
| C07 production protocol/catalog probes; shared headless setup; complete offline voice authoring | 8 / #114 | Planned. Remove private-global mutation/hard-coded inventories; guarantee cleanup and preserve evidence semantics. |
| C08 isolate lifecycle mechanics, not a generic worker framework | 8 after 3 / #114 | Conditional. Extract only after ownership proofs; retain domain queue/epoch policy. |
| C09 file/directory bookmark grant and balanced security-scope leases | 8 / #114 | Conditional. Keep native OS semantics and test actual permissions/renewal/cancel/close if changed. |
| C10 maintained-library adoption versus concrete unmet requirements | 3, 8 / #113, #114 | Planned evaluation per slice. Retain mlx-audio, Hub, just_audio, archive/xml/html/pdfrx and SuperListView. async/pool/WAV/SQL candidates require compatibility, bounded memory, notices and actual removed code. No automatic database migration. |
| C11 speech rate in cache but no effective MLX speed | 6 / #111 | Planned. Confirmed source gap; explicit playback/native/export rate behavior and duration tests are added below. |

### Repository and agent workflow — reviews #115/#116

Sources: [#115 corrections/triage](https://github.com/kellyjanderson/readaloud/issues/115#specific-documentation-corrections), [#116 replacement/rollout](https://github.com/kellyjanderson/readaloud/issues/116#concrete-replacement-shape-for-agentsmd). Designs: ACD-P1/G1.

| ID / reviewed point | Step / owner | Progress and explicit closure |
| --- | --- | --- |
| P01 preserve WIP, consolidate branches, cleanup tag and safe branch retirement | 0 / #122 | Done for recorded scope. Main/tag unchanged; integrated source on release branch; no repeated cleanup assignment. |
| P02 coherent file layout; preserve fixtures, vendor notices, local assets/evidence and nested WIP | 0 / #115 | Done for recorded layout pass. Large preserved directories are not automatically disposable. |
| P03 working writable native launcher without preexisting cache | 0, 10 / #115, #122 | Done launcher; Verify final clean packaged onboarding/runtime separately. |
| P04 current navigation, MLX guide, local checks, executable automatic workflow removal | 9 / #115 | Done source changes. Actions currently disabled and no tracked automatic workflow remains; retain policy. |
| P05 reconcile dated architecture, saved choice/env override, live-switch help, main versus candidate claims | 9 / #115 | Partial. Update against the actual final supported runtime/build; no stale 24-kHz or restart requirement. |
| P06 GitHub About/topics/homepage, cleared actual-build media and support matrix | 9 / #115 | Planned. No invented homepage, private manuscript or unqualified feature claims. |
| P07 old issue/PR/milestone triage without equating merge with acceptance | 9 / #115 | Partial. #49–#53 and #63 remain open; #64 is merged. #63 is an issue, not a PR as the original review called it. Reconcile evidence; no new release workflow. |
| G01 directed default, compact AGENTS and conditional orchestration | 9 / #116 | Partial. Directed execution used; comprehensive instruction reduction/rule-survival map not implemented. |
| G02 distinct thin ACD/plan routes; conditional template fields | 9 / #116 | Partial. Skills exist and interim lifecycle is aligned; remaining template/duplicate-context reduction open. |
| G03 retired managed stubs; retain scoped audio/UI/completion helpers | 9 / #116 | Planned. Use verified SkillsKeeper source authority; preserve unique rules before retiring. |
| G04 custom agents absent locally; unrelated global research roles retained | 9 / #116 | Done review/retention decision. No fabricated project roles or global rewrite needed. |
| G05 comparable directed fix/re-entry and authorized independent-work trial | 9 / #116 | Planned. Measure actual context/coordination/elapsed fields and rule retention; no made-up token savings or unnecessary dispatch. |
| G06 Git-versioned interim drafts, publication, reconciliation and retirement | 0, 9 / #115, #116 | Done at a2fdb4c. Follow that lifecycle; do not return designs to tmp or edit fixed R10 snapshots. |

### Feedback and preserved directed fixes — #119/#120

Sources: [#119 UI/state contract](https://github.com/kellyjanderson/readaloud/issues/119#ui-review-and-accepted-direction), [#120 evidence](https://github.com/kellyjanderson/readaloud/issues/120). Design: ACD-F1 and retained exact-model adjustment registry.

| ID / reviewed point | Step / owner | Progress and explicit closure |
| --- | --- | --- |
| U01 remove covering popup; one quiet inline summary and optional Activity | 2, 7 / #119 | Verify. Implemented; complete native state/layout checks remain. |
| U02 real completed-work fractions; unknown/finalizing/waiting/stalled states; no spinners | 2, 7 / #119 | Verify. Shared measured controls exist; compare actual producer counts across Settings/voices/reader. |
| U03 active first, terminal fade, persistent recoverable/copyable errors | 7 / #119 | Verify. Implemented source behavior; real retry/stale-error/terminal scenarios remain. |
| U04 stable reader/transport position, bounded scrolling/stage rows, reduced motion and timer cleanup | 7 / #119 | Verify. Explicit native accessibility/state matrix retained; do not turn Activity into an unbounded log. |
| U05 paused preparation stages, planning cancellation terminal event, distinct download Cancel/Resume | 3, 7 / #113, #119 | Partial. Terminal repairs integrated; verify every producer and implement missing acquisition controls. |
| X01 copyable errors and accumulated session cast | 2, 4, 10 / #120 | Verify. Integrated; retain real import/dialog/native cases, not injected cast objects only. |
| X02 retained audio/empty finals, first-Play retry/cancel | 2, 3, 10 / #120 | Verify. Integrated source tests; actual failure/retry/ending and no stale speech still required. |
| X03 exact-source explicit choice/Reset, incomplete reopen and preference recovery | 4 / #120, #126 | Verify baseline; extend to work revisions. No new title/name-based recovery or implicit choice overwrites. |
| X04 exact engine/model/revision/policy pronunciation/emotive adjustment scope | 4, 6 / #120, #111 | Verify. Registry/producer fixes integrated; preserve serialization, unknown/deferred scopes and native Fish/Kokoro comparison. |

### Characters and portable Fish concepts — review #124

Sources: [A1/A2/C1/V1/P1](https://github.com/kellyjanderson/readaloud/issues/124). Designs: ACD-A1/C1/A2/S1.

| ID / reviewed point | Step / owner | Progress and explicit closure |
| --- | --- | --- |
| A01 fragment attribution/context, paragraph coordinates and replay | 1 / #125 | Planned; reproduced failing oracle remains unfixed. Test unknowns, tags/pronouns/multi-speaker/cross-work/stale replay. |
| A02 local ModernBookNLP QA/encoder/entity/spaCy assets, CPU/MPS and isolated environment | 5 / #127 | Planned. Source review done; no local install/performance/promotion proof. App owns all pinned downloads. |
| A03 independent held-out/City provider comparison and non-regression | 5 / #127 | Planned. Promotion needs accuracy/coverage, startup, bounded context and memory; failure leads to a recorded alternative decision, not abandoned attribution work. |
| K01 stable work/character identity; comprehensive evidence/aliases/conflicts and source revisions | 4 / #126 | Planned. Additive record and partial projections; no title-based cross-work merging. |
| K02 stated/inferred/presented gender separation and inference precedence | 4 / #126 | Planned. Preserve all facts/conflicts; pronoun-first matching hints must not erase explicitly stated identity or turn voice choice into gender evidence. |
| K03 durable voice intent/Reset; merge/split; cache loss/edit/reopen/engine switch | 4 / #126 | Partial. Exact-source persistence exists; broader work schema/migration and conflict handling do not. |
| S01 common bounded ordered scenes, structural boundaries and source identity | 6 / #111 | Planned. Native Fish and serial compatibility lowering share intent, not prompt syntax. |
| S02 reference identity versus prepared binding/native resource; one casting authority | 4, 6 / #126, #111 | Partial. Prepared bindings exist; native reference-set reuse and portable work identity remain. |
| S03 canonical delivery/inflection plus exact-model supported/approximated/deferred realization | 4, 6 / #111 | Partial. #120 scoped registry exists; qualified model-specific realization remains. |
| S04 bounded continuation and conditioning-aware cache invalidation | 3, 6 / #113, #111 | Planned. Seek/edit/cast/model changes revoke incompatible history; no cross-model tensors. |
| S05 common ordered audio pieces/final marker/native format/truthful alignment | 6 / #111 | Partial. Complete output/native rates implemented; shared early piece/scene protocol remains. |
| S06 observable residency/preparation/reuse/eviction and second-engine benefit | 6, 7 / #111, #112 | Planned. Measure actual active-cast resource reuse; fixed Fish cache sizes do not become global character limits. |
| S07 adapter-only Fish tags, token/speaker limits, codec/KV/sampling and qualified claims | 6 / #111 | Planned boundary. Literal control-looking prose and unsupported capabilities have explicit tests. |

### Inherited product and release gates — #83/#91/#55

These obligations were already referenced by R10; R11 makes their individual closure explicit. Historical #83 source findings are not asserted to remain identical defects.

| ID / reviewed point | Step / owner | Progress and explicit closure |
| --- | --- | --- |
| B01 / #83 F1 startup errors, retry and stale failure | 2, 3, 7 / #113, #119 | Partial. Inject missing/corrupt assets and initial errors in real launch flow; no swallowed readiness failure. |
| B02 / F2 usable Play/voice selection during delayed/failed initialization | 2, 7 / #119 | Verify. Exact launch/notice/Play/voice path; pending intent cancellable and failure actionable. |
| B03 / F3 redundant model copy/hash/session work | 3, 7 / #113, #112 | Verify. Measure cold/warm/voice/cache paths; retain immutable identity and corrupt-asset invalidation. |
| B04 / F4 first speech before later document/character processing | 3, 8, 10 / #113, #114 | Partial. Incremental paths exist; prove bounded complete pipeline and rendered EOF with long documents. |
| B05 / F5 startup lead versus latency and buffering cancellation | 2, 3, 10 / #113 | Verify. Tune only with sustained-refill proof; immediate intent cancellation prevents delayed speech. |
| B06 / F6 meaningful progress on every >1–2 second operation | 7 / #119 | Verify. Per-owner counts/units, changing totals, wait/failure/finalization and usability at completion. |
| B07 / F7 full launch-to-audible timeline | 2, 10 / #122 | Gate. Independent launch/frame/Play/resource/PCM/actual-output timestamps; no shifted measurement start. |
| B08 / F8 automatic reusable .radoc application path | 3, 4, 8, 10 / #113, #126, #114 | Partial. Prove actual persisted reopen skipping valid analysis, restored position/cast/directions and crash/schema invalidation. Codec round-trip is insufficient. |
| B09 / F9 expected cast and actual UI latency under load | 1, 4, 10 / #125, #126, #122 | Gate. Existing regressions plus native intake/cast/input traces; no test-presence claim. |
| B10 / #83 frozen five-prose P0–P4 oracle suite and held-out variants | 1, 4, 5, 10 / #125, #126, #127 | Gate. Reuse existing fixtures; close missing independent oracle, real voice-dialog and native stages. Named non-speakers are negative controls. |
| B11 / #83 pronoun/presentation inference provenance and conflicts | 4 / #126 | Gate. Preserve unknown/they-them, cross-references, aliases and explicit override; test actual automatic matching, not merely returned labels. |
| B12 / #83 10 launches/case; <=2,000 ms every valid trial; response/stall budgets | 10 / #122 | Gate. Primary M5/128 GB; cold installed-model, warm and .radoc; short/long inputs; full samples, max/percentiles. Engineering 100-ms budgets retain their proposal status. |
| B13 / #83 30-minute real-speech continuity, speed/navigation, documented load/recovery | 6, 10 / #111, #122 | Gate. Normal-load zero unintended underruns/restart loops; emitted live output and listening. Unsustainable injected load is recovery evidence, not a continuity pass. |
| Q01 / #91 engineering qualification before final human session | 10 / #122, #91 | Gate. Fix ordinary deterministic defects first; exact build and only residual perceptual/usability questions for human acceptance. |
| Q02 / #55 complete component notices, model/voice provenance and packaging | 9, 10 / #55, #122 | Partial/Gate. Existing notice tooling retained; actual shipped dependency/native/runtime/model/voice inventory, in-app and package notices, license decision and redistribution clearance remain mandatory. |

### Coverage rule

Every row must close with implementation evidence, preservation evidence, or an explicit approved/recorded conditional disposition. A source-tested fix with missing native proof stays Verify/Partial. A conditional deferral is not implemented code. No percentage is inferred from rows or issue counts. Current changes after this snapshot belong in GitHub receipts; a material plan revision gets a new versioned package.
