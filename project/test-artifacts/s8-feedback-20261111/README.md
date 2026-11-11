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
