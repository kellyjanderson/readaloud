# Audio Export and Headless Execution

Reconciled: November 12, 2026; S9.1 shared RIFF/PCM export and analysis core (#146), RC2 #90 complete-range export source; retained P4 native evidence e18c81d
Status: Bounded P4 native export/cancellation evidence; active-export input and human listening unverified

## Implemented structure and limitations

Launch options select interactive reading or headless execution. The headless runner imports inputs and uses the TTS engine instead of a separate synthesis implementation. Export assembles finalized chunk WAVs and metadata. Pronunciation and sentence probes exercise speech generation and emit diagnostic artifacts.

The export, pronunciation and sentence runners share `HeadlessReaderSession`
for controller/importer construction, initialization, exact requested-voice
resolution and bounded speed options. Each runner keeps its workload and reports,
and closes its one session in `finally`, including missing voice and initialization
failure. Close is idempotent and delegates to the existing controller disposal;
this extraction adds no worker, queue, cancellation policy or stronger native
shutdown claim. `headless_reader_session_test.dart` covers option ordering,
missing-voice refusal and failure cleanup. Native process exit remains separate
acceptance under #151/#114.

Offline model probes use `tools/mlx_protocol_client.py` to own one production
JSON-lines child and one request at a time through standard `subprocess` and
`selectors`. Metadata is a data-only worker command derived from adapter lists
and bundled model/reference catalogs. Protocol buffers/events are bounded and
identity checked; packetized completed PCM must equal ordered packet PCM.
Timeout, cancellation and protocol failure retire/reap the owned child, and
complete receipts require acknowledged shutdown and successful process exit.
Benchmark/voice-bank workload and acoustic policy remain separate. No production
seed override exists, so those receipts report null rather than inventing a seed.
VoiceDesign authoring drains its generator before publishing a reference; this
change regenerated no assets. Descriptor-based QA staging creates an independent
root, includes current Fish variants/reference caches and refuses overwrite and
escaping symlinks. Fake-process/catalog/generator tests establish these tool
contracts; actual model/app, native timing and listening are separate #151 gates.

`ExportedAudioAssembler` is a stateful main-isolate supervisor with one active request and no waiting queue. Overlap is rejected. Each accepted request has a monotonic owner-local identity and a dedicated pure Dart isolate; only DTOs, file paths, progress and the terminal result cross the port. The worker scans RIFF sections, verifies matching PCM formats, copies audio in at most 64 KiB blocks and streams one chunk's JSON metadata at a time. It retains the request graph and per-chunk format descriptors, not whole-document PCM. WAV encoding, metadata traversal, file I/O and publication are worker-owned. Source chunks remain read-only.

Cancellation is cooperative between bounded reads/writes and at an explicit staged/commit handshake. `cancel()` suppresses publication before commit authorization; after authorization, the short synchronous publication step completes and returns its result. `shutdown()` closes intake, cancels staging and awaits worker exit and file/temp cleanup. The default five-minute deadline requests cancellation and reports a timeout after drain; it does not pretend an unresponsive filesystem operation was forcibly cancelled. Worker errors/exit become terminal failures; a previous request's callbacks cannot clear a newer request. The engine owns document/session invalidation and must call these lifecycle seams. Progress callbacks are short main-isolate notifications, never assembly work.

Audio and sidecar are flushed to a unique staging directory beside the destination. Publication renames the complete WAV first and sidecar last as its commit marker. Existing outputs are backed up and restored on ordinary publication errors; if rollback itself fails, the error names the retained recovery directory. Each rename is atomic, but two filesystem paths are not crash-atomic as a pair. Cancellation before commit leaves prior outputs intact. No cache chunk may be used as the output path.

Durations come from decoded frame counts rather than the caller's possibly stale duration hints: the result carries microsecond-rounded duration, sidecar milliseconds round to the nearest millisecond, and exact frame counts/sample rate remain recorded. Ancillary RIFF sections and odd chunk padding are parsed; malformed lengths, unsupported/non-PCM formats, incompatible chunk formats and output exceeding the RIFF size limit fail before publication.

Export/probe outputs are local artifacts and are excluded from normal source control. Audio correctness requires comparing emitted output with the intended phrase and routing, not merely a successful process exit. Model availability, native plugin lifetime and toolchain compatibility affect all these routes.

A new controller export is refused while voice choices are pending, with an apply-first message. Accepted export work snapshots document, planning context, exact realization/resource identity and assignment revision before planning, and guards document/assignment ownership at preparation and dispatch. Already dispatched work uses its captured references rather than borrowing later requested choices. Export owns a separate resident planner/tokenizer/runtime, shares the single native synthesis admission owner with playback, and yields inference admission below playback's low-water lead. It does not stop playback or create a second native model session. Native resource replacement cancels and drains the export owner from initialization onward; direct headless callers prepare their own revision-zero context, while controller requests validate supplied resident bindings. Accepted corrected artifacts remain pinned through assembly and runtime/planner drain, including cancellation/failure. Assembly receives ordered per-chunk metadata after bounded synthesis windows; metadata grows with document length, but whole PCM is never accumulated on the UI isolate.

RC2 #90 also accepts a complete committed multi-range checkpoint. The controller reads all its ranges, validates their contiguous coverage/totals and merges existing derived data on a worker before planning export from the beginning. Global word offsets and source ordering cover the full book, even when playback currently displays its last fragment. Required cast resources are prepared against the complete graph while retaining the resident playback document identity. Partial, cancelled or corrupt checkpoints cannot dispatch an audio export. Whole-document graph metadata is materialized for explicit export; ordinary opening/replay remains incremental. Source tests with a recording engine establish request coverage and failure boundaries, not synthesized or live audio. Current-candidate native export/playback/resource competition remains an acceptance requirement.

## Shared RIFF/PCM structure

The first [C03 consumer group](https://github.com/kellyjanderson/readaloud/issues/146)
uses `pcm_wav.dart` for immutable `PcmFormat`/`PcmWavLayout`, structural scanning
and canonical PCM headers. The byte-buffer adapter and `pcm_wav_io.dart` file
adapter drive the same scan state machine. It retains one fmt/data descriptor,
never a chunk list; requests are only the 12-byte RIFF header, 8-byte chunk headers
and 16-byte PCM fmt prefix. Ancillary payloads and fmt extensions are skipped by
offset, including odd-byte padding. Exactly one fmt and data chunk are required,
in either order. RIFF signature/declared extent, chunk bounds/padding, integer PCM
format code, nonzero rate/channels, supported bit depth, byte rate/block alignment
and whole-frame data length are validated before consumers receive a layout.

Export keeps its integer PCM8/16/24/32 subset, native sample rates/channels and
whole-export format matching. The shared header includes final odd padding in
RIFF size but excludes it from data size. Assembly copies source sample bytes
unchanged in the existing 64 KiB blocks, discards source pad bytes and writes one
final pad when needed. Existing worker admission, request identity, staging,
commit handshake, timeout, cancellation, publication and scene-turn metadata
remain with `ExportedAudioAssembler`. The file adapter introduces no owner,
queue, task or file lifetime: the caller serializes its handle, selects the worker
execution context and closes it in `finally`. Checkpoints bracket every bounded
structural read; worker cancellation discards both stale success and failure,
drains cleanup and preserves the established terminal-result route.

Analysis keeps a separate PCM16-only policy and its existing sample normalization
(including `abs(-32768) / 32767`), PCM/WAV hashes, envelope, frame accounting and
microsecond-rounded duration for valid inputs. It now finds fmt by structure
rather than assuming fixed offsets, so metadata, extended PCM fmt and
data-before-fmt layouts are supported. This deliberately tightens invalid-input
behavior: malformed extents, duplicate/missing fmt/data, truncated headers,
payloads or padding, non-PCM codes (including float/extensible), zero fields,
inconsistent byte rate/alignment and partial frames raise `FormatException`.
Earlier analysis could accept some of these or fail incidentally; invalid-input
parity is not claimed. Valid integer PCM8/24/32 still fails analysis's explicit
PCM16 policy with `StateError`.

The maintained [wav 1.5.0 package](https://pub.dev/packages/wav) was evaluated for
this extraction. Its public `Wav.readFile`/`read` API materializes complete bytes
and decoded `Float64List` channels; its upstream
[file adapter](https://github.com/liamappelbe/wav/blob/master/lib/wav_io.dart)
uses `File.readAsBytes`, and its
[byte reader](https://github.com/liamappelbe/wav/blob/master/lib/bytes_reader.dart)
walks an already resident buffer. This does not meet the concrete requirements
for bounded random-access structural reads and byte-preserving streamed assembly.
No dependency was installed or adopted; this is a candidate-specific evaluation,
not a claim that every WAV library was surveyed.

Independent source fixtures cover 24/44.1/48 kHz, supported integer depths and
mono/stereo, exact payload preservation, odd metadata/data padding, fmt ordering,
extensions, malformed/refusal cases and PCM16 analysis arithmetic. A caller-owned
handle instrumented against a sparse file with 512 MiB PCM and 256 MiB metadata
records just `[12, 8, 8, 16, 8]` bytes requested (52 bytes total), establishing
bounded structural scanning rather than whole-payload loading. Existing
cancellation/drain/deadline, previous-output restoration, alias protection and
request isolation tests remain applicable. These are source-level results;
current-candidate native emitted-audio/export comparison and human listening
remain required before final S9 acceptance. Artifact validation, boundary
correction, Kokoro encoding and package validation retain their own adapters;
this group does not complete [C03/#114](https://github.com/kellyjanderson/readaloud/issues/114).

## Bounded P4 native evidence

The engine accepts optional assembler injection at `843f6b5`; the default remains `ExportedAudioAssembler`. The `e18c81d` repair changes only the supplemental probe's early-release latch and timeout-state cleanup. Its diagnostic hold waits before actual assembly and must not be described as CPU-heavy export work.

The [supplemental audit](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396165816) verified cancellation while the held export retained 118 pins: playback had stopped, then export drained before the new Heart playback acknowledgment. No cancelled WAV/sidecar was published. A1/A2 each covered words [0,134) in 11 chunks with 1,219,944 frames at 24 kHz and identical PCM (also matching P3); B covered the same words with different PCM and 1,177,800 frames. Those three exports and a 118-chunk long export strictly decoded and exactly matched ordered source PCM. The retained audit validated 135 unique artifacts; final native resources, sources, pins and tasks were zero. The [root acceptance audit](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396216177) additionally compared A1 byte-for-byte with the accepted P3 export. This establishes bounded ownership and emitted realization, not perceptual quality.

Actual UI action count was zero after CUA binding timeouts. The blocker was recorded before diagnostic release; readiness signals are not input proof. Export-phase debug frame totals included a 63.745 ms maximum; callback receipt intervals are not input latency or smoothness acceptance. Input during active export and human listening remain open.

## Source and tests


- [app_launch_options.dart](../../lib/src/services/app_launch_options.dart)
- [headless_session_runner_io.dart](../../lib/src/services/headless_session_runner_io.dart)
- [pcm_wav.dart](../../lib/src/services/pcm_wav.dart)
- [pcm_wav_io.dart](../../lib/src/services/pcm_wav_io.dart)
- [wav_analysis_service.dart](../../lib/src/services/wav_analysis_service.dart)
- [exported_audio_assembler.dart](../../lib/src/services/exported_audio_assembler.dart)
- [pronunciation_probe_runner_io.dart](../../lib/src/services/pronunciation_probe_runner_io.dart)
- [sentence_probe_runner_io.dart](../../lib/src/services/sentence_probe_runner_io.dart)
- [app_launch_options_test.dart](../../test/app_launch_options_test.dart)
- [pcm_wav_test.dart](../../test/pcm_wav_test.dart)
- [pcm_wav_io_test.dart](../../test/pcm_wav_io_test.dart)
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

## Portable book publishing

File → **Save Audio Book…** (Cmd-S) writes a `radoc-v5` ZIP package through the
platform save panel. It includes complete prepared ranges, analysis/Character
state, canonical directions, voice intent, scene dependencies and available raw
and final WAVs. Audio coverage may be partial and is explicit; missing audio is
never EOF. The legacy controller export default retains v4 JSON when no audio is
available; the Save Audio Book UI explicitly requests v5, including a book whose
rendering has not started. Original input/checkpoint paths are protected.

The package owner uses the maintained archive codec plus bounded streaming I/O;
it admits one worker and no queue. Limits are 10,000 members, 64 MiB per member,
2 GiB total archive, 2 MiB manifest and 8 MiB directory. Export stores members
without compression and atomically renames a staged archive after current-owner
admission; import also accepts bounded raw DEFLATE. Cancellation suppresses stale
publication and drains before cleanup. Metadata and PCM copying stay off the UI
isolate. The signed macOS target grants only user-selected read/write file access
for NSSavePanel, retaining sandboxing and app-scoped bookmarks; see the published
[S6 R2 amendment](../interim/s6-r2/publishing-access.md).

The existing exporter additionally accepts an awaited per-scene publication
callback, cancellation/current predicate and source-word offset. Selective book
regeneration sends one bounded plan with no continuation to this exporter. Its
existing runtime, tokenizer, resource admission and assembly lifecycle retain
ownership; export cancellation does not tear down concurrently playing saved
audio. Saved-audio generations do not compete for inference, so their bounded
scene exports can run below the playback low-water mark; waiting for that lead
would deadlock a missing-scene refill. Ordinary synthesized playback retains its
existing priority rule. Dedicated source tests exercise callback provenance, pins and drain. Real
save-panel access, copied offline replay, launch timing and emitted continuity
remain separately qualified in [#137](https://github.com/kellyjanderson/readaloud/issues/137).
