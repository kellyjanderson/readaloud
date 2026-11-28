## Implementation plan R11

November 4, 2026 Pacific; baseline `a2fdb4cfda9044bbaedea508e27a622931c5bc07`.
This revision supersedes R10's execution index and records a fixed progress
assessment, a finding-by-finding coverage map, and explicit acceptance supplements.
The ten ACD R1 designs remain valid with the R11 supplement; their fixed R10 files
are unchanged. GitHub owns subsequent live execution state and evidence.

**Coverage:** [every reviewed point and its disposition](https://github.com/kellyjanderson/readaloud/issues/110#review-coverage-r11)
and [explicit supplement](https://github.com/kellyjanderson/readaloud/issues/110#review-acceptance-supplement-r11).
The corpus is #111–#116/#119/#120/#124 and inherited #83/#91/#55 gates. This is a
coverage reconciliation, not a repeat repository audit. No new product code,
models, app runs or product test results are introduced by this planning revision.

### What is already accomplished

- Main cleanup baseline: PR #117, `d54fb7f`, immutable `v1.0.0-cleanup.1`.
- All intended feature histories integrated at `164e13a`; draft PR #123 targets
  main, release #122/milestone 2 owns final readiness. Main/tag are unchanged.
- 88 local/61 remote branch refs retired; only main/release remain. Worktree
  files and assets retained. The authorized app and child were normally quit.
- Writable verified Flutter bootstrap, initial Drama adapter/variants, native
  rates, complete generator/final-marker handling, lifecycle/cache repairs,
  app-owned preparation, inline measured feedback and persistent download lookup.
- #120's accumulated cast, copyable errors, audio retention/retry, exact-source
  explicit voice choices/Reset and exact-model speech-adjustment registry.
- File-layout cleanup at `1f605cf`; Git-versioned interim documents, source
  provenance/hashes and lifecycle-aligned skills at `a2fdb4c`.
- Existing validation: source integration at `164e13a` had 655 Flutter passes,
  two skips, clean scoped analyzer and 17 managed-runtime worker passes. Layout/
  tooling checks and seven bootstrap tests passed separately. These are existing
  bounded receipts, not new audible-product acceptance.

The A1 fragment-attribution oracle is reproduced and still unfixed. New persistent
work records, ModernBookNLP integration and native multi-reference Fish scenes are
designed, not implemented. The current code still has the million-chunk MLX planning
path and lacks effective MLX speech-rate realization. Later #120 offline bf16
producer evidence supersedes earlier partial-download-only observations; it does
not establish all native playback/continuity gates.

### Step 0 — Preserve and use the integrated foundation

**Progress: completed for the recorded integration, repository cleanup and design
storage scope.** Owner #122/#115. Read current release head and WIP once at entry;
do not redo merges, cleanup tag, retired branches, launcher or archive migration.
Keep the repository/local-file map and all preserved user/model/evidence assets.
Clean packaged onboarding is a Step 10 test, not a reason to rebuild this foundation.
Result: one recoverable working codebase and one obvious design/implementation path.

### Step 1 — Fix attribution across preparation boundaries

**Progress: diagnosis/design complete; implementation not started; known failing
oracle remains.** Owner [#125](https://github.com/kellyjanderson/readaloud/issues/125),
[ACD-A1](https://github.com/kellyjanderson/readaloud/issues/124#acd-a1--revision-owned-incremental-attribution).
Preserve bounded preceding attributed context, global source/paragraph coordinates,
revision-owned checkpoints and replay. Keep unknowns and #120's accumulated cast.
First regression: split Alice/Bob/Alice/Bob must match whole input. Add boundary,
tag, pronoun, multi-speaker, ambiguous, replay/cancel and cross-work cases. Reuse
the existing independent held-out prose corpus. Result: processing chunks no
longer changes who is speaking. Exit includes bounded memory and no stale evidence.

### Step 2 — Prove the short real Drama reading path

**Progress: substantial adapter/download/audio code exists; full running-app
checkpoint remains unverified.** Owner #111, with #119/#120 preservation checks.
Use the valid installed model; download only missing/invalid assets through the
app. Verify complete offline reuse, unobscured real progress and retry. Read a
manually checked private City passage through its final words, using native rate;
exercise pause/resume, stop, seek and export. Check actual emitted audio, source
coverage, intended voice and listening, not just generated files. Record exact
app/runtime/model/reference identities, then normal Quit and child exit.
Pull only necessary runtime fixes forward if they block this proof. Result: the
highest-priority feature becomes an observable working baseline before broad
refactoring. Heavy tests may be optional in routine runs; omitted acceptance is
not a pass.

### Step 3 — Bound work and finish coherent concurrency

**Progress: lifecycle/admission repairs partly implemented; remaining demand and
ownership work is open.** Owner #113,
[ACD-R1](https://github.com/kellyjanderson/readaloud/issues/113#acd-r1--bounded-reading-and-single-owner-runtime-lifecycle).
Replace million-chunk planning with bounded demand/lead and keep preparation,
planning, inference, I/O, UI and persistence owners distinct. Remove unneeded eager
engine creation and extract neutral session responsibility without replacing the
player. Verify precise lease cancellation, stale success/failure, delayed start,
poisoned child reload and shared shutdown completion within the native fallback
budget. Check repeated model copy/hash work and cache-hit I/O under scrolling.
Keep pending Play cancellation immediate while native drain is separately tracked.
Exit: bounded queues/memory across book sizes, responsive controls, no stale audio
and no orphan child. Result: visible and internal concurrency follow one contract.

### Step 4 — Persist comprehensive characters and their voice intent

**Progress: exact-source voice persistence/Reset and accumulated cast are
implemented; work-level records and broader migration are not.** Owner
[#126](https://github.com/kellyjanderson/readaloud/issues/126),
[ACD-C1](https://github.com/kellyjanderson/readaloud/issues/124#acd-c1--persistent-work-characters-and-voice-intent).
Add stable work/character IDs, aliases/redirects, evidence/facts/conflicts and
separate stated, inferred and contextual gender. Preserve pronoun-first matching
hints without overwriting stated identity or guessing from names/voices.
Store explicit voice intent and Reset independently of prepared engine resources.
Migrate old preferences/.radoc additively; preserve choices through unfinished
reopen, cache loss, verified source move/edit association, engine changes and
merge/split. Never associate different works by title/name alone. Prove the actual
application reopen path, not only codecs. Result: the story owns its cast and voices.

### Step 5 — Improve attribution through a qualified local provider

**Progress: source review and provider design complete; installation/evaluation/
production integration not started.** Owner
[#127](https://github.com/kellyjanderson/readaloud/issues/127),
[ACD-A2](https://github.com/kellyjanderson/readaloud/issues/124#acd-a2--local-attribution-provider-boundary-and-modernbooknlp-gate).
Build the bounded data-only interface and isolated pinned runtime; application
acquisition owns all QA/encoder/entity/spaCy assets. Qualify CPU and actual Apple
acceleration rather than assuming MPS compatibility. Compare repaired heuristics
and ModernBookNLP against fixed public/City labels, accuracy and abstention/error
categories, startup and process-tree memory. Integrate a qualifying provider into
production with future-span refinement and explicit corrections preserved. If it
fails, publish the measured alternative/next action; a failed experiment does not
close the user's attribution-quality goal. Result: better attribution justified
by local evidence. Fish scenes do not wait for this optional provider to qualify.

### Step 6 — Native Fish scenes, shared voice resources and real speed controls

**Progress: single-reference synthesis, binding infrastructure and exact-model
adjustment guards exist; native scene integration, shared reference-set reuse and
effective speed behavior remain open.** Owner #111,
[ACD-S1](https://github.com/kellyjanderson/readaloud/issues/111#acd-s1--portable-speech-scenes-with-native-fish-realization).
Complete typed capability/descriptor interfaces with Step 7; implement bounded
turns, stable speaker/reference mappings, prepared conditioning, continuation
identity and ordered audio pieces. Keep Fish tags/KV/codec/prompt rules inside its
adapter, encode literal control-looking prose safely, and retain truthful alignment.
Preserve canonical directions and #120 exact-model scopes; test a second engine
through the same structures. Qualify at least five installed, previewable, distinct
usable choices per character on the English fiction fixtures and repeated narrator/A/B/A identity without model reload.
Implement actual listening tempo and truthful matching export semantics as defined
in the R11 supplement, including duration, pitch, seek/highlight and cache identity.
Do not constrain Fish's native format to simplify a validator. Exit includes measured
reference reuse, complete endings and second-engine benefit. Result: efficient,
consistent character voices with controls that actually affect speech.

### Step 7 — Finish live model variants, reusable downloads and feedback

**Progress: variants/live replacement, local-first acquisition and measured
Activity UI partly implemented; complete transition/hardware/UI acceptance open.**
Owners #112/#119, [ACD-M1](https://github.com/kellyjanderson/readaloud/issues/112#acd-m1--verified-model-assets-and-live-engine-sessions)
and [ACD-F1](https://github.com/kellyjanderson/readaloud/issues/119#acd-f1--truthful-operation-state-and-quiet-reader-feedback).
One catalog drives UI/factory/download/probes. Preserve saved aliases and Voxtral
full/4-bit semantics. Add validated data refresh, complete snapshot integrity,
explicit acquisition Cancel/Resume, size/space visibility and failure recovery.
Prove no completed-file retransfers across dev builds and supported app identities.
Finish selected-versus-active/latest-wins transitions and A/B/A, rapid A/B/C during
all operation types without app restart/rebuild or overlapping large children.
Choose quality within 100 GB total runtime and measured physical headroom; compare
matched variants and qualify the actual M3 before claiming support. Preserve quiet
inline summary, stable layout, optional bounded Activity, fading completion,
recoverable errors and honest units/terminal/wait states with no infinite bars.
Result: installed models and voices remain reusable while the UI clearly reports
what the app is doing. Descriptor work may precede Step 6; final switching follows it.

### Step 8 — Consolidate the specific duplicated implementations

**Progress: detailed inventory and design complete; remaining extractions not
started. Some common infrastructure already exists and is retained.** Owner #114,
[ACD-D1](https://github.com/kellyjanderson/readaloud/issues/114#acd-d1--consolidation-through-narrow-shared-contracts).
C01/C02 are implemented once by Steps 3/6/7. Separate changes handle C03 RIFF/PCM;
C04 DOCX→EPUB→HTML/text events with richer metadata/mapping preserved; C05 document
envelope encoding after Step 4; C07 production-backed model/voice probes and shared
headless setup after Step 6/7 contracts. C06 traversal, C08 lifecycle mechanics and
C09 bookmark helpers require a documented net-benefit decision, not compulsory
abstraction. Evaluate listed package candidates against actual removed code,
streaming memory, native/offline packaging and notices; retain existing maintained
libraries and separate persistence roles. Exit: removed duplicates with equivalent
or richer behavior and appropriate native evidence. Result: fewer places to fix a
bug without a broad rewrite or delaying the first Drama proof.

### Step 9 — Finish presentation and streamline agent work

**Progress: repository navigation/layout, versioned designs and relevant skill
storage changes completed; public presentation, old-issue reconciliation and
measured instruction reduction remain partial/planned.** Owners #115/#116,
[ACD-P1](https://github.com/kellyjanderson/readaloud/issues/115#acd-p1--one-maintained-repository-and-distribution-entry-path)
and [ACD-G1](https://github.com/kellyjanderson/readaloud/issues/116#acd-g1--directed-agent-entry-and-conditional-orchestration).
Reconcile current architecture/setup/model support and actual main-versus-candidate
claims; update factual About/topics/homepage and cleared media. Triage still-open
#49–#53/#63 against evidence; PR #64's release workflow is already merged.
Keep Actions disabled. Separately reduce duplicated mandatory context, move
orchestration detail behind conditional routing, preserve a rule-survival map and
retire managed stubs only through SkillsKeeper with unique rules retained.
Keep thin routes and unrelated global research roles; no project custom-agent
rewrite is justified. Measure a real directed task/re-entry and authorized
independent-work scenario when available. Result: trustworthy onboarding and less
agent overhead, with no invented savings or lost acceptance rules.

### Step 10 — Qualify, reconcile and release the actual product

**Progress: release coordination and earlier source/package tooling exist; final
candidate, native/human acceptance and publication are not complete.** Owner #122,
with #83/#91/#55 and each feature's evidence. Freeze the exact candidate; reuse
unchanged valid receipts and rerun affected/missing checks locally. Qualify installed
runtime/onboarding, City ending/voices, five-prose oracles, actual `.radoc` reuse,
downloads/switches/rate/export, error recovery, large-document EOF, keyboard/UI,
memory and normal Quit. Preserve #83's ten-launch-per-case external-launch timing
matrix, <=2,000 ms every valid trial and separate proposed UI budgets; no shifted
clock or quiet waiver for cold model initialization. Run 30-minute real live speech
with zero unintended underruns under normal documented load, plus explicit
slowdown recovery. Engineering fixes precede the final concise human listening session.
Reconcile actual architecture/docs and complete shipped component/native/runtime/
model/reference-voice notices in repo, app and package; project license and
redistribution decisions remain explicit. Actual M3 evidence is required for an M3
claim. With required release authorization, merge stable PR, build/validate actual
main artifacts and publish a new immutable tag/release. Result: an identifiable,
reproducible app whose advertised behavior has evidence. No release authorization
is added by this plan.

### Dependencies and completion accounting

Critical path remains `0 → 1 → 2 → 3 → 4 → 6 → 7 → 10`. Step 5 follows stable
A1/C1 interfaces but does not block Fish on neural promotion. Step 8 follows the
short Drama baseline and its schema/protocol dependencies; Step 9 is bounded
independent work. A remaining attribution-quality requirement cannot be closed
by a failed provider experiment; record/reconcile the next candidate or approach.

Keep native edges: #126 ← #125; #127 ← #125/#126; #111 ← #113/#125/#126;
#112 ← #113; #114 ← #111/#126. They govern final integration, not a prohibition on
earlier partial checkpoints. No new agents/slices are dispatched by R11.
At dispatch record the actual fetched base, branch/worktree/target, exclusive
files, design revision, available model/effort, tests and return contract.

Every coverage row closes with code/preservation/acceptance evidence or explicit
conditional disposition. Each slice reports passed/failed/blocked/not-run separately
and updates its named architecture pages. No source test is native proof; no native
PCM metric alone is human acceptance. This frozen progress assessment does not
replace Project Status; current credentials still lack Project-board scope.
Do not infer a percentage from completed documents, tests, issues or matrix rows.
The next code task remains #125; this turn is coverage/plan work only.
