# Speech runtimes and Python in Read Aloud

This describes the macOS integration source at `fd1df4c58c09870258a84e2975a7f6b51402d4f9` and notes where it differs from the feature checkout `ae8d8bd`. Both are development sources. See the [integration and acceptance record](https://github.com/kellyjanderson/readaloud/issues/110) for evidence tied to specific builds.

## What runs where

| Path | App-facing interface | Where the work runs |
| --- | --- | --- |
| Kokoro (deprecated) | Dart calls the vendored `flutter_onnxruntime` plugin | Dart handles pronunciation, token IDs and voice-vector selection. The macOS plugin calls native ONNX Runtime to execute the model with tokens, style and speed. The Dart speech worker owns the call and WAV artifact lifecycle. |
| Fish Audio Drama 3, Qwen3-TTS, Voxtral TTS and MOSS-TTS | Dart starts a dedicated Python child and exchanges JSON lines over its standard streams | The Python app adapter calls `mlx-audio` for model-specific generation. MLX's native runtime executes the numerical operations on Apple Silicon. Python owns model setup, orchestration and WAV/packet production. |
| ModernBookNLP evaluation | Dart starts a separate Python child on opt-in analysis demand | The CPU-based Python pipeline returns linguistic annotations for bounded text windows. Dart validates and applies eligible results to future character routing. |
| Playback and export | Dart speech runtime and native audio facilities | Dart owns playback intent, artifact acceptance, joining, cache identity and export. `just_audio` hands the audio to AVFoundation for macOS playback. |

[Kokoro model runner](../lib/src/services/kokoro_model_runner.dart), [macOS ONNX plugin](../third_party/flutter_onnxruntime/macos/Classes/FlutterOnnxruntimePlugin.swift), [MLX process client](../lib/src/services/mlx_speech_worker_processor.dart), [ModernBookNLP provider](../lib/src/services/modernbooknlp_provider.dart), [audio player integration](../lib/src/services/kokoro_tts_engine.dart)

## Kokoro deprecation

All Kokoro-specific paths are deprecated. Their purpose is compatibility with existing settings and fixtures, and reproduction of prior evidence. Choose a non-Kokoro backend for new speech work. This designation has no removal date.

| Entry point | Deprecated scope |
| --- | --- |
| Engine selection | Explicit Kokoro selection, saved Kokoro preferences, the automatic Kokoro fallback, and Kokoro-only builds. |
| Reader and voice management | Kokoro inference for document playback, narrator and character routing, voice preview, and Kokoro model or voice installation. |
| Export and regeneration | New synthesis through Kokoro for WAV export and for passages that need regenerated audio. |
| Development and QA | Kokoro-specific model setup, ONNX and voice assets, phoneme and pronunciation adaptations, headless export and pronunciation/sentence probes when routed to Kokoro, and the Kokoro-native regression harnesses. |

The shared runtime includes `KokoroTtsEngine`, which also hosts the MLX backends. Document preparation, casting, artifact handling, the player and model-free playback of saved audio are shared paths. See [engine selection and fallback](mlx-tts-engines.md), [legacy model setup](../assets/kokoro/model/README.md), and [retained regression tools](../tools/README.md#retained-native-qualification-probes).

## Exactly what the MLX child does

The executable is the configured or managed **arm64 CPython 3.12**. Dart resolves it, copies the bundled worker and the applicable catalog assets into its runtime area, and launches `python -u -B mlx_tts_worker.py`. The child stays alive across requests, with one resident model and one request in flight. Standard output carries protocol messages and standard error carries diagnostics. The integration build can supply the interpreter and packages, so a user's system Python is unnecessary even though Python executes at runtime. The pinned direct dependencies are `mlx==0.32.4`, `mlx-audio==0.6.3`, `huggingface-hub[hf_xet]==2.4.0`, and `mistral-common[audio]==1.13.0`. NumPy is used in its audio path. [Interpreter lookup and process launch](../lib/src/services/mlx_speech_worker_processor.dart), [runtime pins](../tools/mlx_tts_requirements.txt), [installation and bundle layout](mlx-tts-engines.md)

The child handles four commands in the integration checkout.

1. **`metadata`** reports runtime and model capability information. This helps Dart identify the adapter and check whether a requested model configuration is eligible.
2. **`load`** checks memory admission and looks for the requested model in an explicit directory or eligible caches. The Hub client handles local lookup and any required download. The adapter validates applicable manifests, weights and codec files and reports download and load stages. It loads the model via `mlx_audio.tts.load` and retains it for later calls. Voxtral has an optional in-memory 4-bit conversion. Fish's precision selections are separately pinned checkpoints with their own runtime and memory evidence.
3. **`synthesize`** receives prepared text or ordered scene turns, the effective speaker or reference set, transcripts and request identity. The adapter validates these, lowers Fish speakers to native slots, then invokes the selected model's generation API. `mlx-audio` supplies the model-specific tokenization, reference conditioning, generation loop and audio decoding used by that call. The adapter checks for valid mono output, converts it to PCM16, writes at the model-reported rate, and returns the completed WAV path and identity. Fish emits 44.1 kHz. Enabled streaming paths also report ordered packet offsets with request identity. A partial file is usable for diagnosis but does not become a completed cache artifact.
4. **`shutdown`** releases the resident model and exits. A reporting thread samples the child's physical footprint. Dart owns cancellation and process retirement. It invalidates the request, can terminate and reap the child, and reloads the intended model into a fresh child when required.

[Python protocol](../assets/mlx_tts_worker.py#L1107), [download and load](../assets/mlx_tts_worker.py#L285), [model generation and audio writing](../assets/mlx_tts_worker.py#L906), [Fish catalog](../assets/fish_drama_models.json), [Dart completion and cancellation](../lib/src/services/mlx_speech_worker_processor.dart)

### What can change the speech

- **Kokoro (deprecated)** receives numeric synthesis speed and an acoustic style vector. Its Dart-side pronunciation adaptations can change the phonemes sent to the native model. A native link to ONNX Runtime already exists. [Kokoro inference](../lib/src/services/kokoro_speech_worker_processor.dart), [model inputs](../lib/src/services/kokoro_model_runner.dart)
- **Fish** receives reference audio and transcripts, speaker slots and model text. The integration source also has a model-scoped scene path and two explicit whole-segment delivery mappings, whisper and shout, for the qualified bf16 context. Those mappings belong to Dart's planning and translation. The Python side receives and renders the resulting turns. The earlier `ae8d8bd` checkout has reference-slot reuse and per-chunk renders. Its adapter does not send those directed scenes. A reference carries information about voice and accent. The model still determines much of the pitch contour, phrasing and emphasis. [Integrated delivery mapping](../lib/src/services/voice_session_realization_service.dart#L174), [speech adjustments](../lib/src/services/speech_adjustment_registry.dart), [earlier worker](https://github.com/kellyjanderson/readaloud/blob/ae8d8bd23da18fcd7c15afeea3ddf94d56ba8e14/assets/mlx_tts_worker.py#L353)
- **Qwen CustomVoice and Voxtral** receive a named preset. **Qwen Base and MOSS** receive reference audio and its transcript. MOSS can also need a separate audio tokenizer on first load. The adapter exposes a subset of the upstream models' possible controls. [Backend dispatch](../assets/mlx_tts_worker.py#L906), [model setup](mlx-tts-engines.md)
- **MLX rate** is present in the Dart request and cache identity. The JSON synthesis request contains no speed field. The Fish catalog describes post-processing as the rate strategy, but the current reader's rate setter stores the requested value and the playback code reads player speed for its timing calculations. The source path traced here does not apply the slider at the player. Model generation speed, audible playback rate, and rate baked into an export are three distinct controls. [Dart rate handling](../lib/src/services/kokoro_tts_engine.dart#L768), [MLX request fields](../lib/src/services/mlx_speech_worker_processor.dart#L1163), [Fish capability descriptors](../assets/fish_drama_models.json)

## The other Python runtime

ModernBookNLP is present on the integration checkout and absent from `ae8d8bd`. It uses managed **Python 3.11.15**, separate from the MLX install, with pinned PyTorch, Transformers and spaCy among its dependencies. The resident worker accepts `prepare` and `analyze` over a one-request JSON protocol. It loads or verifies its own pinned model assets, analyzes a bounded source window, converts offsets to Dart UTF-16 coordinates and returns source-linked entity, coreference and quotation/speaker information. Dart owns request identity, character reconciliation, saved analysis, explicit cast assignments and application of results to future reading. Playback can proceed while optional refinement runs. Porting speech synthesis leaves this optional runtime as a separate dependency. [Provider setup and contract](modernbooknlp-provider.md), [worker](../assets/modernbooknlp_worker.py), [Python dependency pins](../tools/modernbooknlp_requirements.txt)

Python files under `tools/` also support model installation, benchmarking, fixture generation and QA. Those tools have a different lifecycle from processes a reader app can launch. A release can eliminate Python from speech rendering while retaining Python tooling for reproducing baseline results.

## What Dart bindings would replace

A binding connects Dart to a compiled implementation. It can replace the invocation and transport, but the compiled model code still has to load the exact checkpoint, condition voices, run its generation and codec, and produce valid PCM. Apple's MLX Swift supplies the tensor runtime. A model-specific native library supplies the speech model and codec. Read Aloud supplies the bridge and the document, voice, playback and export policy. The [Flutter/Dart directive](../AGENTS.md#flutterdart-platform-and-native-bindings) calls for a maintained binding or a Flutter/Dart module that reaches compiled code directly. The current Python relay adds process startup, deployment, packaging, request transport and failure-handling costs. Measure those stages separately from native model load and inference before attributing a performance difference to Python. The [native runtime comparison](../project/research/native-tts-runtimes.md) and [migration draft](../project/interim/native-tts-r1/README.md) cover the intended replacements.
