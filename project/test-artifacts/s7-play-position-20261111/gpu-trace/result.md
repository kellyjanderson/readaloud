# V72 matched first-synthesis trace review

Read-only review, scoped to the dispatched native request; no source, assets, installed app, build, test, Actions, merge, or push changes. Root owned the application and its normal Quit. This worker launched no app and imported no MLX. Managed runtime Python was used only for XML/JSON parsing. Existing tracked QA WIP was preserved.

## Timing and identity

- Trace: QA container `Data/s7-8bit-metal-v72-20261111/native-attached.trace`, run 1; Metal System Trace, 12.975256 s, all processes, Time Profiler/context-switch/wait/kernel stacks enabled; shader profiler disabled.
- Native PID 54564, exact `tmp/ReadAloudS7WarmQualified.app/Contents/MacOS/read_aloud`; owned MLX PID 54588, same bundle's `Contents/Resources/python-runtimes/mlx-native/bin/python3.12`. WindowServer PID 610. Bundle-path ownership is verified; TOC does not independently expose a parent-PID edge.
- TOC start `2026-11-11T21:25:42.456-08:00` = Unix 1794461142.456 s. Millisecond formatting limits cross-clock alignment; allow at least ±1 ms instead of nanosecond certainty. This is separate from native probe-relative 5.902 s request time.
- Given request Unix µs 1794461146329428, native entry 1794461146566671, return 1794461146566786 map nominally to trace 3.873428, 4.110671, 4.110786 s. Request→entry = 237.243 ms; entry→return = 0.115 ms. This is the instrumented 238 ms receipt, not a >250 ms request-delay witness.

## Concrete native stack: AVPlayer position query

Native main TID 64793701 (`0x3dcac65`) has the same stack at 3.859604125 and 4.109790166 s:

`psynch_mtxcontinue → ksyn_queue_insert → __psynch_mutexwait → _pthread_mutex_firstfit_lock_wait → _pthread_mutex_firstfit_lock_slow → MediaToolbox 0x198517164 → 0x198c6d0e8 → 0x198643420 → 0x19850e07c → -[AVPlayerItem _currentTimeWithOptionalFoldedTimebase:] → -[AVPlayerItem currentTime] → -[UriAudioSource position] → -[AudioPlayer getCurrentPosition] → -[AudioPlayer updatePosition] → -[AudioPlayer play:] → -[AudioPlayer handleMethodCall:result:] → Flutter method channel/platform task`.

Those four private addresses resolve to MediaToolbox UUID `58BE6AB9-9D26-31B1-B109-9AB2A2327A1A`, arm64e, load address `0x1982dd000`. The two sampled stack timestamps are 250.186041 ms apart and bracket nearly the entire measured request wait. They are sample/context-switch boundaries, not proof of one continuous 250 ms block or lock-holder identity. Empty adjacent records at 3.859612416 and 4.109871666 s must not be interpreted as CPU occupancy. No mutex address, lock holder, IPC destination, or GPU dependency edge is exported by these selected schemas.

No native CA stack sample appears in 3.800–4.111 s. The `io.flutter.ui` samples in this window are predominantly idle run-loop Mach receive. The prior V63 Core Animation mutex/deferral-worker cluster is a different trace and must not replace this V72 AVPlayer stack. V72's selected window supplies no CA deferral-worker→WindowServer ownership proof.

## Concurrent GPU / command-buffer evidence

Nominal window: 3.873428–4.110671 s. Counts are rows overlapping this window, not complete synthesis totals.

| Owner | Evidence | Count | Maximum interval | Other measured accounting |
| --- | --- | ---: | ---: | --- |
| MLX 54588 | GPU Compute execution | 1,678 / 1,678 unique command buffers | 1.746 ms | union 195.008562 ms (~82.2% of window); summed 195.033312 ms; max CPU→GPU latency 10.356541 ms |
| MLX 54588 | App command-buffer submissions | 2,263 | 15.2985 ms | all one encoder; summed displayed intervals 233.160773 ms |
| MLX 54588 | Driver command buffers | 2,262 | 3.267958 ms | summed intervals 54.868151 ms |
| MLX 54588 | Driver command encoders | 1,687 | 3.265750 ms | nested with command buffers; never add both as CPU time |
| WindowServer 610 | GPU Vertex/Fragment execution | 40 / 17 unique command buffers | 0.065417 ms | union 0.545415 ms; max CPU→GPU latency 7.922875 ms |
| WindowServer 610 | Driver command buffers | 34 | 7.845500 ms | summed intervals 9.718046 ms |
| Native 54564 | GPU / app submissions / driver | 0 | n/a | no owned rows in this selected window |

The GPU data does not contain a long individual execution interval matching the 237 ms native wait. Many short MLX executions and CPU submissions overlap the native mutex-query episode. The app-submission interval label/duration is not established as exclusive CPU-running time. The driver export has one encoder row whose process column says MLX but whose thread and event are WindowServer `coreanimation.assembly-encoder`; the sanitized driver JSON records explicit thread owner and the table uses that owner, rather than silently claiming the 7.679333 ms encoder for MLX.

`ca-client-buffer-wait-interval` and `display-compositor-interval` exported zero rows. That is unavailable instrument evidence, not proof of no CA/compositor waiting. GPU command IDs, thread IDs and event ordering expose ownership within the Metal data; they do not connect the native MediaToolbox mutex to a GPU owner. No GPU, private prefill, or scheduling source patch follows from this evidence.

## Batching-control boundary

MLX v0.32.4 reads `MLX_MAX_MB_PER_BUFFER` once, and its commit policy ORs operation and cumulative unique-input-byte thresholds. The architecture-specific default is not universally 40; the actual selected default and triggered condition are not recorded here. Raising MB to 1000 in a fresh child could test whether memory-triggered submissions become fewer, but only actual command-buffer counts per matched synthesis work would establish batching changed. A fixed wall-time count alone confounds throughput. These are inferences from [MLX device.cpp](https://raw.githubusercontent.com/ml-explore/mlx/v0.32.4/mlx/backend/metal/device.cpp) and [environment accessors](https://raw.githubusercontent.com/ml-explore/mlx/v0.32.4/mlx/utils.h). There is no native mutex-owner link, so this remains an indirect hypothesis; root declined an MB experiment or adoption. The earlier ops=1 run does not establish any actual batching difference.

## Sanitized return artifacts

- `native-wait-boundaries.json`: native main bracketing samples plus selected-window CA search result.
- `profile-window-owned.json`: native/MLX/WindowServer samples only, first wait plus 5 ms alignment margin.
- `gpu-window-owned.json`: owned GPU rows overlapping the first wait.
- `submissions-window-owned.json`: owned app submissions overlapping the first wait.
- `driver-window-owned.json`: owned driver rows overlapping the first wait, with explicit thread owner.
- Parsing scripts reproduce filtering; `.private.xml` exports and the environment-bearing original TOC remain private and must not be published.

No new acoustic acceptance, human listening, M3, feature completion or release claim. Current-block retrieval for #145 and #139 failed the helper's exactly-one-block check; root was notified and owns reconciliation. Explicit dispatch #144 comment 6815528778 supplied this bounded task.
