# Developer tools

Run commands from the repository root. Use `tools/flutter`, which bootstraps the
pinned writable SDK. Start with [development and verification](../docs/development.md)
or [MLX setup](../docs/mlx-tts-engines.md) for prerequisites and complete commands.

| Task | Entry points |
| --- | --- |
| Launch, build, analyze or test Flutter | `flutter`; `flutter_bootstrap.rb` is its implementation |
| Validate documentation / retrieve bounded GitHub context | `check_docs.rb`, `read_issue_context.rb` |
| Install/package the MLX Python runtime | `install_mlx_tts_runtime.sh`, `embed_mlx_runtime.sh`; pinned dependencies in `mlx_tts_requirements.txt` |
| Prepare and run isolated MLX playback | `prepare_mlx_playback_test_app.sh`, `run_mlx_playback_smoke.rb`, `mlx_playback_smoke.dart` |
| Probe Drama settings or document preparation | `drama_settings_smoke.dart`, `document_preparation_smoke.dart` |
| Check MLX worker behavior or benchmark synthesis | `mlx_tts_worker_test.py`, `mlx_tts_benchmark.py` |
| Maintain bundled reference voices | `build_voice_library.py`, `analyze_voice_library.py`, `qualify_voice_library.py` |
| Build, inspect and package macOS candidates | `build_macos_release.sh`, `package_macos_candidate.rb`, `verify_macos_release_entitlements.rb`, `release_notices.rb` |
| Summarize startup timing | `rc2_timing_report.rb` |
| Guide human acceptance and export observations | [human acceptance runner](human_acceptance_runner/README.md) |

## Retained native qualification probes

The P0–P4 names identify prepared-document implementation stages, not alternative
application entry points for daily use. They remain useful for reproducing linked
evidence and targeted regressions:

- `run_native_baseline.rb`: isolated native export baseline.
- `p2_native_probe.dart`, `run_p2_native_probe.rb`: resident session/tensor lifetime.
- `p2_native_failure_probe.dart`, `run_p2_native_failure_probe.rb`: failure paths.
- `p3_native_playback_probe.dart`: worker/planning playback boundary.
- `p4_native_assignment_probe.dart`, `p4_native_supplement_probe.dart`,
  `p4_resource_cache_probe.dart`, `p4_listening_app.dart`: assignment, cache,
  supplemental native and listening scenarios.

Read the relevant development/engine guide and issue acceptance contract before
running a probe. Native runs can require model assets, separate bundle identities
and isolated output directories. Preserve those boundaries and quit any owned
test app when finished. A probe result is not general audible-product acceptance.

Ruby `*_test.rb` files exercise their adjacent tool. Run Python tooling using the
managed environment documented in the MLX guide. Voice-generation and runtime
installation tools modify assets or environments; they are not cleanup commands.

`character_storage_smoke.dart` exercises the real macOS preferences/path-provider
plugins and per-work migration without loading speech models. Build it as a target
with `build_macos_release.sh`, copy the result, give the copy a fresh bundle ID
containing `characterStorageTest`, and re-sign with `Runner/Release.entitlements`.
Never run this target with the production identity. Pass one sandbox-writable JSON
receipt path to its executable; it refuses existing work storage. It seeds two
synthetic works, migrates, resets/reopens, removes one work file and verifies the
other work and global engine are unchanged. After the receipt, use normal Quit and
verify exit. This proves storage behavior, not attribution or audible Fish switching.

The optional [ModernBookNLP provider guide](../docs/modernbooknlp-provider.md) covers
`install_modernbooknlp_runtime.sh`, `prepare_modernbooknlp_assets.py`,
`evaluate_modernbooknlp.py` and `modernbooknlp_worker_test.py`. These use a separate
Python environment and persistent asset directory. `embed_modernbooknlp_runtime.sh`
packages that code; `modernbooknlp_app_smoke.dart` checks the opt-in background path
in an isolated `residentNlpTest` sandbox with silent speech. It must be followed by
normal Quit and app/child exit verification. Diagnostic analysis does not change
voices or dialogue, and none of these tools modifies the MLX runtime.

`modernbooknlp_persistence_smoke.dart` checks native analysis persistence, A/B/A
reuse and portable `.radoc` reopen without a model in a fresh working store. It
uses silent speech; follow the isolated bundle and normal-Quit instructions in the
[provider guide](../docs/modernbooknlp-provider.md#saved-book-analysis).

## Portable audio-book qualification

`tools/s6_acceptance_smoke.dart` combines two native entry points in one isolated
build: `BOOK.radoc RECEIPT.json` runs model-forbidden saved playback;
`fish_drama3 RECEIPT.json` runs real scene regeneration. Build with
`sh tools/build_macos_release.sh tools/s6_acceptance_smoke.dart`, then copy and
re-sign a separate QA bundle identity before running either probe. Restore
`lib/main.dart` for a normal application build.

`run_radoc_playback_smoke.rb APP_EXECUTABLE BOOK NEW_OUTPUT_DIRECTORY` checks
copied-book playback, publication/reopen, transport and resource shutdown.
`run_radoc_regeneration_smoke.rb APP_BUNDLE NEW_OUTPUT_DIRECTORY CAPTURE_EXECUTABLE`
checks a four-scene fixture, one Character voice edit, saved reuse and a missing
middle scene. It needs a working local Fish model/runtime and two distinct Fish
voices; `READALOUD_REGEN_VOICE_BEFORE` and `READALOUD_REGEN_VOICE_AFTER` select them.
Use a fresh output directory inside the QA sandbox container. The regeneration
probe isolates its Character and rendered-scene repositories. Both runners
request normal Quit and verify their owned processes have exited, including
failure paths.

Compile `capture_macos_app_audio.swift` for the capture executable. The runner
starts a separate app-only capture before each Play gate and stops it at source
completion. Compare emitted audio with the exact queued WAVs using
`compare_captured_dialogue.py` and the managed MLX Python. Internal source-end,
package hashes, native waveform comparison and human listening are distinct
checks. Controlled Play gates do not measure first-launch performance; the
ungated offline runner retains opening-to-native-position timestamps separately,
and those timestamps alone do not establish audible onset. Current acceptance
and remaining gates live in [S6 #137](https://github.com/kellyjanderson/readaloud/issues/137).

For opening-to-emitted-speech measurement, pass the compiled capture executable
as the offline runner's optional fourth argument. It starts app-only capture
immediately after launch and introduces no Play gate. Compare the capture with
the exact queued WAVs, then run
`ruby tools/summarize_startup_audio.rb NATIVE_OUTPUT_DIRECTORY COMPARISON_JSON NEW_RESULT_JSON`.
The report aligns the first captured signal with the expected speech and compares
its callback receipt against the process launch using `CLOCK_MONOTONIC_RAW`.
This supplies a conservative upper bound for app-emitted speech, not physical
speaker latency. Verify a complete candidate and fresh-profile provenance
separately; a diagnostic build missing required runtimes cannot pass acceptance.

The combined target also accepts `runtime-cancel RUNTIME_ID RECEIPT.json` and
`booknlp RECEIPT.json`. Use `run_packaged_runtime_smoke.rb APP_BUNDLE NEW_OUTPUT_DIRECTORY runtime-cancel mlx`
(or `modernbooknlp`) to cancel real first-use extraction in an isolated sandbox.
The probe uses its own support directory and verifies consumer cancellation,
staging cleanup, progress suppression and resource drain; it launches no model.
Use the runner's `booknlp` mode with the existing `residentNlpTest` QA identity
and qualified local analysis models for the real persistence/reuse scenario.
These probes require normal Quit and process cleanup even on failure.
