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
