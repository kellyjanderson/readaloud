# v63 bounded thread-state review

Read-only analysis at source 67b8fbefb60f68a93d6b77869b89d67d9ecb8d84. Assignment: issue144 comment6815166252; target145 ->139. Only tmp/s7-thread-state-review outputs changed; no source, tests, app, assets, or runtime changed.

Identity: trace target PID43066 (launcher name env, exec verified by sampled read_aloud binary UUID37B553A9-BD01-31CA-A48E-2BB045911720); main TID64738995/0x3dbd6b3; App AOT UUID9D42B563-4F11-3A62-ACDB-89153B22F3F9. Trace start21:02:18.220-08:00; times below are relative trace seconds. Diagnostic time limit SIGKILL/no final receipt and no normal Quit: no acceptance credit and no exact method-delay mapping.

## Long state intervals

The main-state table contains30 Blocked intervals >=100ms, maximum101.455292ms (12.511567041–12.613022333s), plus a634.688458ms initial Unknown interval which is not a demonstrated wait. Every >=100ms Blocked start has a preceding main sample68.917–135.250us earlier in mach_msg2_trap -> __CFRunLoopServiceMachPort -> __CFRunLoopRun -> AppKit next-event/run. These are consistent with ordinary idle runloop waits, not proved UI request stalls. All exact boundaries are in long-wait-boundaries.json. No individual non-Unknown main state exceeds101.455292ms. No >250ms main wait established by those rows.

## Separate CA mutex cluster

17 main samples at6.567174541–6.965580791s show psynch_mtxcontinue -> ksyn_queue_insert -> __psynch_mutexwait -> pthread firstfit lock -> CA::Context::commit_transaction -> CA::Transaction::commit/flush -> flush_as_runloop_observer -> stepTransactionFlush -> UC::DriverCore::continueProcessing. A further sample6.968427416s shows the mutex wait inside CA::Context::send_deferrals under commit_transaction. Ordinary idle runloop samples bracket the cluster at6.558424708 and6.975092833s.

The directly adjacent Blocked states are repeated, separated by Running/Runnable intervals; they must not be called one continuous400ms block. Selected exact boundaries:

-6.567188416–6.596407333s:29.218917ms
-6.596418750–6.636853583s:40.434833ms (largest adjacent CA-cluster Blocked state)
-6.636865583–6.670040166s:33.174583ms
-6.707775375–6.743681166s:35.905791ms
-6.943193750–6.965575291s:22.381541ms

Across the explicitly selected6.567188416–6.969289958s window (402.101542ms), state-table integration gives401.287166ms Blocked,0.670295ms Running and0.144081ms Runnable. This is state occupancy for that window, not sample-weight-derived occupancy and not proof every blocked subinterval has the same owner/cause. Exact18 sample/preceding-block pairs, including gaps2.750–7.708us from block end to sample, are in ca-mutex-boundaries.json; first sample has preceding8.516417ms wait and last send_deferrals sample preceding0.789042ms.

## Correlated peer and limits

Same PID worker TID64738998/0x3dbd6b6 has17 samples6.567155375–6.965564708s, each about7–20us before corresponding main mutex sample, in CA::Context::send_deferrals -> CA::Render::Encoder::send_message -> CA::Render::Message::send_message -> mach_msg2_trap, called from CA::Render::Fence::Transaction::Observer::activate and dispatch_mach. It remains in this path at6.968326291s. This is a strong correlated candidate peer, not a proven mutex holder: no mutex address/owner edge or Mach port recipient/remote stack is present in exported evidence. Main-state made-runnable-by/preempted-by/yielded-to are empty for these rows. No WindowServer/GPU cause follows.

Flutter UI TID64739070/0x3dbd6fe has31 samples6.510836750–7.039009500s all in idle CFRunLoop/fml message loop. No io.flutter.raster/Metal sample is present in this selected window. Absence of samples is not proof raster or GPU were uninvolved. MLX child is not a sampled target here. app.log contains untimestamped synthesis timings and nearby timestamped AppKit geometry warnings, insufficient to map the cluster to an exact synthesis request or establish that the geometry warnings caused it.

## Smallest falsifiable next proof

No source patch is justified by this trace alone. Repeat a short attach-to-root-owned-app capture around the same first-synthesis phase, retain successful normal Quit/receipt, and correlate a measured main request delay with CA main-mutex and same-process deferral-worker boundaries. If testing the proposed one-variable batching control, set MLX_MAX_OPS_PER_BUFFER=1 in a fresh child while keeping the runtime/audio artifact, MB threshold, progress delivery, and CPU policy unchanged; compare actual request-delay witnesses plus emitted audio and cancellation. Reduction without matched CA/request boundaries supports correlation only. A specific CA ownership claim additionally requires lock identity/owner or Mach recipient evidence; do not infer GPU ownership from CA frame names.

## Export/analysis result

Completed: thread-state, waiting-thread time-profile, raw all-thread-state time-sample. context-switch-sample export failed with Unexpected internal error. The optional combined ThreadActivity/context-switch/identity export grew excessively and was explicitly canceled (owned xctracePID44044 exited); its incomplete private XML was removed. dyld table in that partial output was empty; sampled image identity above is available from time-profile. No other export remains running. Managed Python3 -B at the assigned runtime path parsed XML/JSON without imports of MLX.

Reproduce with xcrun xctrace export --input TRACE --xpath '/trace-toc/run[@number="1"]/data/table[@schema="thread-state"]' --output thread-state.private.xml; use table[@schema="time-profile" and @record-waiting-threads="1"] for symbolized profile and table[@schema="time-sample" and @all-thread-states="YES"] for raw samples. Run state-detail.py, match.py, cluster.py, boundary.py using assigned managed Python. Raw XML stays private (paths/process names); sanitized result and JSON contain no environment dumps. Scripts/JSON are disposable analysis evidence, not design or execution authority.
