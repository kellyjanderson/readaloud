# Native TTS migration and acceptance plan

This draft proposes a sequence and acceptance gates for coordinator review. The [design](design.md) defines ownership across the binding. The [upstream research](../../research/native-tts-runtimes.md) records the compatibility questions to resolve.

## 1. Freeze the comparison

Record the baseline app commit and runtime, hardware, Flutter/Xcode build, exact model and codec identity, voice digests, selected text and expected speaker sequence. Use non-private fixtures covering single-speaker prose, dialogue returning to a previous character, and exact final words. Include a saved-book fixture with existing audio and a first-load fixture that needs synthesis. Run the baseline through the real playback/export path and retain model startup, reference encoding, first PCM, complete render, first emitted audio, full output, memory, and child-process cleanup measurements. Use existing deprecated-Kokoro evidence or probes only for a specific compatibility comparison. The native migration targets Fish and the other MLX backends. Project receipts are evidence for their own binaries and fixtures.

## 2. Prove the native model in isolation

Evaluate the Soniqo Swift Drama 3 adapter first with the **installed, verified Fish 4-bit checkpoint at `2b0c8028998533972e77359cce56b8bf1c5d6d4a`** and the app's existing reference/transcript pairs, provided the test host supports its package. Pin the source and transitive dependencies. Use its native CLI or test API with an explicit local directory and network disabled for this proof. Prefer measurements that separate cold process, first model load, first reference encoding and subsequent renders. Confirm native 44.1 kHz PCM, complete speech including final words, ordered slots and stable voice references. Collect peak physical footprint, real-time factor, and time to first playable piece separately from whole-WAV completion.

If exact checkpoint loading fails, record the incompatibility at the config/tokenizer, quantization, codec or packaging boundary. Try the documented alternate Drama port or a small, reviewable compatibility patch before considering an app-owned model and codec port. Keep any alternate checkpoint in a distinct profile. Qwen Base 1.7B is a smaller secondary binding proof with the same class of reference conditioning. A Qwen result answers the binding question and leaves Fish qualification open.

**Exit evidence.** A repeatable native fixture render with pinned sources and actual PCM, no Python child, and a recorded checkpoint/codec and deployment result. Include upstream reuse versus any app-owned missing API. Independently verify macOS 14 viability or identify the explicit deployment decision.

## 3. Add one Dart-facing backend to the normal reader

Adapt the current speech processor and reuse its admission, cancellation, artifact, playback and export interfaces. Add a gated native backend for the one qualified engine/precision. Start with file-backed output to isolate the binding change. Include the existing packet path before replacing a production configuration that depends on incremental audio. Keep exact-matching request and binding IDs, packet and WAV validation, and explicit success/failure. Instrument bridge overhead and queue occupancy. Test app interactions while native work is genuinely active.

**Exit evidence.** Playback and export from the same ordered accepted PCM through the actual app. Measured responsiveness and bounded queues during wait, cancellation, replacement and export overlap. Forced stale success, error and progress are ignored. Under a held or failed render, record when Play becomes cancellable, when native work drains, and when model memory becomes available. Exercise normal Quit and verify all test processes and handles exit.

## 4. Replace Python provisioning and qualify features per engine

Add native resolution of eligible local snapshots, and a managed acquisition path where required. Reuse current integrity and model selection owners. Check offline reopen with complete files, incomplete models, interrupted acquisition and resumption, corrupted artifacts, disk-space and memory admission, and an A → B → A engine switch. Exercise the signed, sandboxed app with no interpreter available to the enabled speech route. Verify existing WAV and portable-book replay works offline and new native output carries its own synthesis identity.

Expand coverage in this order if the first Fish lane qualifies.

1. Fish 8-bit and bf16, each with its exact profile, memory envelope and hardware evidence. Include the bf16 directed-scene and voice-continuity corpus. Verify 4-bit and 8-bit expectations independently.
2. Qwen Base and CustomVoice, then Voxtral full and fast. Compare existing reference and preset behavior and precision selection.
3. MOSS v1.5 with the exact codec/tokenizer assets. Use the compatibility finding to decide whether to adapt a maintained port, contribute upstream or defer that runtime with the coordinator's scope decision.

**Exit evidence.** Each configuration is evaluated against its own accepted behavior. Report availability by engine and precision. Retire the Python speech bundle for a release only when the approved native speech configurations and provisioning routes cover that release's scope. Keep an explicit evaluation route for the old runtime while it remains useful for comparisons.

## 5. Measure the reader and reconcile

- **Startup.** Record app launch, normal startup complete, document-open, Play, engine preparation, first PCM, first queue admission and captured emitted speech. Verify the workspace’s **2-second opening-to-speech requirement**. Also report the integration baseline’s R25 post-startup gates separately, **5 seconds** for reusable `.radoc` and **10 seconds** for a first load requiring preparation or synthesis. Use separate cold and warm runs and a long source. Keep target-document work inside the applicable timing interval. [Product definition](../../product-definition.md)
- **Continuity.** Use a short exact comparison and long reading with voice changes, range boundaries and export overlap. Check missing, repeated and truncated words, starvation, unexpected pauses, final syllables and PCM alignment. Measure native stream and finalized-file results against the same render when possible. For separately generated stochastic renders use a common seed when supported, ASR and waveform checks, and human listening. Byte equality between different engines is unnecessary for perceptual comparison.
- **Voice and delivery.** Listen for recognizable identity across normal, whispered and shouted turns where supported. Confirm pronunciation changes for the same words and speaker routing separately. If a speed path changes, measure emitted duration, pitch and export behavior at multiple settings with the same material.
- **Availability and recovery.** Exercise cached replay without model startup, re-render compatibility, engine changes, low-memory refusal, cancelled model acquisition, recoverable failure, and clean Quit. Capture per-stage progress with real completed work or honest waiting/unknown totals.
- **Packaging.** Verify the arm64 signed sandbox build, native libraries and Metal resources, applicable macOS and memory envelope, offline/online installation and notices. Confirm which runtime binaries and data actually ship. If the release offers ModernBookNLP, report and test it as a separate optional Python runtime. Any product-wide removal needs a separate native-analysis or feature-scope decision. [Model lifecycle](https://github.com/kellyjanderson/readaloud/issues/112)
- **Reconciliation.** Record local and human acceptance evidence in the owning GitHub issues and update current architecture alongside implementation. Leave unresolved hardware, listening and product readiness gates open. Repository Actions remain disabled.

Exact checkpoints, test limits and the result of each gate belong to the owning issues when work starts. The [interim design lifecycle](../README.md) governs review and publication.
