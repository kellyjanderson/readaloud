# Speech Runtime Messaging Boundary

Reconciled: October 25, 2026; P4 production lineage 295677e
Status: Current source architecture; P2 resident-resource evidence recorded in issue #51

## Implemented structure and limitations

The runtime carries session/generation identity through commands, events and chunk DTOs. `SpeechWorkerPipeline` admits at most eight pending chunks plus one active inference. The active slot includes boundary correction: the pipeline directly awaits the runtime completion hook before starting its next chunk. Predecessor-dependent correction therefore has one active task and no independent queue; per-runtime order is preserved even if native inference finishes faster than correction. Plan submission awaits capacity; cancellation and shutdown bypass the facade's admission queue so they can unblock producers. Eight is the pipeline admission limit, distinct from P3's playable-time lead and shared playback/export priority policy. Kokoro playback inference admission uses four-second low/eight-second high hysteresis and a separate 64-chunk cap; one already admitted operation may overshoot high by its chunk duration. Startup uses two chunks/four seconds or all remaining audio for a short document; impossible count-capped startup reports a terminal error rather than waiting forever.

`KokoroSpeechWorkerChunkProcessor` owns one supervised resident isolate. Resource preparation hashes the model, validates its native session, validates and loads required voice vectors, and returns immutable `PreparedVoiceBinding` records containing model/voice digests, engine/profile identity, document identity and binding revision. Serializable resolved character references preserve the cast assignment decision and join it to the resource record. Document replacement invalidates the snapshot. Active-playback voice edits retain transport-effective references while requested intent is pending; explicit application or initial-buffering supersession prepares the latest intent. Replaced document revisions cannot publish preparation success or failure. Playback supplies this exact reference set and validates it against resident ownership instead of reusing a playback token as a document revision. Native handles stay in the worker/plugin. Repeated chunks select resident vectors; ordinary speaker changes do not load a model or voice file. Requests now capture an expected content fingerprint and binding revision; the resident worker rejects a changed binding before cache lookup or inference. Content identity excludes invocation revision so unchanged validated content can be reused. The model is copied to an immutable content snapshot before its digest is bound and its path is passed to native initialization. Raw inference and predecessor-dependent corrected artifacts use separate immutable, validated publications; see [Audio artifact identity and lifetime](audio-artifact-identity-and-lifetime.md). The engine wires generation/chunk playback pins and export-lifetime pins. The accepted resource/cache probe establishes stale resident binding rejection before events/cache/inference and content-based reuse/misses, not final assignment/playback acceptance. The assignment probe separately observed pause-retained and stop-cleared pins; the supplemental run additionally observed export cancellation/drain, while listening and active-export input acceptance remain in P4.

The worker accepts one command at a time. A timeout reports failure and quarantines admission, suppresses late events, and retains ownership until the native call drains. It does not kill an isolate and pretend native inference stopped, nor create a replacement model while work is undrained. Startup timeout retains the eventual ready channel for cleanup. The final worker shutdown explicitly exits after native disposal, because the background messenger keeps its own port alive. `releaseResources` drains before closing; `dispose` awaits close and isolate exit. A permanently stuck native call can therefore leave shutdown waiting; hard native cancellation is not claimed.

On macOS, a Settings- or environment-selected MLX adapter can instead own serial chunk
inference for Qwen3-TTS 1.7B CustomVoice or Base, Voxtral TTS 4B, or MOSS-TTS v1.5 8B.
The bundled JSON-lines Python helper loads a local model directory in a
separate supervised process and emits mono 24 kHz WAV. It keeps the existing
Dart runtime, bindings, admission, cache and artifact publication path. The
native application delegate requests an orderly worker shutdown on app quit and
uses a bounded termination fallback. Cancellation retires the active process
so it cannot return a late result. The adapter does not yet translate canonical
pronunciation artifacts to model-specific phonemes; it consumes planned text
and preset voice IDs or selected audio references. The versioned synthetic bank supplies 30 identities to Qwen Base/MOSS; its manifest is loaded once and requested WAVs are verified/materialized by content hash. Reference content/transcript enter binding and raw cache identity. The child passes ref_audio/ref_text to the maintained model API; unknown voices/missing references fail without default substitution. Models without at least 30 usable identities remain below voice-library acceptance (CustomVoice 9, local Voxtral 20). No comparative acoustic or latency acceptance is claimed.
MLX uses the same admission policy implementation and existing 64-chunk cap. Fish uses twenty-second low/thirty-second high playable lead; the other MLX adapters retain twelve-second low/twenty-second high lead. The long Fish probe demonstrated complete-WAV generation up to 16.5 seconds, so deliberately suspending inference until twelve seconds remained caused starvation despite faster-than-realtime synthesis overall. The Fish single-chunk startup shortcut likewise requires twenty seconds; two ready chunks can still satisfy startup warmth. These bounds do not guarantee continuity on every machine. Voxtral and Fish Drama use startup warmth; the other MLX adapters start with the first validated chunk. At the five-second MLX warmup deadline, validated audio is admitted even if the target lead is not reached. This bounded wait is included in launch-to-audio measurement and does not establish the two-second requirement. Fish's previous bypass could play a tiny opening turn before the following complete WAV was ready. The Python adapter now reports first-native-packet timing separately from whole-chunk publication; packets still remain in the owned incomplete artifact until the complete WAV passes validation. No progressive native playback claim follows from that telemetry. Voxtral retains full precision by default, with optional saved model-specific in-memory 4-bit quantization; precision participates in model binding and audio-cache identity. Original checkpoint files are retained.
Model installation, launch selection and Voxtral's noncommercial license are documented in
[MLX TTS engine setup](../../docs/mlx-tts-engines.md).

Fish's next planning window now uses that same twenty-second low watermark.
The previous independent eight-second planning gate survived the first refill
repair: a retained long run exhausted its native playlist for 2.367 seconds while
two subsequent WAVs took 13.428 seconds to arrive. Chunk admission still owns
the duration/count bounds; the planner admits only one bounded window at a time.
Initial MLX planning is also bounded to three chunks/scenes instead of requesting
the complete prepared range. Later windows retain the existing revision and
cancellation owner.

ReaderController resource preparation makes one attempt per captured playback
or export intent. The playback pump alone schedules a newer intent. The old
inner retry loop kept revalidating Fish references after document replacement in
the retained release hang; its AOT frame checked pre-await revision values.
Current-intent guards run before native admission and after success/failure;
binding state is committed before publishing stage completion. Pending resource
work responds to the same Pause action shown by the reading surface. Unit
stale-success/error tests and the running file-import/annotation fixture cover
the repaired path; the original hang evidence remains retained in #111/#113.

The [accepted resource run 2](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395918850) at harness source `25f1dfe` recorded four inferences, two balanced session opens/closes, sixteen tensor releases and final zero sessions/tensors with no native errors. It shares unchanged production behavior with `295677e`; it is not a playback, RSS-isolation or listening result. Assignment295 subsequently failed its listening timeout and then cleaned up to zero sessions/tensors/sources/pins/tasks. The [e18c81d supplemental run](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396165816) exited zero with 133 inferences, three balanced session opens/closes and 532 tensor releases, peak one session/four tensors and final zero native resources, sources, pins and preparation tasks. This bounded cleanup evidence does not establish listening or input during active export.

The macOS plugin serializes ONNX calls on `ortQueue`. The model runner disposes every allocated input and output tensor on success and failure before closing the session, including on macOS. Partially registered native outputs roll back if metadata extraction fails. The former per-chunk macOS close workaround is replaced by resident ownership and explicit drain/close. Native resource counts and close-cycle evidence belong in [P2](https://github.com/kellyjanderson/readaloud/issues/51), distinct from acoustic quality or UI proof.

The optional `ResourcePreparationCapable` engine bridge gates document speech readiness on resource preparation and preserves failed/stale preparation states. Direct speak/export paths also prepare resources. Pause and jumps retain the context; document replacement, end-of-document and shutdown release it after drain. Natural completion during export records an epoch-owned release debt and closes after the lease drains, provided no replacement/replay has superseded it. Replay re-prepares before synthesis and joins any in-flight player stop/clear reset before replacing sources. Runtime shutdown also drains tracked boundary-correction futures and suppresses their stale terminals. Correction validates session/generation/work-item identity before work and after either outcome; cancellation suppresses publication while the running compute isolate drains. Failed predecessors clear their trailing-silence reference, so later correction receives unknown predecessor context rather than an older successful chunk's silence. Default correction executes in a compute isolate and returns a new corrected artifact path. It never edits the raw cache file. Runtime maps and publication stay on the main isolate; successful predecessor identity and trailing silence are cleared together on failure/cancellation. Separate playback/export runtimes each own one correction slot and non-owning cancellable leases of one prioritized native owner. Queued cancellation settles independently of the export lead gate; active native work is not preempted. Blocked and never-admitted plan chunks receive cancellation outcomes. Concurrent export no longer stops playback; its integrated acceptance remains recorded in P3.

`READALOUD_ORT_RESOURCE_TRACE=1` reports native session/tensor counts after each operation. `READALOUD_RESOURCE` records context preparation/release and cumulative vector loads. The isolated [native probe](../../tools/p2_native_probe.dart) and [validator](../../tools/run_p2_native_probe.rb) exercise 300 uncached A/B/A chunks plus release/reprepare/new-owner close cycles. The context count is configurable; 12 contexts produce 333 uncached chunks. The isolated failure probe covers malformed private model bytes, truncated private voice bytes with recovery, and native tensor-shape failure followed by valid inference. Source/failure tests do not substitute for native measurements.

The October 24 P2 native run at source commit `3d0366b` passed 333 strict WAV decodes, emitted PCM/duration/provenance checks, 12 session opens/closes and 1,332 tensor releases, with peaks of one session/four tensors and zero retained handles. Recreated-context disposal RSS ranged approximately 1072–1087 MiB over the observed cycles, supporting a bounded plateau for this fixture only. Asset failure/recovery cases also returned to zero handles. Ordinary app Play/Pause/Resume/forward jump/end/replay was exercised separately; these observations do not establish perceptual quality or uninterrupted long-document playback. Detailed immutable build provenance and remaining limits live in #51.

A current integrated-lineage run used production source `1767ed6` and the corrected probe harness delta later committed as `b329c2c`; the run manifest retains checkout HEAD `1767ed6` and the executable hash. The isolated arm64 P2 bundle completed 306 uncached inferences over three resource contexts. Three sessions opened/closed, 1,224 tensors were released, peak counts were one session/four tensors, final counts were zero/zero, and all 306 WAVs passed strict format/hash/duration validation. Repeated same-voice PCM was bit-identical for this fixed utterance. One-second RSS sampling peaked at 1,235.4 MiB across the whole run; during the first context's post-warm 300-chunk interval it ranged 915.2–1,147.7 MiB, falling from 1,144.8 MiB to 929.2 MiB. Runtime model/voice hashes matched the bundle. This supports bounded resource use for this fixture, not a universal memory threshold or long-duration live-playback stability. The [current P2 evidence](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6407243488) preserves provenance and artifacts. Two earlier harness attempts failed before the full run because the probe omitted required binding metadata and then reused cached content; both cleaned up to zero handles. The request factory now supplies binding fingerprint/revision and unique synthesis identity, with focused test coverage.

## Persistent model download identity

MLX model files live under Application Support, separate from the app bundle, checkout and build outputs. Normal debug/release builds use the same bundle identity and therefore the same cache. Deliberately isolated probe bundle identities remain separate macOS sandboxes. The Python loader checks every configured candidate with `local_files_only` before requesting network metadata; a complete pinned Drama snapshot is checked against its required-file catalog and reused offline. Cache hits explicitly report Using downloaded speech model files. Generic snapshots require weights as well as config and validate declared weight-index shards.

If files are missing, the loader uses Hugging Face's dry-run metadata to establish the total and identify cached files, pins that metadata revision for the transfer, and downloads into one persistent app cache. Errors propagate for retry in that same destination; a network error never starts a second copy in another cache. The maintained Hub downloader owns blob locks, reuse and resumption. Its aggregate reconstruction counter includes resumed work; the UI adds already cached bytes and uses the full manifest total, rather than treating fresh network transfer as whole-model progress. Unknown sizes remain unknown. See the [Hub download API](https://huggingface.co/docs/huggingface_hub/guides/download) and [issue #119](https://github.com/kellyjanderson/readaloud/issues/119). Reuse does not imply that an interrupted snapshot is complete, nor that loading weights into memory is a new download.

## Source and tests

- [speech_runtime.dart](../../lib/src/services/speech_runtime.dart)
- [speech_worker_pipeline.dart](../../lib/src/services/speech_worker_pipeline.dart)
- [kokoro_speech_worker_processor.dart](../../lib/src/services/kokoro_speech_worker_processor.dart)
- [kokoro_model_runner.dart](../../lib/src/services/kokoro_model_runner.dart)
- [FlutterOnnxruntimePlugin.swift](../../third_party/flutter_onnxruntime/macos/Classes/FlutterOnnxruntimePlugin.swift)
- [speech_runtime_test.dart](../../test/speech_runtime_test.dart)
- [speech_worker_pipeline_test.dart](../../test/speech_worker_pipeline_test.dart)
- [p2_native_probe_test.dart](../../test/p2_native_probe_test.dart)

P0 ran the focused runtime/pipeline tests and full suite on native arm64 Flutter 3.41.5 / Dart 3.11.3. The full run passed 241 tests with one existing PDF integration smoke skip. Deterministic failure/startup fixtures characterize current behavior; they do not establish audible continuity, resource drain, or responsiveness. See P0 for commands, baseline assets and remaining acceptance. The original ignored Intel SDK remains unsuitable for this arm64 host.

## Design and remaining acceptance

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

## MLX model preparation and replacement

The controller prepares a selected MLX model at launch and immediately on a
Settings selection, independently of document binding preparation. The engine's
single admission owner serializes model preparation and synthesis. One current
replacement loop reads the latest desired engine after old resources drain;
rapid selection changes retire an obsolete preparation before the next model
starts. UI callbacks carry their owning engine identity and old callbacks cannot
publish new-session state. Document/cast preferences and reading position remain
in the controller. Shutdown is shared/idempotent; it retires an active Python
load/inference before waiting for the admission drain.

A playback/export lease forwards cancellation only for its own active generation.
It cannot cancel another lease with the same generation string. The Python
supervisor reserves admission before process start, associates stream/exit
callbacks with their child, and retires malformed, timed-out or cancelled children.
A replacement process reloads the recorded model and verifies its identity before
accepting synthesis. Cache identity includes the loaded model identity, helper
version, voice/reference identity and text. Custom local model identity includes
config hash and weight file path/size/mtime; it is not a full weight-byte audit.
Artifact lookup/publication run on an isolate; temporary WAVs have unique
request-owned directories. Queue bounds remain eight pending pipeline chunks and
three pending shared admissions, with one active synthesis.

The native app and Python child each sample their own physical footprint;
sandbox policy forbids the app from querying the child's libproc counters.
One child-owned daemon emits memory telemetry every two seconds through the
locked JSON-lines writer. The supervisor combines it with one in-flight native
self-query, ignores retired-child messages, and retires the worker at 99 GB or
after 30 seconds without telemetry. Child exit owns sampler cancellation.
These are sampled guardrails, not a proved hard real-time 100 GB bound.

The worker consumes all model-generated pieces and validates finite mono output
and constant rate. An explicitly final, streaming, zero-sample packet is a
terminal marker; it does not erase preceding audio. Empty unmarked packets,
non-finite/multichannel output, rate changes, data after the terminal marker and
generations containing no audio still fail. The iterator is drained/closed so a
late producer exception is not silently converted into success.

Validated packets are written incrementally to a unique PCM16 WAV with its
header updated and flushed after each packet. The existing single Python child
owns the writer; the admitted Dart request owns its unique persistent attempt
directory under `generated-audio/mlx-raw-v1/incomplete`. Initial request metadata
records `complete: false` and source/voice/model/session/generation/chunk identity.
Cancellation and failures retire/join the child before request cleanup. Failed
or cancelled attempts containing WAV data are retained without automatic
eviction; failure text identifies the retained prefix where available. These
files never qualify as complete cache hits or automatically start playback.
Resume/stitching inside a failed text chunk is not implemented because token to
audio alignment has not been established. Empty attempts can be removed.

On successful generator completion, the WAV is published with a no-clobber hard
link; only its duplicate staging link is removed. Dart removes the attempt copy
only after immutable artifact publication succeeds and a joined worker-isolate
checksum comparison confirms identical WAV bytes. A competing different render
or unverifiable published file leaves the attempt intact. Previously published audio
and failed attempt prefixes survive later failures and retries. The PCM16
conversion matches the prior MLX Audio writer, so valid existing cache entries
retain their engine identity and need not be rendered again. See [#120](https://github.com/kellyjanderson/readaloud/issues/120)
for boundary, malformed-tail, retry and process-termination regression evidence.
The artifact
store, boundary correction and export carry the WAV sample rate instead of
assuming Kokoro's 24 kHz. Boundary derivative identity was versioned to prevent
reuse of derivatives computed with the old timing assumption.

Drama has bf16/8-/4-bit pinned repository entries and 43 selectable reference
voices including 13 cached Fish Official designed references. For Drama, the Dart
worker derives a sorted reference set from the current document/revision's
prepared bindings, partitions casts larger than sixteen into bounded groups,
and sends the selected voice plus that group's audio/transcripts. The Python
adapter assigns native `<|speaker:N|>` slots and calls MLX Audio's existing
multi-reference generator. Slot ownership never escapes into persistent character
identity. MLX Audio owns encoding and prefill reuse through its existing
content-keyed voice cache; Read Aloud adds no tensor/history cache. Ordered
reference digests participate in raw artifact identity, and only Drama's engine
version changes for this binding protocol. Non-Drama adapters retain their prior
identity and behavior. Qualified bf16 Drama packs ordered, contiguous source turns
into one native scene call, targeting 75 words and at most sixteen turns. The
second planning pass cannot extend past the realized annotation horizon. Other
model contexts retain per-character chunks. Native per-turn timestamps remain
unavailable; word highlighting uses the existing approximate duration mapping.
Source regressions establish ownership, emitted-sample retention
and format behavior. They do not establish real Drama acoustic quality, sustained
memory, M3 performance or uninterrupted chapter playback; native evidence is
recorded in #111.


Scene and delivery qualification uses the bundled immutable bf16 repository file
manifest, not the selected engine name or a local folder's name. The native
Python owner verifies file contents with Hugging Face Hub's hashing utility.
Its app-owned verification receipt is reusable only while the directory, pinned
manifest and every file's device/inode/size/mtime/ctime remain identical. A
changed file is rechecked; a mismatch disables native scenes and model-specific
whisper/shout lowering while retaining canonical content intent. The first
verification reports completed bytes and may add preparation latency. It runs
in the existing single native model-load owner, with selection cancellation and
shutdown retiring that process; it adds no queue or UI-thread hashing. This is
capability qualification, not portable publishing metadata or a security claim
against hostile file replacement. Source checks cover altered/missing files,
receipt reuse and per-request tokenization capability isolation. Runtime and
startup acceptance remain separate gates in #111.
