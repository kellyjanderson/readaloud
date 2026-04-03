# Open Source Licensing Notes

Last updated: March 29, 2026
Status: Active research notes

## Scope

These are project research notes, not formal legal advice.

## Kokoro

Current working reading:

- the `hexgrad/Kokoro-82M` model page marks the model as `apache-2.0`

Practical implications for the project:

- ship the Apache 2.0 license text
- preserve relevant notices
- propagate `NOTICE` content if upstream provides it
- track whether bundled model or voice assets have been modified

Current non-requirement:

- Apache 2.0 does not require a permanent “Powered by Kokoro” banner in the playback UI

## Current Runtime Dependencies

- `kokoro_tts_flutter`: MIT
- `malsami`: MIT
- `flutter_onnxruntime`: MIT for the Dart wrapper, native runtime obligations still need verification
- `just_audio`: MIT for the Dart package, native backend obligations still need verification
- `file_open`: MIT
- `cmudict`: BSD-style Carnegie Mellon license; license text vendored in `third_party/cmudict/LICENSE`

## Research Follow-Ups

- verify whether the exact Kokoro asset distribution used by the app includes a `NOTICE`
- verify ONNX Runtime native notice requirements
- verify packaged audio backend notice requirements
- decide whether notices should be curated manually or generated from a maintained manifest
