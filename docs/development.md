# Development and verification

The documented baseline is Flutter 3.41.5 / Dart 3.11.3. Use an SDK matching your machine architecture. The ignored `.flutter-sdk` is not a clean-clone prerequisite: inspect `file <sdk>/bin/cache/dart-sdk/bin/dart` and run `<sdk>/bin/flutter --version` before testing. An Intel SDK fails with `bad CPU type in executable` on an arm64 host without Intel execution support. Install the matching arm64 release from the official Flutter archive instead of upgrading project dependencies.

Install Xcode and CocoaPods for macOS development, run `flutter pub get`, and supply the compatible model described in [model setup](../assets/kokoro/model/README.md). Model weights are not committed. Voices and pronunciation resources are bundled; ONNX uses the [vendored override](../third_party/flutter_onnxruntime/pubspec.yaml).

```sh
flutter analyze
flutter test
flutter run -d macos
flutter build macos
ruby tools/check_docs.rb
```

Run focused tests first when changing one subsystem. Native session lifetime, actual audio output and visible UI responsiveness require running-app/native checks. Pure Dart or widget tests do not establish these. Generated outputs remain ignored under `project/test-artifacts/` and `tmp/`.

For native accessibility checks, launch the exact isolated app bundle in the foreground before acquiring its AX tree. Background acquisition can time out or return stale observations; foreground launch is a diagnostic prerequisite, not proof that the app fixes that behavior. Verify named transport buttons and their state changes through actual actions. Keep native action evidence separate from widget semantics and keyboard tests.

See [architecture](../project/architecture/README.md) for source/test locations and [contributing](../CONTRIBUTING.md) for the GitHub planning workflow. No current fresh test-pass or release qualification is implied by this setup guide.

## Native baseline diagnostics

If old generated files are read-only, preserve them outside their generated locations and rerun `flutter pub get`. Check the exact failing path; do not recursively change permissions on the repository or user data. Keep dependency lockfiles unchanged unless a dependency change is intended.

Xcode 27 rejects some dependencies' older macOS deployment targets. For a local baseline on a supported host, after dependency resolution, a command-scoped override can build without changing the project's supported-platform declaration:

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -derivedDataPath build/macos \
  -destination 'platform=macOS,arch=arm64' \
  MACOSX_DEPLOYMENT_TARGET=12.0 build
```

The vendored macOS ONNX plugin accepts `READALOUD_ORT_RESOURCE_TRACE=1` in the launched process environment. It logs `READALOUD_ORT` records containing the completed method, retained session count, retained tensor count and error flag. Snapshots run on the existing serial ONNX queue before the result is handed to Flutter. This opt-in diagnostic does not release resources or change inference behavior. Use uncached inputs and preserve model/voice hashes when comparing runs; cached audio does not exercise native inference. Counts describe plugin retention, not total process memory or successful disposal. Collect process memory separately and keep emitted WAV evidence distinct from audible playback/transport evidence.

The P0 startup-selection characterization deliberately captures the current defect (A can start after selecting B then C); it is not acceptance of that behavior. Replace its expectation with latest-revision acceptance when implementing [P4](https://github.com/kellyjanderson/readaloud/issues/53). Baseline results and blockers live in [P0](https://github.com/kellyjanderson/readaloud/issues/49).

For an isolated export baseline, add `PRODUCT_BUNDLE_IDENTIFIER=com.kellyjanderson.readAloud.p0` to the build command. Then run `ruby tools/run_native_baseline.rb <app-executable> <new-output-directory>`. Use a new directory inside `~/Library/Containers/com.kellyjanderson.readAloud.p0/Data/tmp/` so the sandbox can access the copied fixture and output. The harness requires this separate bundle identity, records asset fingerprints, routes, native counters and sampled RSS, and bounds export to 120 seconds. It terminates its child after the export summary (with a five-second termination grace); that termination is explicitly not proof of native cleanup. It never clears caches, so inspect native inference records to distinguish cold from cached runs. Decode and inspect the WAV separately before claiming emitted-audio validity.
