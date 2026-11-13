# S7 M5 native controls and selective Retry evidence

These are bounded observations, including failed controls. The owning records
are [S7 #112](https://github.com/kellyjanderson/readaloud/issues/112),
[capture-content investigation #142](https://github.com/kellyjanderson/readaloud/issues/142),
[incomplete-cache repair #143](https://github.com/kellyjanderson/readaloud/issues/143)
and [native-main hangs #144](https://github.com/kellyjanderson/readaloud/issues/144).
No issue is accepted merely because a later run passes.

## Candidate and evidence identity

Candidate JSON files name exact source and signed framework/executable hashes.
The final-r5 family used `d20e8dc`; final-r6 used `729b442`; final-r8 used
`62652a4`; final-r9 used `ffd6d64`. Native Runner sources did not change between
the latter framework-only builds and their recorded full native build. The QA
app retains the isolated `mlxPlaybackTest` identity and signed R5 Python runtime
resources. This is not a distributable release artifact.

The extended v27 candidate is `2c622b9`; its candidate JSON records the signed
framework/executable hashes. The full source suite passed1,082 tests with four
optional skips (`final-r10-flutter-test.log`), and the post-cache-fix Python
suite passed122 tests (`final-r7-python.log`). Neither establishes native audio
acceptance. Changed-document local links and `git diff --check` passed.

WAVs, weights, app logs and raw Instruments traces remain private. The inventory
names and hashes local capture/log artifacts. Raw trace/TOC files can contain
environment metadata and must not be uploaded. Copied queued WAV metadata in
receipts identifies exact SHA, format, byte count and original/copied paths.

## What passed

The default full-precision v3 case passed 60-second native and strict waveform
checks. Rapid A/B/A v5 passed native and three-segment acoustic/quiet checks.
4bit v8 passed at native194ms/UI7ms, with56.1096 seconds of complete audible
reference waveforms, minimum correlation.99661 and maximum external timing
residual.004642ms. The v8 startup sample was instrumented and is retained;
do not infer general uninstrumented latency guarantees from it.

Independent exact-PID CoreAudio and ScreenCaptureKit recordings matched167
audible packets/53.1460 seconds in8bit v7 and175/56.1096 seconds in4bit v8.
No missing audible packets or >10ms joins occurred in those comparisons.
8bit v7 still failed its326ms native gate. Diagnostic comparison always reports
`passed=false`; matching both paths is not whole-case acceptance.

Actual Settings v16 on `ffd6d64` passed the complete runner/native case at35ms
native/UI3ms, one observed MLX child, normal Quit and no remaining owned PIDs.
Strict initial8bit, post-Retry4bit and returned8bit waveform/quiet checks passed.
The missing439,426,211-byte shard was fetched into its existing cache with exact
pinned SHA. Every other snapshot inode/size/mtime identity stayed unchanged.
The held original was restored and verified. Cancel in this fast case was
observed during post-transfer verification, not an incomplete network transfer.

V15 separately proves actual incomplete4.324GB transfer cancellation: the
completed blob was absent before the Settings click, selected4bit became
cancelled/no active with last-working8bit, double Cancel joined retirement,
and actual Settings Retry validated4bit. Its final returned8bit interval reached
the240s overall setup deadline, so the whole run remains FAILED. It does not
become a combined passing case with v16.

## Failed controls and interpretation

8bit/4bit v5 captured missing audible reference intervals even though immutable
WAVs were queued well ahead and native positions advanced. The full-waveform
diagnostic retains missing references and exact later timeline recovery; no
threshold was lowered. Queue/file ownership review found no proven lifetime
defect. Later dual-path matches do not establish the historical loss's cause.

Default v5 matched55.4027 seconds with no failed audible references but ended in
an unanchored source-silent tail. It remains failed; source silence has no
individual acoustic identity. Later warm probes wait at most two seconds after
their minimum60s interval for an identifiable audible Pause boundary. The strict
matching/end-coverage gates remain unchanged. These are warm reading probes,
not launch or document-load clock passes.

UIv9 exceeded its Retry setup limit while the old loader started a second
download. V11 was aborted after an invalid shared-codec fixture also affected
initial8bit; originals were restored. V12 timed out before measured download
progress. V14 completed its selective transfer before manual Cancel arrived.
V10 was a preflight rejection while a CUA-reopened blank probe process remained;
that process was subsequently normally quit and exit verified. These controls
are not product passes.

Native-main delays persist independently of Dart heartbeat: v13 observed715ms;
v20's841ms request overlaps an Instruments840.620ms main Hang. The native
entry-to-Dart-reply interval was77 microseconds; native handler execution was
not separately timed. CPU-only samples show CA/MediaToolbox
and AVPlayerItem notifications but do not identify the dominant wait. See the
sanitized timed audit and [timing research](../../research/s7-native-response-timing.md).
Late v17 samples cannot explain already-completed waits. Profiled cases remain
diagnostic even if their native counters pass. The250ms gate stays in force.

Extended v27 completed180 seconds with181.542 seconds of sampled native source
positions, one observed MLX child, normal Quit and no owned processes left.
It FAILED the native gate at351ms while active (Dart heartbeat13ms). All four
bounded live samplers exited successfully; instrumented diagnosis is explicitly
not qualification. The dual comparison matched508 full audible references in
both paths, with54 source-silent and102 unobserved references; no audible
reference was classified missing in this case. A diagnostic comparison's
`passed=false` remains unchanged even when all observed references match.

V28's timestamped waiting-thread trace retained Core Animation IPC/deferral
mutex wait stacks inside the delayed-request windows. The sanitized audit
distinguishes actual run-loop intervals from statistical sample attribution;
the exported `Running` labels do not invalidate the wait stacks. V28 FAILED
both responsiveness (363ms, UI3ms) and actual playback progression (34.744s
observed during180s requested), plus the emitted-signal check. Its waveform
diagnostic cannot meet the native-progress precondition;179 entries reported
unobserved must not be represented as a successful content comparison. Most
native samples observed an inactive app. Profilerexit0 and normal Quit/exit/
no-orphan cleanup passed. Production remains unchanged while the next replay
differential isolates per-item playback work from MLX.

The first prerecorded replay control v29 did not reach Play: ScreenCaptureKit
could not find the requested app/display and the capture-readiness gate timed
out. Normal Quit/no-orphan cleanup passed. A subsequent read-only CoreGraphics
query reported one online display, asleep, with the session screen locked.
This is a native-test prerequisite blocker, not evidence of a new audio defect.
The diagnostic harness was also corrected to initialize its native player
before waiting for capture frames; Play still waits for actual capture readiness.
That correction is source-analyzed/built, not a successful native rerun. Native
checks wait for the user to unlock; independent source work can continue.

After unlock, prerecorded packet v30 and joined v31 both completed at native
232/235ms and UI2ms, with normal Quit/no-orphan cleanup. Joined waveform and
runtime criteria met:168 full references/53.3659s, max join residual0.003968ms,
1.212s quiet tail at peak0. Packet v30 matched168 full references but FAILED its
final interrupted-source witness check; that control is not a paired pass.
The harness now records the actual current source immediately before Pause,
without weakening acoustic thresholds. This correction is not yet natively rerun.

QA-only macOS child scheduling trials retain the existing process/protocol/
memory owner and use the maintained taskpolicy facility. Background+utility v32
completed at native179ms/UI6ms and matched172 full audible references/55.0782s
in both captures. Utility-only v33 completed at native190ms/UI3ms and matched166
audible references in both captures. Neither observed missing references. Both
normally quit with one MLX child and no orphans. They remain diagnostic-only;
one pass per policy does not establish a fix. Most v33 samples were inactive,
whereas all751 v32 samples were active.

Model-load stages took9.904s (background+utility) and6.515s (utility-only), with
first-packet stages1.351/1.281s. These are source stages, not R25 launch/load
clock measurements. Startup impact and repeated full-precision/quantized/switch
checks are required before any adoption. Production policy stays unchanged.

The QA-only lazy-preparation comparison v23 still failed at690ms native delay.
It is not the production default or a completed fix. Both independent captures
have identical PCM over their acoustic overlap, including a199.3125ms exact-zero
hole replacing audible source in v23 and a21.0625ms hole in v17. Global searches
fail the unchanged0.98 full-reference threshold. Adjacent anchors retain timing;
gain or search-window placement does not explain the lost material. The v23
hole overlaps the delay; v17's does not overlap a logged delayed request. See
the sanitized dual-loss audit. This does not identify a producer or establish
physical-speaker output. Later passing cases do not erase these failures.

Physical M3 qualification,
physical-speaker evidence and human listening/usability remain separate. Human
tests are collected for S11. No Actions, paid execution or release publication
was used for these observations.
