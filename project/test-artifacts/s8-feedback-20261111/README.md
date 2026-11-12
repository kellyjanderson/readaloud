# S8 source and native evidence — November 11, 2026

Refs #119 / ACD-F1 R1, parent #110 R23/R25, dependency #112 / #139.
Production source candidate `3cb2a26`; dedicated signed arm64 QA host
`com.kellyjanderson.readAloud.feedbackTest`; runner `ba526b3`.
PR #145 targets `codex/model-lifecycle-s7`, then #139 targets
`codex/fish-expressive-continuity`. Unmerged and unreleased.

Final source suite: **1,109 passed, 4 optional skips**. Scoped Flutter analysis
passed. Arm64 Flutter Assemble succeeded; raw build logs remain private because
they include environment data. The UI-only entrypoint uses the actual app,
controller, prepared input and text-only package Save with inert speech engines.
The counter fixture writes and validates actual bounded private local files;
it does not represent a model download or upstream deep-analysis producer.

`native-v3/cua-observations.json` records coordinator observations independently
of controller assertions. All nine functional gates completed: native keyboard
Activity disclosure and focus, window zoom/restore with local 2x text, unknown
total, measured 48%, counted-but-finalizing, terminal success, actual Copy,
Clear error retaining history, and successful real Save retry. Clipboard content
was checked by the probe only after actual native Copy. Local reduced motion
does not establish OS preference behavior or timed expiration acceptance.

**Native v3 failed overall:** native-main maximum **434ms > 250ms**; UI timer
maximum25ms, zero speech requests. No threshold was relaxed. This overlaps open
#144, including a stall without MLX inference. Functional evidence does not
waive responsiveness. Normal Quit succeeded, exact app exit was verified,
owners drained, no processes remained and the temporary wake guard exited.
LaunchServices owns the app exit status; a null value is not a synthetic zero.

Failed controls are retained: v1/v2 direct execution could not attach native
CUA. V1 stopped before useful UI checks. V2 released early gates as backend-only
diagnostics, never performed native Copy and reached its deadline. Neither has
UI acceptance credit or a normal-Quit pass. V3 normal LaunchServices startup
enabled actual native input; this does not prove the cause of every old timeout.

No emitted-audio, physical speaker, human listening/usability, physical M3,
release packaging or integrated release acceptance is claimed. Human cases are
collected for S11. #119 remains open until responsiveness and integration gates
are satisfied. Actions and paid execution were not run.

## QA frame-pressure control

Read-only review found a QA-only20ms `scheduleFrame()` call absent from
production and the S7/R25 heartbeat probes. Maintained Flutter draw/composite
and native presentation sources support extra presentation opportunities, not
one native commit per request or a demonstrated cause of434ms.
Source `9e5cd3b` adds an explicit runtime flag around that call only, preserving
the default,20ms timer,100ms single-flight native probe and250ms threshold.

Natural-frame v4 completed all9 actual gates: native maximum184ms across2913
active-app replies, UI timer gap24ms,14592timer ticks, zero forced frame requests
and zero speech requests. Duration291.855s. Normal Quit, owner drain, exact exit,
no force/no orphans and wake-guard exit verified. Controller/native receipttrue;
runner overallfalse deliberately labels this QA differential. This is a bounded
natural-frame pass, not a production scheduling remedy. Native keyboard toggles
were observed after coordinate content focus; earlier no-change Tab/Return calls
have no activation credit. CUA intervals are retained in `frame-off-v4`.

The same-source forced counterpart v5 was **confounded and stopped**. Notices
navigation appeared during the Ready dwell without a coordinator navigation
action; later CUA reported user interaction and Play reached the inert engine.
The fixture is intentionally silent. Partial counter/Copy observations cannot
substitute for a final controller receipt. Root interrupted only its runner;
normal Quit and exact app exit/no force/no orphans/wake-guard cleanup passed.
There is no valid matched A/B result or forced-frame causal conclusion. The
default probe remains unchanged. Initial CUA focus/AX staleness and the
uncontrolled navigation are explicitly retained, rather than called app bugs.

S7's default-policy601ms failure remains independent. S8 has implementation,
source and bounded native functional evidence, but shared responsiveness and
dependency integration/reconciliation remain open. No threshold was relaxed.

## Combined dependency source check

Merge `b5340fa` brings declared S7 dependency `bd52661` into the S8 branch;
this is dependency synchronization, not integration into the feature/release.
The combined full suite passed **1109 tests /4 optional skips**; scoped analysis
of lib/test and affected native QA entrypoints was clean. Both Ruby runners
passed syntax checks, and the archived eight mocked first-load runner checks
passed again. The natural-frame native candidate remains `9e5cd3b` (before this
QA/tooling dependency merge); no exact-final-commit native or release claim is
substituted for it. No test app remains running.
