# Dart bindings for native speech synthesis

## Proposed architecture

Use the same division that already works for Kokoro. The Dart speech runtime submits a prepared request to a compiled model implementation. Use a maintained model SDK for the tokenizer, conditioning, model generation and codec. Add a thin generated Dart/Swift binding over stable Flutter platform channels for model lifecycle and render operations. The first transport should exchange small typed messages and references to app-owned staged audio. Measuring the existing streaming path will show whether the bridge needs a lower-level buffer interface. [Current worker interface](../../../lib/src/services/speech_worker_pipeline.dart), [Pigeon platform channels](https://docs.flutter.dev/interop/pigeon)

```text
Dart reader and speech planning
    → speech admission and synthesis processor
    → generated Dart/Swift binding
    → Swift model host on a dedicated execution lane
    → native MLX model and codec
    → PCM packets or completed staged WAV
    → existing Dart validation, playback and export
```

Use a narrow C ABI and `dart:ffi` if the chosen native library already exposes a suitable C API, or a measured copy bottleneck justifies it. Use a supervised compiled helper behind the Dart-facing API if in-process draining, crash isolation, memory reclamation or platform deployment fails qualification. Reuse the existing supervised transport and its bounded, out-of-band cancellation where a helper is necessary. A selectable operating mode is unnecessary for readers if a single deployment meets the evidence gates. [FFIgen](https://docs.flutter.dev/interop/ffigen), [runtime candidate comparison](../../research/native-tts-runtimes.md)

## Boundary and ownership

| Owner | Responsibility |
| --- | --- |
| Dart controller and planning workers | Own document and playback intent, source spans, casting, pronunciation, canonical delivery directions and chunk/scene selection. Lower supported controls for the exact verified backend, model and capability revision. |
| Existing Dart speech coordinator | Own admission, playback before export, generation/session identity, cached and staged asset acceptance, queue credits and cancellation. Use the existing playback/export resource and synthesis leases. |
| Native model host | Own one admitted render at a time, the resident model, reference conditioning, native buffers, model progress, resource accounting and typed errors. It uses the selected library's model/reference caches during the resident lifetime. |
| Artifact and playback owners | Validate ordered packets and complete assets. Publish immutable WAVs only after success, preserve existing cache scopes, play current audio and export the admitted/rendered sequence. |

The model host should expose a capability/identity query, prepare and release operations, one render operation, cancellation by request, and shutdown. Preparation accepts a verified local snapshot plus runtime, precision and memory identity. Render accepts either one bounded text span or canonical ordered turns as needed by existing features, along with source/request identity, binding revision, voice references and transcripts, engine-ready text and a typed set of supported controls. It returns the same request and binding identities, format, frame counts, completion state and a staged WAV descriptor. A streaming extension uses the existing packet contract and credit. It validates packet order, frame offsets and final-state accounting against a completed artifact. [Worker protocol](../../../lib/src/services/speech_worker_pipeline.dart), [packet representation](../../../lib/src/services/speech_audio_packet.dart), [scene types](../../../lib/src/models/native_speech_turn.dart)

### Concurrency and termination

- The Flutter main isolate retains UI state. Native calls may enter the host through the platform channel, where they hand work to a dedicated serialized execution lane. Swift `async` expresses how results are delivered. The model and codec work need their own execution context.
- The existing Dart admission owner remains the source of queue credit. The native model host accepts only the admitted operation. Backpressure applies to streamed PCM as well as synthesis requests. A cancellation command can reach the owner while packet or playback credit is exhausted.
- Cancellation first revokes authority to publish on the Dart side. Typed success, error, progress and packet callbacks are checked against the current session, generation, model and binding. A cooperative native cancel still needs an acknowledgment that inference has drained before another model may load. Quarantine the owner during a drain timeout. Demonstrate restart safety and memory reclamation before choosing in-process deployment. A helper can be killed and reaped if those semantics require termination.
- Partial output stays in an attempt-owned staging area. Failure, timeout and cancellation release owned staged files and buffers or preserve the diagnostic prefix under the existing incomplete-attempt policy. No failed or obsolete artifact enters playback or reusable audio. Quit revokes demand, drains or terminates runtime owners, and verifies process exit. [Current admission owner](../../../lib/src/services/synthesis_admission_owner.dart), [current MLX owner](../../../lib/src/services/mlx_speech_worker_processor.dart), [macOS termination integration](../../../macos/Runner/AppDelegate.swift)

## Asset and cache migration

Start with an already installed, verified local model. Reuse the current catalog, known snapshot identity, voice assets, app-owned cache directories and memory admission policy. Qualify native lookup, download, resumption and integrity before replacing the Python provisioning path. Evaluate maintained Hub/HTTP libraries against the current managed cache and recovery behavior. Keep catalog verification, archive/path validation and publication policy under their documented owners. A candidate that needs a converted checkpoint or codec gets a distinct model profile and provenance. It never overwrites an installed source snapshot.

Version raw audio identity with the actual backend, runtime/library revision, model and codec fingerprints, precision, reference identities, effective input and direction payload, and generation options that affect the WAV. Preserve old playable WAVs and portable books. New synthesis uses the native identity. A transport speed setting belongs to transport or to a separately keyed rendered derivative when baked into an export. Dropping an existing identity field or aliasing across runtimes needs proof that the cached audio remains equivalent for that use. [Catalog store](../../../lib/src/services/fish_drama_catalog_store.dart), [memory admission](../../../lib/src/services/qualified_engine_selection_service.dart), [artifact ownership](../../architecture/audio-artifact-identity-and-lifetime.md)

## Delivery controls across the boundary

| Control | Proposed ownership |
| --- | --- |
| Synthesis speed | Remains a verified numeric model input for Kokoro. Advertise a native synthesis-rate capability only when the backend implements it and emitted tests confirm it. |
| Listening and export speed | Keep listening rate at the player layer when using time-stretch. Define separately whether export follows that rate. Prefer an existing player or native DSP facility after duration and pitch measurements. A player-only change can reuse raw audio. |
| Cadence | Dart owns segmentation, join policy and canonical break intent. The model determines timing within the render. Preserve any existing backend-specific controls and qualify their scope before exposing new ones. |
| Pitch, emphasis and expression | Canonical document directions belong to Dart. Translate only the capability and context that qualify. Fish's current bf16 whisper/shout evidence is scoped to that Python runtime and model context. A native backend must earn its own cue and speaker-continuity evidence. |
| Accent and pronunciation | Preserve the voice identity, reference audio/transcript pairing and existing lexical/phoneme policy. Highlight the difference between a pronunciation change and changing the acoustic voice. The new SDK should receive the same prepared speech text, without extra normalization that changes it unexpectedly. |

## Open decisions

- Scope of removal. Python-free speech, including acquisition for each supported native engine, is the recommended goal. Removing an optional NLP provider or retiring an engine is release scope and needs its own decision.
- macOS 14 compatibility. First test the best exact-checkpoint candidate and verify deployment floors. If its dependencies require macOS 15, gather evidence for a compatible candidate, separately deployable helper, or an explicitly approved platform floor change.
- Process placement. Select in-process Swift or a compiled helper from the measured cancellation, crash containment and memory behavior. Document exactly how pause, replacement and Quit work for the chosen approach.
- Capability parity. Decide whether any engine or precision is offered with fewer features only after recording the effect on the current workflow, cache and accepted scope.

Implementation should reconcile [runtime messaging](../../architecture/speech-runtime-messaging-boundary.md), [playback boundaries](../../architecture/playback-orchestration-and-synthesis-boundaries.md), [artifact identity](../../architecture/audio-artifact-identity-and-lifetime.md), native model setup, and packaging instructions.
