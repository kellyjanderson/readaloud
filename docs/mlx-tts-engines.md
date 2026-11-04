# Local MLX TTS engines

Read Aloud offers four Apple Silicon configurations: Qwen3-TTS 1.7B Base and
CustomVoice, Voxtral TTS 4B, and MOSS-TTS v1.5 8B. Kokoro remains the
default. On macOS, choose an engine from **Read Aloud > Settings…**, under
**Text-to-speech engine**. The selection is saved with reader preferences and takes
effect after quitting and reopening the app. The dialog shows which engine is
active in the current session.

## Model downloads and cache

When an MLX engine is first used, Read Aloud checks for a compatible local
checkpoint and then downloads it automatically if needed. Downloads use the
standard Hugging Face Hub cache, shared with other tools and applications when
the app can access it. If macOS sandbox permissions prevent access, Read Aloud
uses a reusable app-support cache instead. Interrupted Hub downloads can resume
on the next launch. Download progress reports bytes when the Hub provides a
total, followed by a separate model-loading stage.

The recognized Hub checkpoints are:

| Engine ID | Checkpoint | Approx. size | License |
| --- | --- | ---: | --- |
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
READALOUD_TTS_ENGINE=qwen3_tts_1_7b flutter run -d macos
READALOUD_TTS_ENGINE=voxtral_4b flutter run -d macos
READALOUD_TTS_ENGINE=moss_tts_8b flutter run -d macos
```

The default interpreter is installed at
`<app-support>/read_aloud/mlx-tts/runtime/venv/bin/python`. It must be arm64
with `mlx==0.32.4` and `mlx-audio==0.6.3`. `READALOUD_MLX_PYTHON` can override
that path when the override is accessible to the sandbox. An alternate local
checkpoint directory can be supplied with `READALOUD_MLX_TTS_MODEL_PATH`; it
must be readable from the app sandbox. If no recognized `READALOUD_TTS_ENGINE`
is present, Kokoro is selected.

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

### Native playback smoke test

`tools/mlx_playback_smoke.dart` mounts the real application UI with its normal
controller, synthesis pipeline and native audio player. It imports a supplied
short dialogue, requests playback and requires at least 500 ms of advancing
native playback plus non-silent PCM audio. Reader preferences are isolated in
memory. It shuts down the engine and application on either success or failure.

Build a separate test candidate using Xcode's `FLUTTER_TARGET=tools/mlx_playback_smoke.dart`
override (or `sh tools/build_macos_release.sh tools/mlx_playback_smoke.dart`).
Before running it, isolate the test bundle and sandbox so normal File Open
events and user settings cannot replace the test fixture:

```sh
sh tools/prepare_mlx_playback_test_app.sh /path/to/read_aloud.app /tmp/ReadAloudPlaybackTest.app
ruby tools/run_mlx_playback_smoke.rb /tmp/ReadAloudPlaybackTest.app/Contents/MacOS/read_aloud \
  "$HOME/Library/Containers/com.kellyjanderson.readAloud.mlxPlaybackTest/Data/tmp/new-playback-receipts"
```

The runner tests Voxtral, Qwen and MOSS sequentially, bounds each run to six
minutes, records native playback position and PCM peak, and terminates the app
and inference children on failure. Rebuild with `FLUTTER_TARGET=lib/main.dart`
before handing a normal release app to a user. The smoke establishes native
playback and non-silent generated audio; acoustic quality still needs listening.

`tools/mlx_tts_worker_test.py`, run with the MLX runtime Python, separately
regresses generator-result handling for all four configurations and rejects
unknown presets or missing reference conditioning.

The selected engine replaces only chunk synthesis. Read Aloud retains its
existing document preparation, pronunciation/text planning, voice assignment,
chunk planning, admission, cache, cancellation/staleness checks, playback and
export pipeline. A supervised child process loads one model and handles one
request at a time. Cancellation retires the in-flight process so it cannot
publish stale output; a later request can start a fresh worker. On app quit the
native delegate asks Dart to shut the worker down, waits for its response, and
has a bounded 12-second termination fallback. Generated PCM is written as
mono 24 kHz WAV and enters the same artifact store as existing engine output.

MOSS-TTS v1.5 may download its separate audio-tokenizer files into the selected
Hugging Face cache the first time it loads.

These models currently receive the planned plain-text chunk and a supported
preset or a selected synthetic audio reference. Engine-specific phoneme/IPA adaptation and acoustic quality have
not been qualified. The integration is for side-by-side engine evaluation;
it does not establish that any model improves pronunciation or meets the
existing latency target. Per-chunk speech-rate realization is also not yet
implemented by these adapters. Voxtral's noncommercial license must be observed.

Voxtral defaults to **Full precision**. Settings offers optional **Fast (4-bit)** inference;
changing precision takes effect after reopening the app. The helper quantizes
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
| Qwen3-TTS 1.7B Base | 30 synthetic reference identities | Yes; acoustic qualification remains separate |
| MOSS-TTS v1.5 8B | The same 30 reference identities | Yes; acoustic qualification remains separate |
| Qwen3-TTS 1.7B CustomVoice | All 9 fixed native speakers | No; retained separately as a limited configuration |
| Voxtral 4B local MLX | All 20 native presets | No; the released local decoder/runtime lacks the reference encoder |
| Kokoro | 54 catalog presets across languages (28 English) | Catalog count only; installed availability is shown in Voice Management |

Choose **Qwen3-TTS 1.7B Base (reference voices)** or **MOSS-TTS** in Settings,
quit and reopen, then open **Voice Management** to preview/select voices or
assign them to characters. Qwen Base is a separate, automatically downloaded
checkpoint; existing CustomVoice weights are retained. Reference WAVs ship in
`assets/voice_library/` and only selected files are materialized in the app cache.
There is no model or reference-bank generation during reader startup.

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

Voice Management shows the active engine and ready English voice count. The
reference bank contains 30 English profiles (15 female and 15 male labels). A
five-English-voice list is the local Voxtral configuration; its other-language
presets do not satisfy the 15-English-default minimum. Select Qwen Base or MOSS
and reopen to use the reference bank. Settings selection does not change the
engine already running in that session.

The document-processing native probe now scrolls the real reader to its displayed
ending and checks tail text plus the EOF marker. For a long source, set
`READALOUD_PREPARATION_RUNS=1` and `READALOUD_PREPARATION_MAX_MS=60000`. This timeout
covers explicit traversal to the end; the probe separately records time to the
first range and UI timer gaps. It does not require eager whole-novel preparation
before displaying or speaking the opening.
