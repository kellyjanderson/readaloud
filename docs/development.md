# Development and verification

The documented baseline is Flutter 3.41.5 / Dart 3.11.3. Use an SDK matching your machine architecture; the ignored local `.flutter-sdk` is not part of a clean clone and its current Intel Dart binary cannot run in the review environment. Establish a passing baseline before upgrading libraries.

Install Xcode and CocoaPods for macOS development, run `flutter pub get`, and supply the compatible model described in [model setup](../assets/kokoro/model/README.md). Model weights are not committed. Voices and pronunciation resources are bundled; ONNX uses the [vendored override](../third_party/flutter_onnxruntime/pubspec.yaml).

```sh
flutter analyze
flutter test
flutter run -d macos
flutter build macos
ruby tools/check_docs.rb
```

Run focused tests first when changing one subsystem. Native session lifetime, actual audio output and visible UI responsiveness require running-app/native checks. Pure Dart or widget tests do not establish these. Generated outputs remain ignored under `project/test-artifacts/` and `tmp/`.

See [architecture](../project/architecture/README.md) for source/test locations and [contributing](../CONTRIBUTING.md) for the ACD/plan workflow. No current fresh test-pass or release qualification is implied by this setup guide.
