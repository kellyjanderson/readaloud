# Read Aloud

`Read Aloud` is a local-first Flutter document reader focused on high-quality long-form text-to-speech.

The current repository contains the new Kokoro-based speech pipeline, document import and normalization, pronunciation planning and diagnostics, export and headless QA tooling, and the full architecture/specification corpus for the project.

## Status

- current release target: `Beta 2`
- platform status: macOS is the only platform currently treated as functional
- other Flutter targets may build, but have not been validated yet

## What It Does

- opens and normalizes imported documents
- reads them aloud through a local speech pipeline
- supports playback progress, jumping, and export
- traces pronunciation and synthesis behavior for debugging
- provides probe and sentence-by-sentence QA workflows for speech evaluation

## Repository Layout

- [`lib/`](lib/) application code
- [`assets/`](assets/) bundled pronunciation resources and Kokoro voice assets
- [`project/`](project/) product, architecture, specifications, planning, and research
- [`test/`](test/) regression and behavior tests
- [`third_party/`](third_party/) vendored third-party source and license material

Project system documentation starts in [`project/README.md`](project/README.md).

## Prerequisites

- Flutter `3.41.5`
- Dart `3.11.3`
- Xcode and CocoaPods for macOS and iOS work
- Git LFS is not required for a normal clone of this repository as currently checked in

## External Model Dependency

The Kokoro ONNX model is not committed to this repository.

Before running or building the app, place a compatible model file at:

```text
assets/kokoro/model/kokoro-v1.0.onnx
```

Setup notes live in:

- [`assets/kokoro/model/README.md`](assets/kokoro/model/README.md)

Without that file, Kokoro-backed speech startup will fail because the Flutter asset bundle expects that model path to exist.

## Quick Start

```bash
git clone https://github.com/kellyjanderson/readaloud.git
cd readaloud
flutter pub get
```

Then download or place the Kokoro model file at:

```text
assets/kokoro/model/kokoro-v1.0.onnx
```

Run the macOS app:

```bash
flutter run -d macos
```

Build the macOS app:

```bash
flutter build macos
```

## Development Notes

- the repository currently uses a local `dependency_overrides` path for [`third_party/flutter_onnxruntime`](third_party/flutter_onnxruntime)
- Kokoro voice `.npy` files and pronunciation resources are checked in
- generated local speech QA artifacts are ignored under [`project/test-artifacts/`](project/test-artifacts)

## Testing

Examples:

```bash
flutter test
flutter analyze
```

Speech-quality work should also use the in-repo probe and trace workflows rather than relying only on manual listening. Project-specific agent rules for that live in:

- [`project/agents/README.md`](project/agents/README.md)

## Contributing

Start here:

- [`CONTRIBUTING.md`](CONTRIBUTING.md)
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
- [`SECURITY.md`](SECURITY.md)
- [`SUPPORT.md`](SUPPORT.md)

Branch and pull request workflow rules are defined in:

- [`agents/git-and-github.md`](agents/git-and-github.md)

## Community Standards

- bugs should be filed through GitHub issues
- feature work should be tied to a specification
- bug-fix work should be tied to an issue
- implementation work should happen on branches, not directly on `main`
- pull requests are required, even though formal review is not currently required for this repo

## License And Third-Party Notes

The repository includes third-party code and license material under [`third_party/`](third_party/) and supporting notes in:

- [`project/research/open-source-licensing-notes.md`](project/research/open-source-licensing-notes.md)
- [`OPEN_SOURCE_LICENSING_PLAN.md`](OPEN_SOURCE_LICENSING_PLAN.md)

A top-level project license has not yet been added in this pass.
