# Read Aloud

A local-first Flutter reader for long-form text-to-speech using Kokoro. Import documents, listen with narrator and character voices, follow the spoken text, and export audio.

## Project status

macOS is the current functional target. Other Flutter platform folders are retained but are not qualified by the current project review. This repository is pre-release; older release labels and the package version are being reconciled before the next release.

Speaker attribution is heuristic. Document preparation and native inference resource lifetime have known limitations documented in [current architecture](project/architecture/README.md). Planned improvements live in a separate [ACD and implementation plan](project/acd/README.md).

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

Before running, place a compatible model at `assets/kokoro/model/kokoro-v1.0.onnx`. Model weights are not in Git; see [model setup](assets/kokoro/model/README.md). The app uses a [vendored ONNX plugin override](third_party/flutter_onnxruntime/pubspec.yaml).

```sh
flutter run -d macos
```

See [development and verification](docs/development.md) for checks and build instructions. The ignored local SDK/build caches are not clean-clone prerequisites.

## Repository guide

| Path | Purpose |
| --- | --- |
| `lib/`, `test/` | Application source and tests |
| `assets/`, `third_party/` | Bundled resources and vendored dependencies |
| [docs](docs/README.md) | Human setup and maintenance guidance |
| [architecture](project/architecture/README.md) | Current implementation and evidence locations |
| [ACDs](project/acd/README.md), [plans](project/planning/README.md) | Proposed changes and bounded implementation work |
| [legacy contracts](project/specifications/README.md) | Retained detailed behavior references |
| [archive](project/archive/README.md) | Superseded specifications and historical snapshots |

## Contributing and support

Read [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), [SUPPORT.md](SUPPORT.md) and [SECURITY.md](SECURITY.md). New architecture changes use one ACD and one paired plan, not a recursive specification tree.

## Licensing

A top-level project license has not yet been selected. Do not infer a project license from public repository visibility. Existing third-party notices remain with their components; see the [licensing checklist](project/planning/open-source-compliance-plan.md).
