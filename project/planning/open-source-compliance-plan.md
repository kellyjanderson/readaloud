# Open Source Compliance Plan

Last updated: March 29, 2026
Status: Active plan

## Objective

Turn current licensing notes into a release-ready compliance workflow for shipped dependencies, bundled assets, and downloadable runtime assets.

## Deliverables

- `third_party/licenses/` directory
- curated notice set for shipped dependencies and assets
- in-app `Open Source Notices` screen
- installer or package notice inclusion where supported

## Current Work Items

- copy applicable license texts for shipped components
- verify whether bundled Kokoro assets require propagation of a `NOTICE` file
- verify native ONNX Runtime notice obligations separately from the Dart wrapper
- verify native audio backend notice obligations separately from the Dart wrapper
- decide whether notice generation is lockfile-driven or curated

## Known Components To Cover

- `hexgrad/Kokoro-82M`
- `kokoro_tts_flutter`
- `malsami`
- `flutter_onnxruntime`
- `just_audio`
- `file_open`

## Exit Criteria

- every shipped third-party component has a recorded source and license
- required notices are available in-repo and in-app
- release packaging has a clear compliance checklist
