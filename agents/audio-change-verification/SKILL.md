---
name: audio-change-verification
description: Verify that pronunciation, synthesis, or other speech-output changes in Read Aloud produce a real audio change before claiming the fix worked.
---

# Audio Change Verification

Use this Skill for pronunciation, synthesis, and other speech-output fixes.

## Verification Rule

Do not claim a speech-output fix succeeded unless you verify that the emitted audio materially changed.

The workflow is:

1. capture a baseline audio run for the target phrase or phrases
2. make the code change
3. capture a second run for the same phrases
4. compare the before and after outputs

## Preferred Method

Prefer the existing headless pronunciation probe path and compare PCM hashes or equivalent waveform-level analysis instead of relying only on code inspection or casual listening.

## Reporting Rule

When reporting speech-output work, state whether:

* the emitted audio changed
* the emitted audio did not change
* or audio change verification was not completed
