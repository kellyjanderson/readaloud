# Test Artifacts

This directory is the stable project-owned home for generated test and debug
artifacts that should persist across app runs while we are iterating on speech
quality.

Current subdirectories:

- `tts-debug-traces/` for live playback phoneme/input trace logs
- `pronunciation-probes/` for headless pronunciation probe WAVs, manifests, and
  before/after comparison reports
- `sentence-probes/` for imported-document sentence-by-sentence WAV exports,
  manifests, and combined run logs

These files are intentionally generated inside the repository instead of an
ephemeral app container path so they remain easy to inspect from the editor and
easy to compare across runs.
