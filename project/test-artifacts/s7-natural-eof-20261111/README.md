# Natural book EOF and saved-book replay diagnostics

Refs #142/#144/#112, ACD-M1 R1 and #110 R23/R25. Signed arm64 native
candidate built from59702df (includes finite-EOF correction79fa0b9 and progress
coalesceradcece7). QA physical-head flag remains off by default. These runs are
not production-adoption, M3, listening or physical-speaker acceptance.

| Case | Functional observation | Emitted audio / responsiveness |
| --- | --- | --- |
| v46 first load | All197 words, natural completion, six-scene saved book | SCK setup failed (PID/display unavailable); no acoustic/timing credit. Native20ms, zero foreground samples |
| v47 repeat first load, CoreAudio | All197 words, natural completion, six-scene saved book | All six full active waveforms matched; max external join0.01ms. Native200ms/all800samples active |
| v48 saved v47 book, CoreAudio | Full197-word playback, Save/reopen, cancellation stays quiet, restart, zero forbidden model calls | All six full active waveforms matched; max external join0.01ms. Native15ms/569of762samples active |

V47's ordinary startup is4276.319ms; document-load-to-emitted-speech upper
bound2235.428ms meets the10s first-load hard limit. Total launch6511.843ms
misses the2s goal. V48 startup264.548ms, document-load246.314ms and total
launch510.977ms meet the5s reusable-book limit and2s launch goal. All work
triggered by the document request stays on its load clock. No capture Play gate.
CoreAudio timing is callback-receipt upper bound, not physical-speaker onset.

The maintained comparator retains its generic250ms join threshold; this
record separately requires observed joins <=10ms and correlation >=.98. The
actual maximum is0.01ms in both captures. Reference paths are v47's exact saved
book scene WAVs; v48 replays that same saved book. Input adaptation is retained.

All three runners remain overallfalse because the physical-head QA flag is
explicitly non-qualifying; v46 also failed capture. The timing summarizer's
'Native functional/cleanup check failed' comes from that runner verdict and
must not be misreported as a product pass. Individual native receipts, clocks,
waveform matches and failures are separate evidence. Every run normal-Quit,
exact owned PID exit, no force and no remaining owned processes. The sequence
wake guard remains root-owned until the test sequence ends.

Independent review subsequently found the same-head early-final notification
path unrepresented in these runs. Production applicability and that controlled
ordering still require correction/requalification. Generic/indefinite media
must not inherit a global QA flag. All previous failing controls remain retained.
