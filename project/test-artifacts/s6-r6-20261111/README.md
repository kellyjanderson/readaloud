# S6 R6 native evidence, November 11, 2026

These immutable receipts retain both successful bounded tests and failed controls.
GitHub [S6 #137](https://github.com/kellyjanderson/readaloud/issues/137) owns execution
and acceptance; this directory records evidence, not a second planning authority.

## Timing boundaries

[R25](https://github.com/kellyjanderson/readaloud/issues/110#issuecomment-6791030471)
excludes ordinary app startup from the five-second reusable-book and ten-second
first-load hard limits. The two-second launch-to-speech goal remains separate.
The R25 reports use shared CLOCK_MONOTONIC_RAW boundaries for launch, ordinary
startup completion, explicit target loading, Play and captured signal. No target
synthesis or native audio sources exist before measured target loading. Startup
may initialize the selected model as normal application behavior. All preparation
triggered by the target request remains in the load clock; no guessed subtraction
or relabeling of historical receipts is used.

Candidate v11 is source f5f3c8a, actual arm64 release code in a signed sandbox QA
bundle; `r25-v11-candidate.json` hashes the copied Runner and AOT App framework.
The existing full-precision Fish model is read-only. Each first-load test uses a
new private raw store with no target synthesis cache; existing installed runtime,
model and reference files and OS caches are retained. Reusable-book testing uses
two owned copies of the same complete book, so its warm OS cache condition is
explicit. Model access is forbidden in the reusable probe. These are bounded
197-word/four-scene fixtures, not arbitrary-book or physical-speaker proof.

- R25 v11 first load: startup9953.107ms separately; document load to captured
  speech5351.837ms meets10000ms. Launch-to-speech15305.081ms misses the2000ms goal.
  Four full queued waveforms match at correlation>=.98; maximum join gap0ms.
  Native main response103ms, UI heartbeat8ms, activity starts/ends6/6, none active.
- R25 v11 reusable book: startup288.717ms separately; document load to speech
  283.542ms meets5000ms. Launch-to-speech572.363ms meets the2000ms goal.
  Four full waveforms match, maximum join gap0.01ms. Native main214ms/UI7ms.
- R25 v11 cancellation: controller-command cancellation during natural cold
  initialization, then retry and Pause during an incomplete streamed scene.
  Captured pre-retry and post-Pause-guard silence have zero peak; the active40ms
  first-packet prefix matches at.997938. Pause drain2ms, native main161ms/UI4ms,
  activities3/3/0. The8307ms cancelled background drain is not control latency.
- Native-input v8 separately records an actual Cancel pending Play click:
  40.441ms from input-call start to observed cancelled intent, with background
  drain continuing independently. Its.997151 prefix and silence checks are
  bounded cancellation evidence; these do not establish a complete turn.

All successful runners requested normal Quit and verified zero owned children.
Capture results are app-emitted signal receipt upper bounds, not physical speaker
onset. Human listening, voice/expression/transcript judgments and final usability
remain collected for S11 by release decision.

## Failed controls and limits

Historical R24 launch-only timing reports preserve their original verdicts and
cannot qualify the R25 clock. Aligned/prefault model-loading experiments did not
improve actual launch-to-speech enough and were removed; current code uses the
maintained serial provider. No model weights or precision were changed.

The v3/v5/v9 packet diagnostics preserve skipped or gapped native audio despite
functional source completion. In particular v9 initial playback failed the whole
waveform threshold (.511), while changed/reused/missing captures passed. Native
queue fixes use an immutable old index, actual surviving head, one queue snapshot
and one retained completed predecessor until the following source completes.
The24 production-native fixture scenarios include negative controls; source tests
alone do not establish emitted continuity.

R25 v10 completed all four waveforms and met the document-load hard limit but
failed the unchanged250ms native-main gate with286ms during ordinary startup.
Source f5f3c8a extends native work activity through runtime acquisition before
Python starts. Passing v11 observations qualify those runs; they do not prove a
universal stall cause or erase v10.

Private WAVs and books remain at the exact receipt paths; manifests and reports
retain identities/hashes. Large media and model assets are not copied into Git.

The full R25 v11 sequence passed all functional and four strict full-waveform checks
(initial, changed, reused, genuinely uncached missing repair), with joins at most
0.01 ms and all 197 source words retained. Saved reopen made zero new synthesis
calls. Its overall native receipt FAILS: a 263 ms main-channel roundtrip during
final Save exceeded the unchanged 250 ms gate; UI maximum was 13 ms, activities
10 started/10 ended/0 active, normal Quit/zero owned children. Source and logs
exclude bookmark creation from that interval; the staging allocator already runs
on a utility queue. No speculative bookmark change was made.

## Foreground v12 complete-sequence receipt

Native code `f2d96a2` passed the full initial/change/reuse/uncached-repair sequence.
All four complete waveforms matched at correlation >= .98, with joins <= 0.01 ms.
Native-main roundtrip maximum was 230 ms across 3359 samples, including final
Save; 3267 samples observed the app active. UI maximum was 9 ms. Activities were
10 started / 10 ended / 0 active. Normal Quit left no owned processes. Native
handler entry/return diagnostics remain separate from the monotonic 250 ms gate.
The runner explicitly activated its directly spawned app before initial playback.
This qualifies the bounded foreground run; it does not identify the cause of the
earlier 263 ms failure. The controlled Play gates qualify continuity only. Load
latency remains established independently by the ungated v11 timing receipts.

`r25-native-qualification.json` ties together exact receipts and hashed local
check logs. Human listening/usability remains in S11; release integration and
publication are separate from these recorded native observations.
