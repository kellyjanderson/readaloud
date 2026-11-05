## Review acceptance supplement R11

This supplements the ten fixed ACD R1 documents; it does not rewrite their
published files or claim implementation. It makes review requirements explicit
where R10 compressed them into general capability, ownership or release language.
Baseline: `a2fdb4c`, November 4, 2026 Pacific. Source findings and owners are mapped
in [review coverage](https://github.com/kellyjanderson/readaloud/issues/110#review-coverage-r11).

### S1 supplement — effective speech rate and literal prompt text

Owner #111, Step 6; sources #114 correctness/library decisions and #111 minimum
change. Current `KokoroTtsEngine.setSpeechRate` stores the value and the MLX
artifact identity includes it, but the inspected MLX generation path does not
apply that rate and the player setter is not used. A changed cache key is not a
speed implementation. Drama's reviewed native API rejects non-default speed.

Separate three values/capabilities: requested reading rate, effective native
synthesis rate, and effective playback/export tempo. Native-rate control is used
only where the exact provider supports it. Otherwise implement listening tempo
with the retained platform player facility, with pitch/quality and position mapping
qualified; do not disable useful reading-speed functionality merely because Fish
has no native speed argument. Expose effective state, not a decorative slider.
Buffer lead uses real playable duration at that tempo. Pause/seek/follow-along and
voice changes must use the same time mapping without repeating or skipping text.

Export must state whether it uses the requested reading tempo or explicitly
selected original tempo. The default should match the requested reading tempo;
use a maintained, offline-capable pitch-preserving tempo facility when native
synthesis cannot do it. The implementation slice must select and qualify that
facility against current packaging/notices and streaming-memory requirements
before promising support. No custom resampler, WAV-header rate trick or forced
24-kHz conversion. If a requested export tempo cannot yet be rendered, return an
explicit recoverable unsupported operation rather than silently exporting normal
speed or claiming the feature complete. The unresolved export capability remains
an acceptance gap, not a reason to constrain native quality.

Cache raw speech by actual synthesis configuration; represent applied tempo in
derived artifacts/playback configuration. Include exact model/context/direction
identity; never create or reuse audio under a falsely claimed native rate.
Tests: at least normal/slower/faster supported settings, captured audible duration
and pitch/quality checks, exported decoded duration, correct seek/highlight/source
mapping, lead accounting and no stale result after rate change. Fake setter tests
alone cannot pass. Reconcile engine capability, playback and export architecture.

Before inserting Fish speaker/direction tokens, encode literal source text that
resembles those tokens through a tested adapter-only strategy supported by the
pinned tokenizer. Never trust manuscript text as prompt control. Synthetic cases
include literal speaker tags, bracket-like reference text and unsupported cues;
verify the intended words survive, controls are not spoken and original source
mapping/text remain unchanged. Bound scenes using the actual provider limits,
not advertised global speaker count. Revalidate or split reference sets without
changing stable work/character identity.

### R1 supplement — cancellation scope and complete shutdown budget

Owner #113, Step 3. Preserve the repaired startup/retirement paths; prove exact
operation ownership across playback, preview, export and model load. A playback
cancel revokes its lease/generation and cannot kill a different active export/load.
An engine switch is broader and visibly cancels/drains affected export before
replacing the shared owner. Keep non-preemptible native Kokoro work explicitly
quarantined/draining where immediate hard stop is impossible.

Name one application shutdown bridge. Allocate and instrument the entire close
budget across Dart invalidation/drain, child TERM/KILL/reap and native reply,
against the existing 12-second AppDelegate fallback. Do not assign each stage
the full budget or call completion merely because a closed flag was set. Repeated
close callers await the same real completion. Test delayed process start,
TERM-ignoring child, oversized/malformed reply, duplicate final, old child exit
after successor creation, timeout/reload attestation and quit during each stage.
Verify zero owned processes after normal Quit; report inability to reap as a
failure rather than starting an overlapping large model. Retain stage-specific
timeouts; network slowness alone is not fabricated success or arbitrary progress.

### M1/F1 supplement — compatibility and stable feedback

Owners #112/#119, Step 7. Explicitly migrate `voxtralQuantizationBits` 0/full and
4-bit meanings to descriptor identities, preserving stored engine aliases and
environment-override precedence. Unknown/incompatible choices are visible and
recoverable; no hidden model replacement. Show actual download size, available
space, active identity and cancel/resume. Model, voice, reference transcript,
codec, runtime, context and effective synthesis configuration determine reuse.

Preserve the reserved reader/transport/status layout during all transitions.
Activity has bounded scrolling and at most one current row per preparation stage;
completed stage presentation may fade without erasing durable errors. Keep row
identity revision-scoped, dispose timers/subscriptions and honor reduced motion.
Check parallel/resumed download callback accounting against actual completed
files/bytes, not the retired shared-map implementation. Source waiting, planning
cancel and model validation must all terminate/idle truthfully. A spinning bar
never substitutes for unknown totals, an outstanding producer or stalled work.

### C1/A2 supplement — evidence and promotion remain separate

Owner #126: preserve the #83 pronoun-first **automatic voice-matching hint** tests
while separately retaining explicitly stated identity, inferred identity and
contextual presentation. A hint must not overwrite a contrary stated fact.
Pronouns attach to the correct character; names/clothing/occupation are not
substitutes. Unknown/they-them, aliases and conflicts remain explicit. Test actual
voice assignment and reopen, not labels alone. Keep manual choice/Reset precedence.

Owner #127: evaluation is followed by production integration of a qualifying
provider through the same bounded interface, app-owned acquisition and persistent
work evidence. If the candidate fails, publish a measured alternative/next action;
do not close the attribution-improvement requirement merely because a benchmark
was run. Fish scenes can proceed with the repaired heuristic independently.

### Qualification supplement — retain the exact inherited acceptance

Owners #125/#126/#127 and #122/#83/#91. Reuse the existing independently reviewed
P0–P4 original-prose fixtures; identify any missing cases rather than generate a
duplicate corpus. Production input receives no oracle, roster or fixture metadata.
Expected narrator/speaker identities, not only counts, are checked through import,
normal voice-dialog UI and actual native intake/speech; named non-speakers and
held-out/rephrased variants are negative controls. P4 must begin speaking before
later speakers finish analysis, retaining earlier explicit choices.

Preserve #83's exact timing definition: external launch request → actual audible
output, with separate interactive-frame/Play/resource/PCM times, installed required
models, fresh-process/no-document-or-audio-cache, warm and valid `.radoc` cases,
short prose/tens of pages/full novel, ten launches per case and every valid trial
<=2,000 ms. Publish all failures, maxima and percentiles. First acquisition is
reported separately, never hidden; normal cold process initialization remains in
the measurement. The 100-ms input/stall budgets retain their stated proposed
engineering-threshold status, distinct from the user's mandatory two seconds.

At least 30 minutes of real speech under documented normal load must have zero
unintended underruns/restart loops and no observed audible stutter/click/cut, with
live emitted output and source sequence evidence. Deliberately unsustainable
slowdown tests recovery/position; it is not a successful continuity trial. Include
speed changes, seeking/cancellation, background persistence and warm reopen.
Engineering fixes and exact-build/package validation precede one concise human
session for residual cadence/voice/usability judgments. Do not substitute final
concatenated audio, synthetic tones or non-silent PCM for actual live continuity.

### Presentation and process supplement

Owner #115, Step 9: reconcile open #49–#53 and #63 against evidence. The initial
review mislabeled #63 as a PR; live verification found an open release-policy issue,
while PR #64 is already merged. Preserve the existing release workflow rather
than implementing it again. Update GitHub About/topics/homepage and cleared media
only with concrete supported-build facts; do not infer a license or manufacture
a site. Verify native ONNX Runtime and native audio-backend obligations separately
from their Dart wrappers, preserve applicable Kokoro NOTICE material, and use the
existing curated/lockfile-driven notice tooling's actual inventory. Keep component/native/runtime/model/reference-voice notices in repo,
in-app and distributed package under #55; existing notice tools are reused.

Owner #116, Step 9: preserve rule-survival mapping and actually comparable tasks.
The original review's independent/parallel re-entry check remains a conditional
validation scenario when such authorized work exists; do not create needless
agents to manufacture a metric. Managed skill storage/lifecycle changes already
completed are distinct from still-unimplemented instruction reduction.
