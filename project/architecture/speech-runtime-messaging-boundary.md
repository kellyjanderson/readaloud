# Speech Runtime Messaging Boundary

Reconciled: October 24, 2026
Status: Current source architecture; runtime validation not refreshed

## Implemented structure and limitations

The runtime exposes commands, events, session/generation identity and chunk payload DTOs. `SpeechWorkerPipeline` queues work sequentially and suppresses results for cancelled generations. The facade and queue structure do not imply a long-lived inference isolate: `KokoroSpeechWorkerChunkProcessor.process` spawns one isolate per chunk and constructs a model runner on an uncached request.

The macOS plugin dispatches heavy operations to its serial `ortQueue` and returns results on the main queue. Native sessions and tensors are retained in dictionaries. The model runner does not dispose inference tensors and deliberately skips session closure on macOS. Isolate teardown therefore does not establish native cleanup.

The processor waits for a done message without explicit exit/error/timeout supervision and has an empty dispose method. Cancellation removes queued work/suppresses stale results but does not prove cancellation of active native inference. These are source-confirmed lifecycle gaps; native resource growth and failure behavior need runtime measurement.

The active ACD specifies persistent document resources, explicit preparation lanes, bounded queues and supervised terminal outcomes. Those targets must not be described as current architecture until implemented and verified.

## Source and tests

- [speech_runtime.dart](../../lib/src/services/speech_runtime.dart)
- [speech_worker_pipeline.dart](../../lib/src/services/speech_worker_pipeline.dart)
- [kokoro_speech_worker_processor.dart](../../lib/src/services/kokoro_speech_worker_processor.dart)
- [kokoro_model_runner.dart](../../lib/src/services/kokoro_model_runner.dart)
- [FlutterOnnxruntimePlugin.swift](../../third_party/flutter_onnxruntime/macos/Classes/FlutterOnnxruntimePlugin.swift)
- [speech_runtime_test.dart](../../test/speech_runtime_test.dart)
- [speech_worker_pipeline_test.dart](../../test/speech_worker_pipeline_test.dart)

Tests listed here are existing evidence locations, not a claim that they passed in this review. The bundled Intel Dart executable cannot run in the current Apple Silicon execution environment.

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
