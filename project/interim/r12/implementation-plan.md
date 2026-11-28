## Implementation plan R12

November 4, 2026 Pacific, baseline `00e437d`. This replaces R11's sequence of
separate attribution repair, character persistence and provider projects with one
character contract and incremental end-to-end delivery. It does not delete any of
the [89 reviewed obligations](https://github.com/kellyjanderson/readaloud/issues/110#review-coverage-r11)
or [acceptance requirements](https://github.com/kellyjanderson/readaloud/issues/110#review-acceptance-supplement-r11).
Those fixed records retain their original evidence assessment; the mapping below
assigns them to the consolidated units. Current execution remains in GitHub.

### What changes in the plan

- Define one persistent `Character` aggregate exposing selected voice,
  explicit/implicit/presented gender, evidence-backed facts and speech profile.
  [Character contract R2](https://github.com/kellyjanderson/readaloud/issues/124#character-contract-r2)
  supersedes the former separate canonical character/voice-map shape.
- Both attribution providers produce typed evidence/deltas for that aggregate.
  They do not own character persistence, UI cast state or voice assignment.
- Keep the reproduced continuity failure as a shared regression; stop requiring
  a standalone heuristic improvement project before the persistent type exists.
  Implement only a minimal fallback/blocker repair when needed for the working slice.
- Build and qualify the current/Fish path as soon as a small character/voice slice
  works. Do not wait for every attribute or ModernBookNLP qualification.
- Integrate concurrency, descriptor and feedback changes where those boundaries
  are touched. Record their broader stress qualification once; do not redo it
  under each feature heading. Likewise, source/native feature proof is reused by
  final release acceptance unless integration or changed conditions require reruns.

### A — One character model, one attribution boundary, one persistence migration

**Progress: design revised; existing cast/evidence/voice-choice parts are available,
but the unified type and migration are not implemented.** Owner #124; #126 leads
the contract/migration, #125 the common attribution adapter/regressions, #127 the
neural provider. These are coordinated parts of one outcome, not three serial
replacement projects.

First define the typed aggregate and minimal data-only analysis delta. Migrate
current cast evidence and exact-source choices/Reset; expose compatibility views
to existing consumers while moving write ownership to the aggregate. Prove one
character's selection and distinct gender evidence across reopen before widening
the fixture. Route heuristic output into the same merge boundary and add the known
split/whole regression. Only repair legacy continuity needed for the supported
fallback; avoid speculative heuristic expansion that ModernBookNLP would replace.

Evaluate and integrate a qualifying local provider using the same output schema,
source coordinates, entity reconciliation and independent oracle. Provider changes
cannot overwrite explicit voice choices or require another storage/UI migration.
A failed candidate needs a measured follow-up decision, not closure of the user's
attribution-quality goal. Keep the minimal character/Fish path moving independently.

### B — Complete audible Fish reading through that model

**Progress: current adapter, native formats and complete-output repairs exist;
new scene/binding integration and complete native acceptance are open.** Owner #111.
Use the installed valid snapshot and the smallest working A slice, with explicit
manual assignments if automatic analysis is not yet qualified. Establish the
short City passage/ending through the existing player immediately, fixing blocking
runtime defects in place rather than waiting for a separate general refactor.

Then derive reference bindings/scenes from the same Character selections, reuse
resident prepared references, preserve canonical/model-specific directions and
prove narrator/A/B/A plus at least five usable voices per character. Fish slots
remain scene-local; selected voices and character IDs persist. Add truthful piece
alignment, literal-tag handling, effective listening/export speed and demonstrate
a second engine using the same contract. Keep native sample rates. The short
audible checkpoint and richer scenes are iterations of this one delivery unit.

### C — Finish shared runtime/model operation and qualify it once

**Progress: cancellation/session/download/progress fixes partly implemented;
bounded planning and full stress/hardware proof remain open.** Owners #113/#112/#119.
Land the specific queue, lease, shutdown, catalog or progress fix needed by A/B at
its affected boundary. Do not implement a second model manager or schedule an
independent neutral-engine rewrite of code just changed for Fish.

Complete bounded demand, session/resource lifetime, exact identity and resumable
download controls, selected/active transitions, saved preference compatibility,
quiet truthful feedback and quality-first memory admission. One combined native
matrix covers playback/preview/export, cancel/retry/seek, A/B/A and rapid A/B/C,
offline rebuild reuse, shutdown and actual M5/M3 memory/continuity. Share those
receipts with A/B and release qualification. Unknown M3 hardware and measured
startup limits remain explicit gates. This unit is partly interleaved with B,
not a command to postpone the first audible Fish result.

### D — Remove the remaining specific duplication

**Progress: inventory/design completed; remaining extractions are unstarted or
conditional.** Owner #114. Catalog/session/character ownership consolidated during
A–C is not implemented again here. Remaining C03 RIFF, C04 import adapters, C05
document-envelope overhead and C07 production-backed probes land as small changes
against the resulting contracts. C06/C08/C09 require explicit net-benefit decisions.
Retain libraries and richer import/audio behavior; no generic framework rewrite.

### E — Finish presentation and agent instructions

**Progress: branch/file cleanup, launcher and versioned design storage complete;
remaining public documentation and measured instruction reduction open.** Owners
#115/#116. Update actual-build support claims/media/onboarding and reconcile old
issues. Reduce repeated directives/templates with the rule-survival map; retain
managed skill authority and unrelated global roles. No repeat repository cleanup
or new local progress ledger. This work does not gate first Fish playback.

### F — Final integrated acceptance and release

**Progress: coordination/tooling and prior source receipts exist; final candidate,
native/human acceptance and publication remain open.** Owner #122/#83/#91/#55.
Reuse exact-build compatible feature evidence from A–E, then test integration and
packaging risks and remaining gates: external-launch timing, normal-load 30-minute
continuity, persisted work/.radoc, true native voice/rate behavior, real hardware,
full notices and the final human session. Rerun only changed or missing checks;
do not restart every earlier qualification from scratch without a reason.
Reconcile implemented architecture and retire interim documents through their
published lifecycle. Main/tag/release publication still requires authorization.

### Mapping of all R11 steps and review obligations

| Earlier step | New owner/unit | Disposition |
| --- | --- | --- |
| 0 foundation | Completed baseline | Preserve; no new task. |
| 1 attribution repair | A / #125 with #126 | Shared provider oracle/adapter plus minimal necessary fallback repair; standalone heuristic campaign removed. |
| 2 short Drama checkpoint | B / #111 | First end-to-end iteration, not a separate implementation to replace later. |
| 3 concurrency | C, interleaved with B | Existing owner fixes once, combined stress matrix. |
| 4 persistent characters | A / #126 | Unified aggregate and one migration, not a separate voice store. |
| 5 neural provider | A / #127 | Replaceable provider implementation against the same type, evidence merge and tests. |
| 6 native scenes/shared voices/rate | B / #111 | Continue the same character-to-speech path. |
| 7 models/downloads/feedback | C / #112/#119 | One catalog/session/operation contract and combined qualification. |
| 8 specific duplication | D / #114 | Only duplication remaining after A–C; all conditional findings retain explicit disposition. |
| 9 presentation/agent entry | E / #115/#116 | Finish only remaining work. |
| 10 release | F / #122 | Integrate/reuse feature evidence; close remaining acceptance. |

The 89-row R11 coverage map remains the requirement index: substitute the unit
above for its old step number. No review point is waived. The R11 rate, prompt,
shutdown, migration, gender-evidence, timing/prose/continuity and notices supplement
remains in force except where Character contract R2 explicitly replaces ownership
or sequencing. Historical fixed files remain intact.

### Execution and dependency correction

The first implementation work is the **minimal Character contract/migration slice
in #126**, coordinated with the shared oracle in #125, followed immediately by a
small B native path. #126 no longer waits for a standalone heuristic fix. Final
integration of #125 and #127 depends on #126's shared contract; writing the oracle
can begin beforehand. #111 final scene integration depends on #126 and #113, not
completion of #125 or #127; manual/explicit cast input can prove synthesis while
automatic attribution is being qualified. Full automatic attribution remains an
A/F acceptance requirement. #112 depends on #113; #114 on #111/#126 as before.

No current workers are dispatched by this revision. Preserve one checkout writer
and coordinate shared model/controller files before implementation. Fresh dispatch
still records exact base/target, ownership, checks and return contract. Current
Project status is not inferred from these frozen progress descriptions. No product
implementation, app run, model download or new acceptance pass is claimed here.
