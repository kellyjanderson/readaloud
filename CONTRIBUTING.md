# Contributing To Read Aloud

Thanks for contributing.

## Before You Start

Read:

- [`README.md`](README.md)
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
- [`SECURITY.md`](SECURITY.md)
- [`agents/git-and-github.md`](agents/git-and-github.md)
- [`project/README.md`](project/README.md)

## Branch Rules

Do not make implementation changes directly on `main`.

Use:

- `bugfix/<issue-id>-<short-description>` for defect work
- `feature/<short-spec-slug>` for feature work

Bug-fix branches must link to an issue.

Feature branches must link to a specification.

## Pull Requests

All branch work should land through a pull request.

For the current team shape:

- pull requests are still required
- formal review is not required
- anyone may merge the pull request

## Local Setup

1. Install Flutter `3.41.5`.
2. Run `flutter pub get`.
3. Place the Kokoro model file at:

```text
assets/kokoro/model/kokoro-v1.0.onnx
```

Model setup notes:

- [`assets/kokoro/model/README.md`](assets/kokoro/model/README.md)

## Running

macOS is the only currently validated target.

```bash
flutter run -d macos
```

## Validation

At minimum, use the checks relevant to your change:

```bash
flutter analyze
flutter test
```

For pronunciation, synthesis, and speech-quality changes, follow the project audio-verification rule in:

- [`project/agents/README.md`](project/agents/README.md)

Do not call a speech fix successful if the emitted audio did not materially change or if that verification was not performed.

## Docs And Specs

This repository uses durable product and system documents.

Relevant folders:

- [`project/architecture/`](project/architecture/)
- [`project/specifications/`](project/specifications/)
- [`project/planning/`](project/planning/)
- [`project/research/`](project/research/)

If your work changes behavior, update the relevant durable docs alongside the implementation.
