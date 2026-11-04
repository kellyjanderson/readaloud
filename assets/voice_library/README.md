# Synthetic reference voice bank

Thirty fictional speaker references generated locally with Qwen3-TTS 1.7B
VoiceDesign. No personal recordings or celebrity identities are used.
`library.json` records each reference's description, seed, transcript, duration,
SHA-256, and the pinned source checkpoint revision. The descriptions and accents
are generation intentions, not independently certified speaker demographics.

Build with the managed MLX Python and `tools/build_voice_library.py`. The source
model is distributed under Apache 2.0:
https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign

Qwen Base and MOSS condition synthesis on these WAVs. These are reference
identities, not pretrained speaker IDs from those engines. Cross-engine speaker
similarity and pronunciation require acoustic evaluation. The assets permit a
shared selection for comparison while preserving each engine's synthesis.
