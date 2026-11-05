# Development and verification

## Native app test-session cleanup

Agents running UI, native, playback or acceptance checks must quit Read Aloud when each test session ends, including failed or blocked runs. Use the app's normal Quit action, then verify the exact test-build process has exited before finishing the test or development task. Do not leave the app running between cases. Record an inability to close or verify as a blocker. The [human acceptance runner](../tools/human_acceptance_runner/README.md) requires this closure record before an app-used test counts as complete.

The `tools/flutter` launcher bootstraps Flutter 3.41.5 / Dart 3.11.3 from the [official Flutter SDK archive](https://docs.flutter.dev/install/archive). It pins the archive hash and framework revision, selects the native Mac architecture (including Apple Silicon from a Rosetta terminal), and uses `.readaloud-tools/flutter-3.41.5-<architecture>` with a separate project-local `pub-cache`. Existing `.flutter-sdk/` and global caches are not prerequisites and are left untouched. `tools/flutter --version` verifies the resulting toolchain. With no arguments, or with `-d macos`, the launcher runs the app.

Installation happens in a unique staging directory; a failed download or checksum never publishes a partial SDK. An incompatible installed tree is preserved beside its replacement. Read-only permissions are repaired only within the managed tool directory. An OS file lock serializes installation/repair; shared leases allow concurrent healthy invocations and prevent replacing an SDK while Flutter is running. The lease is released on process exit, including crashes. The first SDK download needs network access; subsequent launches reuse the verified installation. Package resolution remains Flutter's responsibility and uses the writable project-local cache.

Install Xcode and CocoaPods for macOS development, run `tools/flutter pub get`, and supply the compatible model described in [model setup](../assets/kokoro/model/README.md). Model weights are not committed. Voices and pronunciation resources are bundled; ONNX uses the [vendored override](../third_party/flutter_onnxruntime/pubspec.yaml).

```sh
tools/flutter analyze
tools/flutter test
tools/flutter run -d macos
tools/flutter build macos
ruby tools/check_docs.rb
```

Run focused tests first when changing one subsystem. Native session lifetime, actual audio output and visible UI responsiveness require running-app/native checks. Pure Dart or widget tests do not establish these. Generated outputs remain ignored under `project/test-artifacts/` and `tmp/`.

The expandable voice-selection contract uses stable `VS` case IDs. Run:

```sh
tools/flutter test test/character_voice_selection_contract_test.dart test/character_analysis_adapter_test.dart test/reader_document_serialization_service_test.dart test/reader_preferences_service_test.dart test/reader_voice_assignment_revision_test.dart
```

Keep these cases when replacing attribution providers. Add prose-to-character
oracles separately so wrong attribution cannot pass merely because a wrong
character consistently uses one voice. The native smoke accepts
`READALOUD_SMOKE_CHARACTER=Mara` with a City fixture path: it selects an alternate
compatible voice, reopens the source, and requires the chosen voice in prepared
references and played character turns. `READALOUD_SMOKE_NORMAL_QUIT=1` leaves the
finished test app alive after writing its receipt so the driver can issue normal
Quit and verify exit. This flag requires a supervising driver; it is not for an
unattended launch without cleanup. Existing smoke defaults remain self-cleaning.

For native accessibility checks, launch the exact isolated app bundle in the foreground before acquiring its AX tree. Background acquisition can time out or return stale observations; foreground launch is a diagnostic prerequisite, not proof that the app fixes that behavior. Verify named transport buttons and their state changes through actual actions. Keep native action evidence separate from widget semantics and keyboard tests.

See [architecture](../project/architecture/README.md) for source/test locations and [contributing](../CONTRIBUTING.md) for the GitHub planning workflow. No current fresh test-pass or release qualification is implied by this setup guide.

## Native baseline diagnostics

If old generated files are read-only, preserve them outside their generated locations and rerun `tools/flutter pub get`. Check the exact failing path; do not recursively change permissions on the repository or user data. Keep dependency lockfiles unchanged unless a dependency change is intended.

Xcode 27 rejects some dependencies' older macOS deployment targets. For a local baseline on a supported host, after dependency resolution, a command-scoped override can build without changing the project's supported-platform declaration:

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -derivedDataPath build/macos \
  -destination 'platform=macOS,arch=arm64' \
  MACOSX_DEPLOYMENT_TARGET=12.0 build
```

The vendored macOS ONNX plugin accepts `READALOUD_ORT_RESOURCE_TRACE=1` in the launched process environment. It logs `READALOUD_ORT` records containing the completed method, retained session count, retained tensor count and error flag. Snapshots run on the existing serial ONNX queue before the result is handed to Flutter. This opt-in diagnostic does not release resources or change inference behavior. Use uncached inputs and preserve model/voice hashes when comparing runs; cached audio does not exercise native inference. Counts describe plugin retention, not total process memory or successful disposal. Collect process memory separately and keep emitted WAV evidence distinct from audible playback/transport evidence.

The historical P0 startup-selection characterization captured A starting after B/C edits; it was a baseline defect, not accepted behavior. Current P4 source tests require latest-only initial startup and separate requested/effective choices. Read [voice behavior](reading-and-voice-choices.md) and the [evidence index](../project/architecture/README.md#evidence-and-acceptance-limits); integrated native assignment/audio/frame acceptance remains in [P4](https://github.com/kellyjanderson/readaloud/issues/53) and [FINAL](https://github.com/kellyjanderson/readaloud/issues/54). Baseline provenance remains in [P0](https://github.com/kellyjanderson/readaloud/issues/49).

For an isolated export baseline, add `PRODUCT_BUNDLE_IDENTIFIER=com.kellyjanderson.readAloud.p0` to the build command. Then run `ruby tools/run_native_baseline.rb <app-executable> <new-output-directory>`. Use a new directory inside `~/Library/Containers/com.kellyjanderson.readAloud.p0/Data/tmp/` so the sandbox can access the copied fixture and output. The harness requires this separate bundle identity, records asset fingerprints, routes, native counters and sampled RSS, and bounds export to 120 seconds. It terminates its child after the export summary (with a five-second termination grace); that termination is explicitly not proof of native cleanup. It never clears caches, so inspect native inference records to distinguish cold from cached runs. Decode and inspect the WAV separately before claiming emitted-audio validity.

`run.json` separates checkout (`source`), app-bundle (`bundled`), and Application Support (`runtime_before`/`runtime_after`) asset snapshots. Each observed file records its absolute and resolved paths, size and SHA-256. Runtime files live under the required bundle's sandbox container at `Data/Library/Application Support/com.kellyjanderson.readAloud.p0/kokoro/`; the model loader and voice manager reuse installed files there, which may differ from a newer checkout or build. `asset_comparisons` reports source/bundle and bundle/runtime equality independently; `null` means missing evidence, not equality. Missing, empty or unreadable required runtime assets, a changed runtime digest during the probe, or missing route evidence make the harness fail even if export succeeded. Source/bundle mismatches remain explicit observations and do not overwrite runtime provenance. Files created during startup have no before/after stability proof. These filesystem observations are not per-inference attestation: especially when `inference_observed` is false, cached WAV provenance cannot be inferred from current asset hashes. Preserve the snapshots and native log together when comparing runs.

## Resident resource validation

Build the P2 lifetime probe with `tools/flutter build macos --debug -t tools/p2_native_probe.dart`, then use the command-scoped Xcode workaround above with `PRODUCT_BUNDLE_IDENTIFIER=com.kellyjanderson.readAloud.p2`. Run `ruby tools/run_p2_native_probe.rb <app-executable> <new-container-output-directory>`, choosing a new path inside `~/Library/Containers/com.kellyjanderson.readAloud.p2/Data/tmp/`. It runs 300 uncached A/B/A chunks and six close-cycle chunks, records actual asset/PCM hashes and RSS, requires native session/tensor bounds and normal close, and strictly decodes every WAV with ffmpeg. Model weights remain local prerequisites. This probe establishes resource lifetime and emitted PCM validity; it does not establish audible continuity or provider quality. Restore the ordinary app entry point before subsequent user-interface builds.

For the automatic-selection native case, add `READALOUD_SMOKE_AUTO_VOICE_CHANGE=1`
to the existing named-character City excerpt probe. It selects another compatible
Fish voice during active playback, never calls Apply, and requires a current engine
acknowledgment, new selected binding and a completed selected-character turn.
This proves the routing path, not perceived age/timbre or smooth switching. Keep
`READALOUD_SMOKE_NORMAL_QUIT=1` and verify the cleanup receipt.
