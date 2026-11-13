# Support

macOS on Apple Silicon is the functional target. Start with [setup](docs/development.md) and the [engine support matrix](docs/mlx-tts-engines.md#support-and-evidence). Selecting a model or building the app does not establish native qualification. The current development candidate is unreleased; M3 and current human acceptance remain open under [release #122](https://github.com/kellyjanderson/readaloud/issues/122).

For an engine/setup report, include the app commit/build, macOS and chip/RAM, selected engine/model revision, bundled runtime or explicit override, exact action and observed error. Share a synthetic reproducer and cleared screenshots; keep private manuscripts and recordings local. A missing packaged MLX runtime is a setup prerequisite failure.

## Getting Help


Use GitHub issues for:

- bug reports
- feature requests
- documentation gaps
- setup problems that are specific to this repository

Before opening an issue, check:

- [`README.md`](README.md)
- [`CONTRIBUTING.md`](CONTRIBUTING.md)
- [`assets/kokoro/model/README.md`](assets/kokoro/model/README.md)
- [`project/README.md`](project/README.md)

## Security

Do not use public issues for security reports.

Use:

- [`SECURITY.md`](SECURITY.md)
