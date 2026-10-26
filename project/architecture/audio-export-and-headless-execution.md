# Audio Export and Headless Execution

Reconciled: October 25, 2026; P4 source e18c81d
Status: Bounded P4 native export/cancellation evidence; active-export input and human listening unverified

## Implemented structure and limitations

Launch options select interactive reading or headless execution. The headless runner imports inputs and uses the TTS engine instead of a separate synthesis implementation. Export assembles finalized chunk WAVs and metadata. Pronunciation and sentence probes exercise speech generation and emit diagnostic artifacts.

`ExportedAudioAssembler` is a stateful main-isolate supervisor with one active request and no waiting queue. Overlap is rejected. Each accepted request has a monotonic owner-local identity and a dedicated pure Dart isolate; only DTOs, file paths, progress and the terminal result cross the port. The worker scans RIFF sections, verifies matching PCM formats, copies audio in at most 64 KiB blocks and streams one chunk's JSON metadata at a time. It retains the request graph and per-chunk format descriptors, not whole-document PCM. WAV encoding, metadata traversal, file I/O and publication are worker-owned. Source chunks remain read-only.

Cancellation is cooperative between bounded reads/writes and at an explicit staged/commit handshake. `cancel()` suppresses publication before commit authorization; after authorization, the short synchronous publication step completes and returns its result. `shutdown()` closes intake, cancels staging and awaits worker exit and file/temp cleanup. The default five-minute deadline requests cancellation and reports a timeout after drain; it does not pretend an unresponsive filesystem operation was forcibly cancelled. Worker errors/exit become terminal failures; a previous request's callbacks cannot clear a newer request. The engine owns document/session invalidation and must call these lifecycle seams. Progress callbacks are short main-isolate notifications, never assembly work.

Audio and sidecar are flushed to a unique staging directory beside the destination. Publication renames the complete WAV first and sidecar last as its commit marker. Existing outputs are backed up and restored on ordinary publication errors; if rollback itself fails, the error names the retained recovery directory. Each rename is atomic, but two filesystem paths are not crash-atomic as a pair. Cancellation before commit leaves prior outputs intact. No cache chunk may be used as the output path.

Durations come from decoded frame counts rather than the caller's possibly stale duration hints: the result carries microsecond-rounded duration, sidecar milliseconds round to the nearest millisecond, and exact frame counts/sample rate remain recorded. Ancillary RIFF sections and odd chunk padding are parsed; malformed lengths, unsupported/non-PCM formats, incompatible chunk formats and output exceeding the RIFF size limit fail before publication.

Export/probe outputs are local artifacts and are excluded from normal source control. Audio correctness requires comparing emitted output with the intended phrase and routing, not merely a successful process exit. Model availability, native plugin lifetime and toolchain compatibility affect all these routes.

A new controller export is refused while voice choices are pending, with an apply-first message. Accepted export work snapshots document, planning context, exact realization/resource identity and assignment revision before planning, and guards document/assignment ownership at preparation and dispatch. Already dispatched work uses its captured references rather than borrowing later requested choices. Export owns a separate resident planner/tokenizer/runtime, shares the single native synthesis admission owner with playback, and yields inference admission below playback's low-water lead. It does not stop playback or create a second native model session. Native resource replacement cancels and drains the export owner from initialization onward; direct headless callers prepare their own revision-zero context, while controller requests validate supplied resident bindings. Accepted corrected artifacts remain pinned through assembly and runtime/planner drain, including cancellation/failure. Assembly receives ordered per-chunk metadata after bounded synthesis windows; metadata grows with document length, but whole PCM is never accumulated on the UI isolate.

## Bounded P4 native evidence

The engine accepts optional assembler injection at `843f6b5`; the default remains `ExportedAudioAssembler`. The `e18c81d` repair changes only the supplemental probe's early-release latch and timeout-state cleanup. Its diagnostic hold waits before actual assembly and must not be described as CPU-heavy export work.

The [supplemental audit](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396165816) verified cancellation while the held export retained 118 pins: playback had stopped, then export drained before the new Heart playback acknowledgment. No cancelled WAV/sidecar was published. A1/A2 each covered words [0,134) in 11 chunks with 1,219,944 frames at 24 kHz and identical PCM (also matching P3); B covered the same words with different PCM and 1,177,800 frames. Those three exports and a 118-chunk long export strictly decoded and exactly matched ordered source PCM. The retained audit validated 135 unique artifacts; final native resources, sources, pins and tasks were zero. The [root acceptance audit](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396216177) additionally compared A1 byte-for-byte with the accepted P3 export. This establishes bounded ownership and emitted realization, not perceptual quality.

Actual UI action count was zero after CUA binding timeouts. The blocker was recorded before diagnostic release; readiness signals are not input proof. Export-phase debug frame totals included a 63.745 ms maximum; callback receipt intervals are not input latency or smoothness acceptance. Input during active export and human listening remain open.

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

Focused tests exercise source-order PCM across block boundaries, ancillary RIFF sections, frame-derived durations, staged cancellation, overlap rejection, deadline/shutdown drain, retry isolation, malformed/mismatched inputs and rollback after sidecar publication failure. They use explicit completion barriers rather than sleep-based synchronization. These source tests do not establish native export/playback competition, frame timing, audible continuity or perceptual quality; P3's bounded native matrix is recorded in [P3](https://github.com/kellyjanderson/readaloud/issues/52); current assignment/frame/input acceptance remains in [P4](https://github.com/kellyjanderson/readaloud/issues/53) and [FINAL](https://github.com/kellyjanderson/readaloud/issues/54). Use the pinned native arm64 toolchain in [development guidance](../../docs/development.md).

## Design and remaining acceptance

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/audio-export-and-headless-execution.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

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
