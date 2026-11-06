# Local MLX TTS engines

Read Aloud offers Fish Audio Drama 3 (bf16, 8-bit and 4-bit), Qwen3-TTS
1.7B Base/CustomVoice, Voxtral TTS 4B and MOSS-TTS v1.5. Kokoro remains the
default. On macOS choose **Read Aloud > Settings… > Text-to-speech engine**.
Selecting an engine starts its download and loading immediately. A saved MLX
selection does the same at launch. Settings shows progress and offers retry on
failure. Switching away cancels preparation, drains the old inference process,
and prepares the latest selection without restarting or rebuilding the app.
The document and reading position remain available; resume playback explicitly.

Drama bf16 has running-app playback evidence at native 44.1 kHz, including
short fiction turns and explicit Character choices. Full qualification remains
owned by [the Drama issue](https://github.com/kellyjanderson/readaloud/issues/111).
Builds, source tests and playback position do not establish listening quality or
the two-second launch-to-speech requirement.

## Model downloads and cache

At launch with an MLX selection, or when selecting one in Settings, Read Aloud checks for a compatible local
checkpoint and then downloads it automatically if needed. Downloads use the
standard Hugging Face Hub cache, shared with other tools and applications when
the app can access it. If macOS sandbox permissions prevent access, Read Aloud
uses a reusable app-support cache instead. Interrupted Hub downloads can resume
on retry or a later selection. Download progress reports bytes when the Hub provides a
total, followed by a separate model-loading stage.
There is no fixed elapsed-time cutoff for downloading a model. The Hub bounds
individual network requests; changing the selected engine cancels preparation.

The recognized Hub checkpoints are:

| Engine ID | Checkpoint | Approx. size | License |
| --- | --- | ---: | --- |
| `fish_drama3` | `mlx-community/fish-audio-drama-3-bf16` | 67 GB | Fish Audio Community License |
| `fish_drama3_8bit` | `mlx-community/fish-audio-drama-3-8bit` | 36 GB | Fish Audio Community License |
| `fish_drama3_4bit` | `mlx-community/fish-audio-drama-3-4bit` | 23 GB | Fish Audio Community License |
| `qwen3_tts_1_7b` | `mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16` | 4.2 GB | Apache 2.0 |
| `qwen3_tts_base_1_7b` | `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16` | 4.2 GB | Apache 2.0 |
| `voxtral_4b` | `mlx-community/Voxtral-4B-TTS-2603-mlx-bf16` | 7.5 GB | CC BY-NC 4.0; noncommercial use only |
| `moss_tts_8b` | `OpenMOSS-Team/MOSS-TTS-v1.5` | 16 GB | Apache 2.0 |

Previously installed checkpoints in either the current app-support model
directory or the older sandbox container directory are reused. Checkpoints
are not committed to Git or bundled into the application. The JSON-lines
Python worker is bundled as a Flutter asset. Install the build's arm64 Python
runtime and MLX packages once with `sh tools/install_mlx_tts_runtime.sh`.
The Xcode embed phase copies this executable runtime into the app bundle and
signs the interpreter for sandbox inheritance. Model weights remain in the
cache. The sandbox cannot execute the external build-time interpreter directly.

For development, `READALOUD_TTS_ENGINE` can still override the saved preference
for the process that launches the macOS app:

```sh
READALOUD_TTS_ENGINE=qwen3_tts_1_7b tools/flutter run -d macos
READALOUD_TTS_ENGINE=voxtral_4b tools/flutter run -d macos
READALOUD_TTS_ENGINE=moss_tts_8b tools/flutter run -d macos
```

The default interpreter is installed at
`<app-support>/read_aloud/mlx-tts/runtime/venv/bin/python`. It must be arm64
with `mlx==0.32.4` and `mlx-audio==0.6.3`. `READALOUD_MLX_PYTHON` can override
that path when the override is accessible to the sandbox. An alternate local
checkpoint directory can be supplied with `READALOUD_MLX_TTS_MODEL_PATH`; it
must be readable from the app sandbox. If no recognized `READALOUD_TTS_ENGINE`
is present, the saved preference is used (Kokoro on a fresh installation).

## Runtime boundary

### Local macOS release packaging

Local releases must retain `Runner/Release.entitlements`. The file-picker
plugin checks the running app's signed entitlements before presenting a panel;
an unsigned build fails before the user can choose a document. For a local
arm64 release, use ad-hoc signing with the configured release entitlements:

```sh
sh tools/build_macos_release.sh
```

Run this bundle check before handing a candidate to a user. It rejects unsigned
or invalid bundles and missing sandbox, selected-file read access or network
client entitlements. Also exercise File > Open in the running release.
The wrapper reseals the outer bundle after Flutter and Python embedding so
incremental builds cannot retain a stale resource signature. It preserves the
embedded interpreter's sandbox-inheritance signature. The wrapper also accepts
`tools/mlx_playback_smoke.dart` as its first argument for a native smoke candidate.

### Optional native playback smoke test

Model-dependent tests are opt-in and are not prerequisites for ordinary source
checks. Install/download the requested model through the application first. A
missing checkpoint or failed download is a prerequisite failure, not evidence of
bad audio. The dedicated `tools/drama_settings_smoke.dart` target checks launch
and selection downloads, private fiction display and replacement before weights
finish; it explicitly does not claim Drama audio acceptance.


`tools/mlx_playback_smoke.dart` mounts the real application UI with its normal
controller, synthesis pipeline and native audio player. It imports a supplied
short dialogue, requests playback and requires at least 500 ms of advancing
native playback plus non-silent PCM audio. Reader preferences are isolated in
memory. It shuts down the engine and application on either success or failure.
Full-document completion within five seconds is a separate optional assertion:
set `READALOUD_SMOKE_REQUIRE_COMPLETE_DOCUMENT=1` only for a fixture that fits
the bounded prepared-range window. Longer stories can start playing while
preparation waits for reading or display demand; the playback probe records
that state without requiring eager whole-document preparation.

The November 3 native regression read the City fixture with Qwen Base and the
downloaded Fish Ethan reference: 522 ms advancing playback, non-silent PCM16
(peak 15,501), native 24 kHz output, and 5,231 words in eight prepared ranges.
This exercises the shared worker and downloaded references; it is not Drama
inference, a full-story continuity test, or a listening-quality judgment.

Build a separate test candidate using Xcode's `FLUTTER_TARGET=tools/mlx_playback_smoke.dart`
override (or `sh tools/build_macos_release.sh tools/mlx_playback_smoke.dart`).
Before running it, isolate the test bundle and sandbox so normal File Open
events and user settings cannot replace the test fixture:

```sh
sh tools/prepare_mlx_playback_test_app.sh /path/to/read_aloud.app /tmp/ReadAloudPlaybackTest.app
ruby tools/run_mlx_playback_smoke.rb /tmp/ReadAloudPlaybackTest.app/Contents/MacOS/read_aloud \
  "$HOME/Library/Containers/com.kellyjanderson.readAloud.mlxPlaybackTest/Data/tmp/new-playback-receipts"
```

The runner tests Voxtral, Qwen and MOSS sequentially by default; append an engine
ID such as `fish_drama3` to select a single backend. Each run is bounded to six
minutes plus `READALOUD_SMOKE_PLAY_SECONDS`. It requests normal Quit after success
or failure, verifies app/owned-child exit, and reports forced cleanup as failure.
Rebuild with `FLUTTER_TARGET=lib/main.dart`
before handing a normal release app to a user. The smoke establishes native
playback and non-silent generated audio; acoustic quality still needs listening.

For S3 dialogue checks, `READALOUD_SMOKE_REQUIRE_END=1` requires contiguous
completed source spans through the final word. `READALOUD_SMOKE_CAST_VOICES`
accepts a JSON map of Character labels to explicit voice IDs, and
`READALOUD_SMOKE_EXPECT_CAST_SEQUENCE=Mara,Mira,Mara` checks dialogue order.
`READALOUD_SMOKE_WHISPER_TEXT` identifies one synthetic-fixture segment to receive
an explicit canonical whisper annotation; it does not infer directions from
prose. `READALOUD_SMOKE_TRANSPORT=1` checks pause, seek acknowledgment and a
superseded pending Play. The receipt separates transport latency, startup,
playhead stalls, app/worker peak footprint and UI event-loop delay. The latter
is a timer-latency diagnostic, not a claim of human input-response acceptance.
Release-build metrics are written beside the receipt as `.metrics.jsonl` only
when this harness explicitly installs its observer.

For actual app-output evidence, compile `tools/capture_macos_app_audio.swift`
with `swiftc -parse-as-library` and run the resulting executable with the owned
test PID, a new WAV path and a duration of at most 300 seconds. ScreenCaptureKit
filters to that process; it does not change output routing or record a microphone.
The tool requires existing screen/audio-capture authorization and does not
request new permissions. Start it before first speech. Run
`tools/compare_captured_dialogue.py RECEIPT CAPTURE.wav NEW_RESULT.json` with the
managed MLX Python to compare captured waveforms to queued files. It requires
strong whole-turn acoustic matches and measures gaps between matched turns;
human review still decides transcript correctness, expression and perceived
voice continuity. Keep private manuscript recordings local.

`tools/mlx_tts_worker_test.py`, run with the MLX runtime Python, separately
regresses full generator consumption and native sample-rate preservation and rejects
unknown presets or missing reference conditioning.

The selected engine replaces only chunk synthesis. Read Aloud retains its
existing document preparation, pronunciation/text planning, voice assignment,
chunk planning, admission, cache, cancellation/staleness checks, playback and
export pipeline. The legacy Kokoro respelling of `for` as `four` is restricted
to Kokoro; MLX engines receive the original `for`, including when reopening
an existing prepared book. Explicit pronunciation choices still apply. Previously
rendered audio is preserved; new synthesis uses the corrected text.

Engine-specific pronunciation and expressive adjustments require a versioned
record for the exact engine/model context. A different model, revision or precision
does not inherit another model's exceptions. Saved books retain adjustment
references separately from their text. Recognized legacy records migrate when
opened; an unknown or mismatched adjustment is retained but not applied.
Document intent such as a pronunciation request or “whispered” direction remains
separate. The pinned Drama bf16 adapter lowers one unambiguous, explicit,
whole-segment whisper direction to the native `[whispers]` cue and isolates its
scope from subsequent ordinary text. Partial/conflicting directions, other
delivery types and untested variants remain preserved with unsupported fallback.
Audible quality remains a listening gate. Unchanged raw speech is reused across
seek/replay; join corrections have their own cache identity.

A supervised child process loads one model and handles one
request at a time. Cancellation retires the in-flight process so it cannot
publish stale output; a later request reloads the same model identity into a fresh worker before synthesis. On app quit the
native delegate asks Dart to shut the worker down, waits for its response, and
has a bounded 12-second termination fallback. Generated PCM is written as
mono PCM16 WAV at the model's native sample rate. Drama stays at 44.1 kHz.
Artifact duration, boundary silence measurements and export derive timing from
the WAV header. Playback/export introduce no sample-rate conversion.

If synthesis fails after producing valid audio, that audio is retained. The
error gives the saved incomplete WAV path when available; request provenance is
stored beside it under `generated-audio/mlx-raw-v1/incomplete` in Application
Support. Cancellation also retains packets already written. Retry creates a
separate attempt and does not overwrite the earlier recording. Incomplete
passages are not automatically played or treated as complete cached speech;
automatic continuation within a failed chunk is not yet implemented. Completed
cached audio remains reusable. Drama's empty final stream marker is handled as
normal completion, preserving all preceding samples at 44.1 kHz.

MOSS-TTS v1.5 may download its separate audio-tokenizer files into the selected
Hugging Face cache the first time it loads.

These models currently receive the planned plain-text chunk and a supported
preset or a selected synthetic audio reference. Engine-specific phoneme/IPA adaptation and acoustic quality have
not been qualified. The integration is for side-by-side engine evaluation;
it does not establish that any model improves pronunciation or meets the
existing latency target. Per-chunk speech-rate realization is also not yet
implemented by these adapters. Voxtral's noncommercial license must be observed.

Voxtral defaults to **Full precision**. Settings offers optional **Fast (4-bit)** inference;
changing precision retires and reloads the model in the current session. The helper quantizes
supported model layers in memory with mlx-audio's model-specific predicate. The
original cached checkpoint is retained, and precision is part of the speech-cache
identity. Qwen and MOSS keep their original precision.

MLX playback uses a bounded 20-second high / 12-second low playable-audio lead
and the existing 64-chunk cap. Voxtral warms the startup buffer before playback;
Qwen and MOSS start with their first validated chunk. At the five-second MLX
warmup deadline, already validated audio can start rather than failing solely
because the target lead was not reached. Cancellation and stale-result checks
continue to apply. This does not establish the two-second startup requirement.

For a sustained native check, set `READALOUD_SMOKE_DOCUMENT_PATH` to a local text
file, `READALOUD_SMOKE_PLAY_SECONDS=45`, and
`READALOUD_SMOKE_QUANTIZATION_BITS=4`. The probe records source preparation,
native playback advancement/stalls and non-silent emitted PCM, then closes the
app and worker. It does not replace acoustic loopback or pronunciation listening.
`tools/mlx_tts_benchmark.py` compares worker synthesis time against generated
audio duration using a supplied corpus; it writes audio and a JSON receipt.

Document-processing diagnostics are independent of synthesis. Build
`tools/document_preparation_smoke.dart`, clone into the isolated QA bundle, and
invoke its executable with `SOURCE_TEXT RECEIPT_JSON`. It opens the real reader
UI, runs three document imports with an engine that cannot synthesize, records
completion and main-isolate timer responsiveness, then closes the app. Its
preparation timing starts at import, not application launch. The local source
test can use `READALOUD_PREPARATION_FIXTURE=/path/to/file.txt` to exercise the same
controller/worker path without committing a private passage.

## Voice selection and qualification

The minimum evaluation requirement is 30 distinct usable voice identities per
engine. Voice count is separate from acoustic quality, pronunciation and latency.

| Configuration | Selection | Meets the count requirement |
| --- | --- | --- |
| Fish Audio Drama 3 | 13 Fish Official plus 30 synthetic references | Count available; native acoustic qualification pending |
| Qwen3-TTS 1.7B Base | 43 reference identities | Yes; acoustic qualification remains separate |
| MOSS-TTS v1.5 8B | The same 43 reference identities | Yes; acoustic qualification remains separate |
| Qwen3-TTS 1.7B CustomVoice | All 9 fixed native speakers | No; retained separately as a limited configuration |
| Voxtral 4B local MLX | All 20 native presets | No; the released local decoder/runtime lacks the reference encoder |
| Kokoro | 54 catalog presets across languages (28 English) | Catalog count only; installed availability is shown in Voice Management |

Choose **Qwen3-TTS 1.7B Base** or **MOSS-TTS** in Settings,
then open **Voice Management** to preview/select voices or
assign them to characters. Qwen Base is a separate, automatically downloaded
checkpoint; existing CustomVoice weights are retained. Reference WAVs ship in
`assets/voice_library/` and only selected files are materialized in the app cache.
Models download/load at startup; reference voices are not generated during startup.

These fictional voices were created locally with the pinned Qwen VoiceDesign
checkpoint. The manifest records descriptions, seeds, transcript, duration and
content hashes. Descriptions/accents are intentions, not certified demographics.
`tools/build_voice_library.py` builds the bank; `tools/qualify_voice_library.py`
exercises every reference through each supported backend and retains audio.
`tools/analyze_voice_library.py` compares real output/reference speaker embeddings
as an uncalibrated diagnostic. Neither unique file hashes nor an embedding rank
replace listening acceptance of perceptual voice variety.

The selected reference audio and transcript are sent to Qwen Base/MOSS for each
request. Reference content participates in prepared voice binding and audio-cache
identity. Unknown presets or missing references fail explicitly instead of
silently speaking in a default voice. The old unconditioned MOSS voice is removed.
The 30-voice requirement is not met by relabeling emotion/style variants or
creating several names for the same conditioning. Voxtral stays below this gate;
cloud voice-cloning capabilities do not establish local MLX support.

Voice Management shows the active engine and available English voice count. The
reference bank contains 43 English profiles, including 30 bundled synthetic voices
(15 female and 15 male labels) and 13 Fish Official references. A
five-English-voice list is the local Voxtral configuration; its other-language
presets do not satisfy the 15-English-default minimum. Select Drama, Qwen Base or MOSS
to use the reference bank in the current session. Settings replaces the running
engine after its previous worker has stopped.

The document-processing native probe now scrolls the real reader to its displayed
ending and checks tail text plus the EOF marker. For a long source, set
`READALOUD_PREPARATION_RUNS=1` and `READALOUD_PREPARATION_MAX_MS=60000`. This timeout
covers explicit traversal to the end; the probe separately records time to the
first range and UI timer gaps. It does not require eager whole-novel preparation
before displaying or speaking the opening.

## Drama voices, precision and memory

The three Drama choices are independently downloaded checkpoints, pinned in
`assets/fish_drama_models.json`. They require no rebuild to change. bf16 is the
primary M5 Max/128 GB target; the configured total-runtime ceiling is 100 GB.
The model card reports roughly 74 GB peak for bf16 and 26 GB for 4-bit. M3 RAM
varies; choose a precision that fits the actual machine. The app checks estimated
headroom before loading, caps MLX allocation, and retires the child at a sampled
99 GB application-plus-inference-child physical-footprint high water, queried
through macOS libproc. Each process samples itself, respecting sandbox rules;
the parent combines its footprint with telemetry from its current child only.
These sampled guards have not yet been qualified under
full Drama model memory pressure.

bf16 and 4-bit are pinned to conversions of the October 29 updated weights.
The available 8-bit conversion has an older lineage; a comparison therefore
changes both precision and checkpoint. See each pinned model's NOTICE and
license. No hosted Fish synthesis or paid API is used.

Drama preparation downloads 13 Fish Official designed English reference voices,
with pinned sample hashes, transcripts and source links in
`assets/fish_voice_library.json`. Together with the 30 existing synthetic
references there are 43 choices for every character, with no gender-based hard
filter. Remote samples are cached locally; their audio is not redistributed in
this repository. The descriptions are catalog claims, not verified acoustic
quality. Each selected reference is passed to the model; missing references
fail visibly rather than selecting a different voice.

Current story reading retains one selected voice per planned chunk. Drama's
native multi-speaker scene API is not yet connected to the document/timing DTOs;
source-offset-aware scene synthesis remains open in #111. Do not describe
per-character chunk routing as native scene generation. Speech-rate handling
for MLX and perceptual voice continuity also remain acceptance gaps.

Sources: [Drama bf16 model card](https://huggingface.co/mlx-community/fish-audio-drama-3-bf16),
[MLX Audio Drama implementation](https://github.com/Blaizzy/mlx-audio/tree/main/mlx_audio/tts/models/fish_drama3),
[Fish public voice API](https://docs.fish.audio/api-reference/endpoint/model/list-models).
