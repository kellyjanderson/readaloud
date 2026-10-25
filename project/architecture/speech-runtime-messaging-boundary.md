# Speech Runtime Messaging Boundary

Reconciled: October 24, 2026
Status: Current source architecture; P2 resident-resource evidence recorded in issue #51

## Implemented structure and limitations

The runtime carries session/generation identity through commands, events and chunk DTOs. `SpeechWorkerPipeline` admits at most eight pending chunks plus one active inference. The active slot includes boundary correction: the pipeline directly awaits the runtime completion hook before starting its next chunk. Predecessor-dependent correction therefore has one active task and no independent queue; per-runtime order is preserved even if native inference finishes faster than correction. Plan submission awaits capacity; cancellation and shutdown bypass the facade's admission queue so they can unblock producers. Eight is a provisional admission limit, not a measured playback watermark. P3 owns contiguous lead and playback/export priority policy.

`KokoroSpeechWorkerChunkProcessor` owns one supervised resident isolate. Resource preparation hashes the model, validates its native session, validates and loads required voice vectors, and returns immutable `PreparedVoiceBinding` records containing model/voice digests, engine/profile identity, document identity and binding revision. Serializable resolved character references preserve the cast assignment decision and join it to the resource record. Document or voice/cast intent invalidates the snapshot; same-document intent changes retry preparation, while replaced document revisions cannot publish success or failure. Playback supplies this exact reference set and validates it against resident ownership instead of reusing a playback token as a document revision. Native handles stay in the worker/plugin. Repeated chunks select resident vectors; ordinary speaker changes do not load a model or voice file. Content identity participates in the worker cache path and sidecar check. Broader atomic cache publication, corrected derivatives and retention policy remain P4.

The worker accepts one command at a time. A timeout reports failure and quarantines admission, suppresses late events, and retains ownership until the native call drains. It does not kill an isolate and pretend native inference stopped, nor create a replacement model while work is undrained. Startup timeout retains the eventual ready channel for cleanup. The final worker shutdown explicitly exits after native disposal, because the background messenger keeps its own port alive. `releaseResources` drains before closing; `dispose` awaits close and isolate exit. A permanently stuck native call can therefore leave shutdown waiting; hard native cancellation is not claimed.

The macOS plugin serializes ONNX calls on `ortQueue`. The model runner disposes every allocated input and output tensor on success and failure before closing the session, including on macOS. Partially registered native outputs roll back if metadata extraction fails. The former per-chunk macOS close workaround is replaced by resident ownership and explicit drain/close. Native resource counts and close-cycle evidence belong in [P2](https://github.com/kellyjanderson/readaloud/issues/51), distinct from acoustic quality or UI proof.

The optional `ResourcePreparationCapable` engine bridge gates document speech readiness on resource preparation and preserves failed/stale preparation states. Direct speak/export paths also prepare resources. Pause and jumps retain the context; document replacement, end-of-document, export takeover and shutdown release it after drain. Replay re-prepares before synthesis and joins any in-flight player stop/clear reset before replacing sources. Runtime shutdown also drains tracked boundary-correction futures and suppresses their stale terminals. Correction validates session/generation/work-item identity before work and after either outcome; cancellation suppresses publication while the running compute isolate drains. Failed predecessors clear their trailing-silence reference, so later correction receives unknown predecessor context rather than an older successful chunk's silence. Default correction executes in a compute isolate; runtime maps and publication stay on the main isolate. Separate playback/export runtimes each own one correction slot; shared native inference priority belongs to the engine scheduler. Blocked and never-admitted plan chunks receive cancellation outcomes. Export currently stops playback and owns a separate sequential processor after releasing playback resources; concurrent playback/export scheduling remains P3.

`READALOUD_ORT_RESOURCE_TRACE=1` reports native session/tensor counts after each operation. `READALOUD_RESOURCE` records context preparation/release and cumulative vector loads. The isolated [native probe](../../tools/p2_native_probe.dart) and [validator](../../tools/run_p2_native_probe.rb) exercise 300 uncached A/B/A chunks plus release/reprepare/new-owner close cycles. The context count is configurable; 12 contexts produce 333 uncached chunks. The isolated failure probe covers malformed private model bytes, truncated private voice bytes with recovery, and native tensor-shape failure followed by valid inference. Source/failure tests do not substitute for native measurements.

The October 24 P2 native run at source commit `3d0366b` passed 333 strict WAV decodes, emitted PCM/duration/provenance checks, 12 session opens/closes and 1,332 tensor releases, with peaks of one session/four tensors and zero retained handles. Recreated-context disposal RSS ranged approximately 1072–1087 MiB over the observed cycles, supporting a bounded plateau for this fixture only. Asset failure/recovery cases also returned to zero handles. Ordinary app Play/Pause/Resume/forward jump/end/replay was exercised separately; these observations do not establish perceptual quality or uninterrupted long-document playback. Detailed immutable build provenance and remaining limits live in #51.

## Source and tests

- [speech_runtime.dart](../../lib/src/services/speech_runtime.dart)
- [speech_worker_pipeline.dart](../../lib/src/services/speech_worker_pipeline.dart)
- [kokoro_speech_worker_processor.dart](../../lib/src/services/kokoro_speech_worker_processor.dart)
- [kokoro_model_runner.dart](../../lib/src/services/kokoro_model_runner.dart)
- [FlutterOnnxruntimePlugin.swift](../../third_party/flutter_onnxruntime/macos/Classes/FlutterOnnxruntimePlugin.swift)
- [speech_runtime_test.dart](../../test/speech_runtime_test.dart)
- [speech_worker_pipeline_test.dart](../../test/speech_worker_pipeline_test.dart)

P0 ran the focused runtime/pipeline tests and full suite on native arm64 Flutter 3.41.5 / Dart 3.11.3. The full run passed 241 tests with one existing PDF integration smoke skip. Deterministic failure/startup fixtures characterize current behavior; they do not establish audible continuity, resource drain, or responsiveness. See P0 for commands, baseline assets and remaining acceptance. The original ignored Intel SDK remains unsuitable for this arm64 host.

## Proposed changes

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/speech-runtime-messaging-boundary.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [boundary candidate metadata contract](../specifications/boundary-candidate-metadata-contract.md)
- [boundary corrected chunk output and reuse](../specifications/boundary-corrected-chunk-output-and-reuse.md)
- [boundary silence thresholds](../specifications/boundary-silence-thresholds.md)
- [generated audio cache](../specifications/generated-audio-cache.md)
- [initial and resumed boundary handling](../specifications/initial-and-resumed-boundary-handling.md)
- [native engine queue policy](../specifications/native-engine-queue-policy.md)
- [platform capability and fallback policy](../specifications/platform-capability-and-fallback-policy.md)
- [playback coordination](../specifications/playback-coordination.md)
- [playback progress and jump mapping](../specifications/playback-progress-and-jump-mapping.md)
- [sendable runtime dto contract](../specifications/sendable-runtime-dto-contract.md)
- [speech runtime command protocol](../specifications/speech-runtime-command-protocol.md)
- [speech runtime event protocol](../specifications/speech-runtime-event-protocol.md)
- [speech runtime lifecycle and ownership](../specifications/speech-runtime-lifecycle-and-ownership.md)
- [speech worker pipeline](../specifications/speech-worker-pipeline.md)
- [trim and cap join correction](../specifications/trim-and-cap-join-correction.md)
