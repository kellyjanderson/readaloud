# S7 R25 scheduling differential — November 11, 2026

Refs #112 / #144, parent #110 R25, release #122. Framework source `28f42f7`,
entrypoint `tools/s6_acceptance_smoke.dart`; runner `fe32bd9`.
The signed isolated arm64 QA app uses managed pinned assets offline and the
existing memory admission policy. Every run uses a fresh private target raw
store and the same independently counted 197-word source. OS/model caches are
retained. The quantized engine produced six scenes, so this is not the old
four-scene full-precision fixture's synthesis output.

| Case | Startup, separate | Document load to emitted speech | Native maximum | Waveforms | Overall |
| --- | ---: | ---: | ---: | --- | --- |
| v34 bf16 utility | No completed boundary | Not measured | 111ms | None | Failed headroom admission |
| v35 8bit utility | 8009.347ms | 6800.774ms | 229ms | All6, minimum correlation .999858, max positive join0ms | Diagnostic false |
| v36 8bit default | 4903.119ms | 3547.286ms | 601ms | All6, minimum correlation .999854, max positive join0ms | Native failure |

Both measured cases meet the unchanged 10000ms first-load hard limit, excluding
startup. Both miss the separate 2000ms launch-to-speech goal:14810.220ms utility
and8450.501ms default. All target-triggered preparation remains on the document
load clock; target synthesis/native sources before that boundary are zero.
Native and captured timing use CLOCK_MONOTONIC_RAW. Capture onset aligns with
the first expected waveform within0.011ms. This is an app-emitted upper bound,
not physical speaker onset or listening proof.

V35 native functional checks passed and all837 replies observed the app active.
V36 completed functionally but failed at300ms during ordinary startup and601ms
during playing; UI heartbeat maximum9ms. These trials are single sequential
cases with uncontrolled OS cache/scheduling state, not a causal policy study.
Production policy remains unchanged. The QA utility runner deliberately forces
its overall verdict false; the standard timing summary retains that false
verdict instead of presenting a qualification pass. Its generic native/cleanup
error does not mean cleanup failed: both cases quit normally, verified exact
owned exit, and left no processes. The wrapper's temporary wake guards exited.

V34 refused the full-precision model under the unchanged measured headroom /
95GB admission budget before target loading. No model load timing or acoustic
credit is taken. Its temporary QA-only alias was created only when absent,
pointed to an existing read-only model folder, and was removed after normal
Quit. No model bytes were changed and no memory guard was bypassed.

`runner-validation.rb` reproduces eight mocked process/argument/verdict checks
without launching an app. Ruby syntax and scoped diff checks passed. Private
WAV/log identities are in `private-artifact-inventory.json`; media and model
weights are not copied into Git. The input adapter maps each actual completed
scene extent/path to the maintained full-waveform comparator. Its generic join
allowance is not used to weaken S7's10ms gate: both observed maximum gaps are0ms.

#142 audio holes and #144 native-main stalls remain open. S8 also reproduced a
434ms no-inference delay; inference policy alone cannot be presumed its cause.
No physical M3, human listening, release packaging, merge or publication proof.
