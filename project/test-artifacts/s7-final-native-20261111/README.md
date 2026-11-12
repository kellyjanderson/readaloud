# Native, capture and natural-book evidence

Refs #112/#142/#144, ACD-M1 R1 and parent #110 R23/R25. Product sources
remain25936d4, including per-player finite local-WAV queue08d90fc and bounded
runtime progressadcece7. These are evidence receipts, not slice closure.

| Case | Native maximum / foreground samples | Result and limits |
| --- | --- | --- |
| v56 System Trace | 720ms /669of669 | Instrumented failure; tracer forced after20s finalization, unusable trace; normal app Quit passed |
| v57 CoreAudio only | 188ms /719of719 | Old ungated diagnostic; pre-Play coverage absent and quiet tail unanchored; never qualification |
| v58 ScreenCaptureKit only | 312ms /671of671 | Same signed artifact as v57/v59; real native failure |
| v59 CoreAudio repeat | 32ms /666of666 | Same old ungated diagnostic; never promoted to full qualification |
| v60 production natural book | 10ms /838of838 | All197 words, natural EOF, six complete scenes persisted; all six emitted waveforms match, max join.01ms |
| v61 bounded warm CoreAudio | 274ms /717of717 | Real first-synthesis native failure without ScreenCaptureKit; waveform criteria separately pass |
| v62 no-SCK System Trace | 174ms /684of684 | Instrumented pass only; tracer forced after120s finalization; export malformed, no owner evidence |
| v63 short launched Thread Activity | no final receipt | Readable diagnostic trace, but xctrace time limit SIGKILLed app; owned child cleaned; no normal-Quit/acceptance credit |
| v64 production saved-book replay | 51ms /748of748 | Zero forbidden model calls; all197 words, Save/reopen, cancel quiet and restart; six full waveform matches/maxjoin.01ms |
| v65 MLX max-ops1 diagnostic | 349ms /671of671 | First-synthesis native failure; functional/normalQuit pass; override not adopted |
| v66 production8bit, no CUA intervention | 93ms /668of668 | Strict bounded warm intended-source acoustic/runtime pass; no prior failures erased |
| v67 attached System Trace | 127ms /666of666 | Readable trace, profiler0/app normalQuit/noorphans; instrumented only, no >250ms reproduction |
| v68 production4bit CoreAudio | 16ms /668of668 | Functional pass; tap begins22.288ms after firstPosition, full interval coverage refused |
| v69 production4bit ScreenCaptureKit | 186ms /661of661 | Strict complete-waveform/runtime pass |
| v70 production A8/B4/A8 CoreAudio | 183ms /328of328 | Strict switches acoustic/runtime pass; rapid latest selection validated |
| v71 extended8bit diagnostic | 246ms /1868of1868 | Three minutes playback;164.232s complete audible references, min correlation.99177/maxjoin.00443ms; extended flag keeps overall verdict false |
| v72 Metal System Trace | 238ms /670of670 | Readable12s all-process GPU trace; profiler0/app normalQuit/capture0/guard0/noorphans; instrumented only |

V57/v58/v59 suggest a recorder contribution, not the whole cause. V61
falsifies a ScreenCaptureKit-only explanation. Its strict verdict fails;
diagnostic continuation matches54.682766s of complete intended-source audio
with unchanged .98 context/active and10ms join checks. It does not waive native
responsiveness. QA4179746 uses the new bounded process-tap primary protocol and
stronger final Pause selection. Play-to-tap remains unobserved; no first emitted
audio, full session, earlier-prefix/replay exclusion or load/startup credit.

V60 load-to-speech upper bound3052.390ms meets the10s first-load hard limit.
Ordinary startup10009.064ms is excluded only from that load clock. Total
launch-to-speech13061.564ms misses the2s goal. No target work moved to startup.
This bounded book does not establish arbitrary-document performance.

V64 reusable load-to-speech upper bound253.807ms meets the5s hard limit.
Startup360.209ms and total614.132ms are separate; the launch goal also passes.
All six scene correlations exceed.9997 and observed joins are.01ms or less.

V63's exact state table shows401.287ms cumulative Blocked across a selected
402.102ms CoreAnimation mutex cluster, separated by brief Running/Runnable
states; the largest adjacent block is40.435ms. This is not one continuous
400ms wait or sample-weight-derived occupancy. A same-process CA deferral
worker is correlated, but lock-holder/Mach recipient/GPU ownership is not
established. No final request-delay receipt exists. V67 attaches instead of
launching, so stopping the15s recorder leaves the app under its standard
runner's normal-Quit ownership. It has112ms and127ms request witnesses but no
failed250ms witness. No speculative native source fix follows.

MLX0.32.4 documents MLX_MAX_OPS_PER_BUFFER as a batching diagnostic, not GPU
priority. V65 changed only that variable to1 in a fresh child, leaving MB,
progress and CPU policy unchanged; native349ms still fails. This does not
prove batching actually changed the relevant GPU work, nor establish a GPU
cause. The runner labels any such override diagnostic and refuses acceptance.

The sanitized v55 audit verifies the exact post-exec app PID/image and188ms
window coverage. Main stacks show an AppKit window-move CAFence/CA transaction
wait, not awakeFromNib. No exact remote owner or source patch follows from those
sampled stacks. V53 missed the delay; v56 trace was unusable. Raw traces/TOC,
environment-bearing logs, model weights and audio remain private. WAV hashes
are retained separately. Full JSON receipts retain independent failures.

S8 final native UIv6 passed its own nine gates at96ms native/22ms UI with all
3418 native samples active, zero forced frames and no speech. That is separate
from simultaneous MLX/audio acceptance. No M3, human listening, physical speaker,
feature integration, main merge or publication claim. Every actual app launch
verified normal Quit and owned process exit; tracer failures are separate.
