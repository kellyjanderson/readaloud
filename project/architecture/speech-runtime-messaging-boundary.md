# Speech Runtime Messaging Boundary

Reconciled: October 24, 2026
Status: Current source architecture; bounded native baseline recorded in P0

## Implemented structure and limitations

The runtime exposes commands, events, session/generation identity and chunk payload DTOs. `SpeechWorkerPipeline` queues work sequentially and suppresses results for cancelled generations. The facade and queue structure do not imply a long-lived inference isolate: `KokoroSpeechWorkerChunkProcessor.process` spawns one isolate per chunk and constructs a model runner on an uncached request.

The macOS plugin dispatches heavy operations to its serial `ortQueue` and returns results on the main queue. Native sessions and tensors are retained in dictionaries. The model runner does not dispose inference tensors and deliberately skips session closure on macOS. Isolate teardown therefore does not establish native cleanup.

The processor waits for a done message without explicit exit/error/timeout supervision and has an empty dispose method. Cancellation removes queued work/suppresses stale results but does not prove cancellation of active native inference. These are source-confirmed lifecycle gaps; native resource growth and failure behavior need runtime measurement.

The macOS plugin offers opt-in `READALOUD_ORT_RESOURCE_TRACE=1` snapshots after native method handling on its serial queue. They report retained session/tensor counts and errors before dispatching results to Flutter; they do not alter cleanup. The bounded P0 uncached three-chunk export retained three sessions and twelve tensors. This confirms retention for that run, not a long-session growth rate or cleanup guarantee. Reproducible tooling and evidence limits are in [development guidance](../../docs/development.md) and [P0 evidence](https://github.com/kellyjanderson/readaloud/issues/49).

The active ACD specifies persistent document resources, explicit preparation lanes, bounded queues and supervised terminal outcomes. Those targets must not be described as current architecture until implemented and verified.

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
