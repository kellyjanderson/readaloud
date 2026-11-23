# S9–S11 source engineering evidence

November 13, 2026 Pacific. Refs #114/#146/#148/#149/#151, S10 #150 and
final qualification #152/#153 under #110 R23/R25 and release #122.
This is source/tool evidence, not native or human acceptance.

The combined source at `f621e21aa9d4528d0b82084e778fb18d70349cd4` passes
1,311 Flutter tests with four optional skips, application analysis (`lib test tools`),
26 protocol and 63 worker Python tests, notice tests (7/26 assertions), candidate
packaging tests (28/237) and bootstrap tests (7/26). Docs, JavaScript syntax and
diff checks pass. The worker suite retains an existing socket ResourceWarning.
A root-wide analyzer run also inspected independent vendored examples/tests
without their development dependencies and failed with 73 diagnostics; this is
recorded separately, not called a clean whole-workspace result.

Shared PCM consumers retain canonical/native-rate/channel/quantization policy;
inspection encoding omits PDF allocation and the JSON round trip. Headless
setup and production-backed probes retain their owner lifetimes. Import review
found added lookahead could gate first publication on EOF and valid omitted HTML
end tags could hit a depth refusal. `242c019` removes both pending layers,
retains terminal metadata without synthetic speech, and handles implicit closures.
Seven tests fail against the preceding implementation and pass after repair.
Focused independent verification cleared both findings. Protocol review's absolute
cache-link alias is repaired in `7dc44fe`; real APFS clone and symlink-preserving
copy fixtures prove accepted relative links keep source bytes independent.

S10's exact rule-survival map, natural input measurements and verified managed
source sync are in [#150 receipt](https://github.com/kellyjanderson/readaloud/issues/150#issuecomment-6849917153).
These observations do not establish billed-token or cost savings. C06/C08/C09
remain intentionally retained under the [conditional net-benefit decision](https://github.com/kellyjanderson/readaloud/issues/114#issuecomment-6849770393).
Notice integrity now covers 118 texts and 58 tracked assets while preserving
all seven distribution blockers; text/hash coverage is not legal clearance.

The machine reports a locked screen. No combined-source test app was launched;
native emitted/exported audio, responsiveness, clean candidate onboarding/runtime
reuse and long continuity are unrun. Human listening/usability is collected for
one final session through the candidate/fixture-gated runner. Physical M3 remains
unavailable and unqualified. Prior first-launch two-second-goal failure remains;
no new timing claim, release/main merge or publication is made here.

[source-checks.json](source-checks.json) records exact counts and hashes of local
raw logs retained under this worktree's ignored `tmp/s11/`. Subsequent documentation
and evidence-only commits do not change the tested application source. No Actions,
paid execution, model download or reference regeneration was used.
