# Native Play position snapshot verification

Refs #144/#142/#112 under ACD-M1 R1 and parent #110 R23/R25.
Production change: S8 7624064 / S7 f034e8a (worker 7af15c0).
Full arm64 native rebuild UUID A2AEA678-A052-374F-A43E-9B07F802B20B;
the tested bundle is isolated as mlxPlaybackTest. This is not an installed release.

The matched V72 native wait is AVPlayerItem.currentTime through the production
position reader called by Play after rate activation. The sampled boundaries
bracket a 237.243ms request wait; they do not prove one continuous lock or its
owner. The separate V63 CoreAnimation wait is not this stack. Selected GPU work
has no similarly long individual kernel or native mutex dependency edge.
The sanitized GPU review preserves these limits; raw traces/ENV remain private.

The patch samples the existing real paused/pending-seek position before rate
activation only for macOS finite-local-WAV opt-in, loop-off playback. No fake
position, scheduler, timer, offload or GPU/model policy is added. Generic players,
other platforms and both loops retain their legacy order. Existing callbacks
can still query position; this is not a universal AVFoundation latency guarantee.

| Exact candidate | Native maximum / active samples | Result |
| --- | --- | --- |
| V73 8bit, CoreAudio primary | 45ms /721of721 | Strict bounded warm waveform/runtime pass |
| V74 4bit, ScreenCaptureKit | 178ms /671of671 | Strict waveform/runtime pass; retained8→7 snapshot anomaly |
| V75 A8/B4/A8, CoreAudio | 30ms /321of321 | Strict switches waveform/runtime and rapid-latest pass |
| V76 natural book | 66ms /39of781 | Functional/timing/six-waveform pass; no foreground responsiveness qualification |
| V77 foreground natural book | 30ms /752of752 | All197 words, natural EOF, complete save and six full waveform matches |
| V78 model-forbidden replay | 66ms /718of718 | Zero model calls, all197 words, Save/reopen/cancel/restart and six waveform matches |
| V79 extended CoreAudio | 48ms /1864of1865 | Native/input component pass; first callback26.076ms after firstPosition, capture coverage refused |
| V80 extended ScreenCaptureKit | 227ms /1873of1875 |180s playback;162.338s complete audible references, min.99589/maxjoin.00546ms; diagnostic flag retains overallfalse |

All three cases verified normal Quit, one MLX child and no owned orphans.
Full reference/context and active correlation, join, source order, pause-tail,
foreground and 250ms gates remain unchanged. CoreAudio primary qualifies only
bounded warm intended-source coverage: Play-to-tap remains unobserved and gives
no first-emitted-audio, full-session or earlier-prefix/replay exclusion claim.

All subsequent app cases also verified normal Quit, capture/guard exit and no
owned orphans. V77/V78 match all six scene waveforms with joins≤.01ms. First
load-to-speech upper bound2099.705ms excludes separately measured4218.100ms
ordinary startup; total6317.906ms misses the2s goal but meets10s load hard limit.
Reusable load525.851ms/startup275.554ms/total801.514ms meets5s hard limit and
launch goal. V76 retains a colder9355.749ms startup/2229.178ms load/11585.038ms
total; installed model/OS caches are disclosed, and target raw-audio stores are
fresh. No target work is moved before the load boundary.

V79 actual pointer input opened Activity with its saved-scene result; the first
Tab/Return attempt did not toggle Activity and receives no such credit.
Shift-Tab/Return collapsed it and a second Return reopened it while Pause stayed
visible during the reading session. This verifies functional keyboard disclosure,
not individual key latency or exact GPU-inference overlap. Its first26.076ms
coverage deficit is retained, never prefix-qualified. V80 uses the pre-Play
ScreenCaptureKit gate for complete long-run coverage; its original180s diagnostic
flag deliberately prevents an overall qualification verdict. Standard V73–V75
remain the strict passes. No thresholds or missing intervals were waived.

The full native fixture suite passes. Exact base a721106 fails the bounded
startup-clock-lock control through real AudioPlayer.updatePosition,
getCurrentPosition and UriAudioSource.position. Initial/nonzero resume,
outstanding seek, duplicate Play/results and opt-in/loop isolation are covered.
Native control logs and replay commands are retained. Independent Sol/high
source/evidence review found no actionable correctness defect; it ran no apps
or tests and did not waive acceptance.

This record does not establish physical speaker output, human listening, M3,
arbitrary-document performance, release integration or publication. Earlier
failed controls remain in s7-final-native-20261111 and prior artifact records.
