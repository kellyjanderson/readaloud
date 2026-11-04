# Read Aloud

A local-first Flutter reader for long-form text-to-speech using Kokoro by default. Import documents, listen with narrator and character voices, follow the spoken text, and export audio.

For local Apple Silicon evaluation of Qwen3-TTS, Voxtral TTS, or MOSS-TTS,
see [MLX TTS engine setup](docs/mlx-tts-engines.md).

## Required reading experience

These are product requirements, not claims that the current build meets them:

- **Sound within two seconds of opening the app:** when Play is requested promptly with a document available, smooth, uninterrupted speech must begin within two seconds, regardless of document size. Measure from opening, not from the end of preparation.
- **Always responsive:** controls and the reading surface remain responsive during every background operation. Pending playback remains cancellable; obsolete work must never start unexpected speech.
- **Everything about reading is dynamic:** acquisition, parsing, normalization, display/position mapping, analysis, pronunciation and delivery planning, voice binding, synthesis, buffering and persistence advance incrementally as needed. Whole-document completion must not gate first speech. Character discovery is one example of this rule, not its scope.
- **Truthful progress:** operations exceeding one or two seconds show dynamic progress based on actual completed work, with honest totals, stages and waiting/failure states. No fabricated percentages or 100% while the operation still blocks readiness.
- **Reusable, directed `.radoc`:** automatically persist processed input for second-run reuse, preserve inflection and other speech-direction annotations, and support the long-term goal of publishing books with voice direction.

The [product definition](project/product-definition.md) defines these standing expectations. [Issue #83](https://github.com/kellyjanderson/readaloud/issues/83) records source findings, implementation gaps and required acceptance evidence. Current architecture documents implemented behavior separately.

## Project status

macOS on Apple Silicon is the current functional target. Other Flutter platform folders are retained but are not qualified. The cleanup baseline consolidates the RC2 reader, local MLX engines, full-document display and the visual acceptance runner. It is a development checkpoint, not a claim that all reading-experience requirements pass.

Speaker attribution is heuristic. Current architecture records implementation and evidence limits. Sustained audio continuity, launch timing and human acceptance remain tracked in [RC2 qualification](https://github.com/kellyjanderson/readaloud/issues/91). [Drama 3 integration](https://github.com/kellyjanderson/readaloud/issues/111), live model switching and their concurrency repairs follow this baseline; they are not implemented by the cleanup tag.

## Features

- Import plain text, Markdown, HTML, EPUB, PDF, DOCX and RTF.
- Use local speech generation with narrator/character casting and manual voice assignments.
- Follow spoken text, navigate playback, and restore file-backed reading position.
- Export WAV audio and run headless pronunciation/sentence probes.

## Development quick start

The documented baseline is Flutter **3.41.5** and Dart **3.11.3**. Install a matching native SDK, Xcode and CocoaPods for macOS.

```sh
git clone https://github.com/kellyjanderson/readaloud.git
cd readaloud
flutter pub get
```

For the default Kokoro engine, place a compatible model at `assets/kokoro/model/kokoro-v1.0.onnx`; see [model setup](assets/kokoro/model/README.md). For MLX engines, install the [arm64 runtime](docs/mlx-tts-engines.md) and select the engine in Settings. Model weights download separately and are not in Git. The app uses a [vendored ONNX plugin override](third_party/flutter_onnxruntime/pubspec.yaml).

```sh
flutter run -d macos
```

See [reading and voice choices](docs/reading-and-voice-choices.md) for Current/Pending behavior and [development and verification](docs/development.md) for checks and build instructions. The ignored local SDK/build caches are not clean-clone prerequisites.

## Repository guide

| Path | Purpose |
| --- | --- |
| `lib/`, `test/` | Application source and tests |
| `assets/`, `third_party/` | Bundled resources and vendored dependencies |
| [docs](docs/README.md) | Human setup and maintenance guidance |
| [architecture](project/architecture/README.md) | Current implementation and evidence locations |
| [GitHub planning](docs/project-management.md) | Working design, execution slices and orchestrator handoffs |
| [legacy contracts](project/specifications/README.md) | Retained detailed behavior references |
| [archive](project/archive/README.md) | Superseded specifications and historical snapshots |

## Contributing and support

Read [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), [SUPPORT.md](SUPPORT.md) and [SECURITY.md](SECURITY.md). Working architecture and planning live in GitHub; final architecture is reconciled alongside implementation in this repository.

## Licensing

A top-level project license has not yet been selected. Do not infer a project license from public repository visibility. Existing third-party notices remain with their components; see the [licensing checklist](https://github.com/kellyjanderson/readaloud/issues/55).
