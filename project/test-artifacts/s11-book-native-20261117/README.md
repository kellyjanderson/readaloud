# Saved-book voice edit and model handoff evidence

November 17, 2026 Pacific. Refs #152, #110 R23/R25 and release #122.
Exact source `18df8cc3dfbfd6361b91639df4047a480abe93f1`, ordinary
`lib/main.dart`, arm64 QA build `225d0393-e3a4-4771-8328-6d4d02244a7a`,
bundle SHA-256 `038ee4de19df4d28e0f17e8e5c157dcbf4d3babfbd0933f2cf1a4e00661fa7ca`.
Host: Apple M5 Max / 128 GiB. Synthetic public `test/fixtures/s3_dialogue.txt`
only; no private manuscript or recording is committed.

A new isolated profile was absent at preflight, before launch. Fish 4-bit
acquisition, truthful cancellation and normal Quit/app+child exit were observed.
Complete independent model/voice cache leaves were then staged; fresh partials
were preserved. These later cases are warm functional tests, not cold acquisition
or startup acceptance.

With Fish 4-bit initially active, a legacy Fish 8-bit book was opened before
any playback. Mara changed from Freya to Adrian. One Play emitted all 42 words
in seven complete waveforms, minimum correlation 0.998535 at native 48 kHz.
The complete 0–8 opening preceded a **26.388896-second model handoff wait**.
This proves ordered coverage and consumption ownership, not uninterrupted
continuity across the model switch. Only Mara raw spans 8–15 and 26–30 changed;
all five unrelated raw hashes remained identical. Changed final derivatives
8, 26 and 30 are within accepted S6 R1 boundary scope 8/15/26/30; reprocessing
15 produced identical bytes. See [legacy-edit.json](legacy-edit.json).

The edited book was saved, normally quit and restored. No speech worker was
observed before, during or after Play. Its complete 15.172188-second, seven-scene
reference matches emitted output at 0.998301993; natural EOF and normal Quit/app
exit were verified. See [edited-reopen.json](edited-reopen.json).

A fresh native source was assigned narrator Adrian, Mara Freya and Mira Hannah.
All seven finalized playback scenes contain canonical turns and captured bindings
for Fish 8-bit. See [fresh-canonical.json](fresh-canonical.json). Opening that new
book and changing Mara to Adrian regenerated only raw spans 8 and 26; five other
raw and final WAVs remained identical. All seven complete waveforms matched the
capture in order, with no external join gap/overlap at 48 kHz and minimum full
correlation 0.993829155. See [fresh-edit.json](fresh-edit.json). These are emitted
waveform/metadata checks, not semantic voice quality or listening judgments.

All captures have finalized exact-PID CoreAudio process-tap integrity checks and
zero loss/discontinuity counters. Initial 12 kHz diagnostics could not establish
two short scene matches; native-rate comparisons retain the 0.98 threshold and
provide the reported results. The tap measures software output; physical output,
M3, human listening/usability and startup limits remain separate. All test apps
and owned workers were normally quit and their exits verified.

The fresh source also exposed that **Save Audio alone omits scene publication**:
its WAV has seven chunks, but immediate Save Audio Book has zero scenes; playback
then populates the book. This pre-existing export-request wiring gap remains a
bounded S6 R1 repair, not a passed gate in this receipt. The final candidate must
include and qualify that repair before handoff. Human acceptance, the two-second
launch goal miss and seven distribution blockers remain open.

[Durable native checkpoint](https://github.com/kellyjanderson/readaloud/issues/152#issuecomment-6966587486).
Raw local evidence: `/Users/k/.codex/worktrees/s11-book-qualified/readaloud/tmp/s11/`.
No Actions, paid execution, target/main merge, publication or acceptance waiver.
