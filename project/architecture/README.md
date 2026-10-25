# Architecture

Current source structure, ownership and known limitations. Proposed changes belong in [GitHub design issues](../../docs/project-management.md), not in descriptions of implemented behavior. Reconciled against P4 production lineage `295677e` on October 25, 2026. Source implementation, bounded native evidence and final acceptance are separate; this index does not qualify an installed release.

- [System Overview](system-overview.md)
- [Document and Speech Pipeline](document-speech-pipeline.md)
- [Normalized Content and Position Mapping](normalized-content-and-position-mapping.md)
- [Speech Enrichment and Narration](speech-enrichment-and-narration.md)
- [Character Dialogue Attribution and Voice Casting](character-dialogue-attribution-and-voice-casting.md)
- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)
- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)
- [Engine Pronunciation Expression and Capability Adaptation](engine-pronunciation-expression-and-capability-adaptation.md)
- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)
- [Audio Artifact Identity and Lifetime](audio-artifact-identity-and-lifetime.md)
- [Playback Orchestration and Synthesis Boundaries](playback-orchestration-and-synthesis-boundaries.md)
- [Spoken Text Highlighting and Reading Focus](spoken-text-highlighting-and-reading-focus.md)
- [Audio Export and Headless Execution](audio-export-and-headless-execution.md)
- [Reader Interface and Session State](reader-interface-and-session-state.md)

The [legacy contract index](../specifications/README.md) links retained children directly to their owning architecture. Historical design prose is in [the archive](../archive/README.md).

## Evidence and acceptance limits

- [P0 baseline](https://github.com/kellyjanderson/readaloud/issues/49#issuecomment-6393427541): native arm64 toolchain and separated source/bundle/runtime asset provenance; cached runs do not attest fresh inference.
- [P1 preparation](https://github.com/kellyjanderson/readaloud/issues/50#issuecomment-6393533201): worker/revision tests and native input during a large preparation, replacement, publication and scrolling on bounded fixtures. Observation times are not frame-time bounds.
- [P2 resources](https://github.com/kellyjanderson/readaloud/issues/51): resident A/B/A resource/cleanup, failure and normal-app replay evidence. Retained handles, memory, emitted PCM and listening answer different questions.
- [P3 accepted working-branch integration](https://github.com/kellyjanderson/readaloud/issues/52#issuecomment-6395174262): bounded planning/synthesis and native queue/export matrix. The [copied-audio audit](https://github.com/kellyjanderson/readaloud/issues/52#issuecomment-6395019641) verifies complete emitted PCM concatenation; it does not prove acoustic continuity. Eight seconds is an admission threshold plus one in-flight chunk, not a hard maximum.
- [P4 accepted resource/cache run 2](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395918850): source `25f1dfe` adds a harness-only private-copy repair to the `295677e` production lineage. Actual resident stale-request rejection, unchanged-content reuse, same-ID voice-byte/model-digest misses, incomplete regeneration and corrupted metadata rejection passed. Four inferences, two balanced native session opens/closes, peak one session/four tensors and final zero/zero were recorded; this is not an isolated RSS or playback/acoustic benchmark. Failed run 1 remains a preserved copy-permission failure.
- [P4 assignment/input observations](https://github.com/kellyjanderson/readaloud/issues/53): immutable `295677e` recorded a full-buffer pending edit preserving the current source/hash, explicit Apply from exact chunk-start word 8, latest-only A/B/C initial startup and pause-retained/stop-cleared pins. At the recorded checkpoint the app was kept alive for the human listening step; these automated phases are not a terminal P4 pass. Modal open/Close and scrolling/Recenter were observed during playback, but every actual input had export inactive; producer ownership is not proof of CPU-heavy planning. File-menu dismissal, supplemental failure/export-input/frame acceptance and listening remain pending.
- [Bounded P4 modal/status smoke](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395513249): real app/control layering and named Close/status dismissal, with an identified status-only probe and API seam. It does not establish final assignment behavior; native Escape remains unproven.

P0–P3 have reached the working integration branch. This P4 source description is not a main merge or feature-completion claim. [FINAL](https://github.com/kellyjanderson/readaloud/issues/54) must reconcile required evidence and delivery before the [parent design](https://github.com/kellyjanderson/readaloud/issues/48) closes. `.radoc` writing remains an inspection export, with no reload decoder/cache.
