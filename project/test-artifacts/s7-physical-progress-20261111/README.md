# Physical-head and runtime-progress diagnostic evidence

Refs #142/#144 under #112, ACD-M1 R1 and #110 R23/R25. Immutable
November 11 records; these do not establish final slice acceptance.

| Case | Native / UI maximum | Full-waveform observation | Result |
| --- | --- | --- | --- |
| v43 4bit physical-head, native b9eabb4 / Dart 9abcb92 | 493 / 4ms | 173 references,55.434s in both captures; min .993924, max join .003968ms | Startup native failure |
| v44 8bit same candidate | 225 / 3ms | 170 references,54.152s in both; min .994344, max join .003968ms | Diagnostic criteria met |
| v45 4bit physical-head plus progress coalescer adcece7 | 157 / 3ms | Primary capture 55.366s, min .996291, max join .003968ms | Primary criteria met; secondary capture failed |

Physical-head ownership remains an off-by-default QA flag; normal rewind,
history pruning and inference scheduling remain enabled. These runs stop with
Pause and provide no natural final-EOF proof. All requested normal Quit and
verified owned-process exit, no orphans and wake-guard exit. Foreground samples
are recorded in receipts; do not infer sustained foreground use from them.

V43's first 2.2 seconds emitted192 state events,186 during runtime-native
verification. Coalescing same-stage progress to at most10Hz, while preserving
real counts, stage/reset/final publication and attempt cancellation, reduced
v45's first2.2s to10 events. V45 uses a fresh QA resource path and runtime
bundle identity, hence a fresh verified runtime extraction. This is one
cold diagnostic, not proof that all startup/native delays are fixed.

V45's independent CoreAudio capture failed with TranslatePID !obj before
registration; it provides no secondary audio credit. Commit2e3777c retries only
that transient status for the exact live PID within the existing deadline.
The retained no-audio-process negative test times out without a tap or frames;
it observed zero !obj retries and therefore does not exercise that error branch.
It must not be reported as a passing !obj regression test.

Independent review found a stale same-item seek/load completion and pending
final completion without a later head KVO. Native finite-EOF correction79fa0b9
is not in v43-v45. The retained old-source and mutant fixtures fail as intended;
the corrected fixture suite passes. These are native callback/ownership checks,
not audible playback proof. The QA path requires numeric positive finite
media (the local WAV route); generic streaming media is not qualified.

Receipts are compact JSON; original private audio/receipt/log hashes are in the
inventory. No WAVs or weights are committed. Earlier failed controls remain in
s7-boundary-20261111 and s7-m5-r3-20261111. No M3, listening, physical-speaker,
release integration or publication claim.
