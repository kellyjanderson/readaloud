# Audio Export and Headless Execution

Reconciled: October 24, 2026
Status: Current source architecture; runtime validation not refreshed

## Implemented structure and limitations

Launch options select interactive reading or headless execution. The headless runner imports inputs and uses the TTS engine instead of a separate synthesis implementation. Export assembles finalized chunk WAVs and metadata. Pronunciation and sentence probes exercise speech generation and emit diagnostic artifacts.

The assembler reads and processes audio data and constructs output buffers. Asynchronous file APIs do not establish a dedicated CPU worker for assembly. Interactive export therefore needs execution-context review; headless command completion is not proof of responsive UI export.

Export/probe outputs are local artifacts and are excluded from normal source control. Audio correctness requires comparing emitted output with the intended phrase and routing, not merely a successful process exit. Model availability, native plugin lifetime and toolchain compatibility affect all these routes.

## Source and tests

- [app_launch_options.dart](../../lib/src/services/app_launch_options.dart)
- [headless_session_runner_io.dart](../../lib/src/services/headless_session_runner_io.dart)
- [exported_audio_assembler.dart](../../lib/src/services/exported_audio_assembler.dart)
- [pronunciation_probe_runner_io.dart](../../lib/src/services/pronunciation_probe_runner_io.dart)
- [sentence_probe_runner_io.dart](../../lib/src/services/sentence_probe_runner_io.dart)
- [app_launch_options_test.dart](../../test/app_launch_options_test.dart)
- [exported_audio_assembler_test.dart](../../test/exported_audio_assembler_test.dart)
- [pronunciation_probe_runner_io_test.dart](../../test/pronunciation_probe_runner_io_test.dart)
- [sentence_probe_runner_io_test.dart](../../test/sentence_probe_runner_io_test.dart)

Tests listed here are existing evidence locations, not a claim that they passed in this review. The bundled Intel Dart executable cannot run in the current Apple Silicon execution environment.

## Proposed changes

See [prepared document runtime ACD](../acd/prepared-document-runtime.acd) and its [implementation plan](../planning/prepared-document-runtime.plan). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/audio-export-and-headless-execution.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use an ACD and plan.

- [audio export assembly](../specifications/audio-export-assembly.md)
- [command line mode selection](../specifications/command-line-mode-selection.md)
- [generated audio cache](../specifications/generated-audio-cache.md)
- [headless synthesis session](../specifications/headless-synthesis-session.md)
- [in app audio export workflow](../specifications/in-app-audio-export-workflow.md)
- [native engine queue policy](../specifications/native-engine-queue-policy.md)
- [platform capability and fallback policy](../specifications/platform-capability-and-fallback-policy.md)
- [playback coordination](../specifications/playback-coordination.md)
- [sendable runtime dto contract](../specifications/sendable-runtime-dto-contract.md)
- [speech qa debug tooling](../specifications/speech-qa-debug-tooling.md)
- [speech runtime command protocol](../specifications/speech-runtime-command-protocol.md)
- [speech runtime event protocol](../specifications/speech-runtime-event-protocol.md)
- [speech runtime lifecycle and ownership](../specifications/speech-runtime-lifecycle-and-ownership.md)
