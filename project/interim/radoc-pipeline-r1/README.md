# Canonical .radoc pipeline draft R1

Unpublished, November 20, 2026 Pacific. Draft author and owner is Codex in the planning chat. The source baseline is `fd1df4c58c09870258a84e2975a7f6b51402d4f9` on `codex/remaining-slices-integration`. Related issue ownership is [#110 pipeline direction](https://github.com/kellyjanderson/readaloud/issues/110), [#127 ModernBookNLP](https://github.com/kellyjanderson/readaloud/issues/127), [#137 audio-only .radoc](https://github.com/kellyjanderson/readaloud/issues/137) and [#135 follow-on timing](https://github.com/kellyjanderson/readaloud/issues/135).

Use one canonical .radoc document representation for every downstream consumer. Prepare it progressively for interactive Open, with offline full conversion available when explicitly requested. Reuse qualified ModernBookNLP structure for linguistic cut candidates. Place audio by sample-frame timing so storage and transport boundaries carry zero implied pause. Evaluate FLAC, standard ALAC and NARALAC for durable lossless audio. Apply the [Flutter/Dart platform directive](../../../AGENTS.md#flutterdart-platform-and-native-bindings) to all native dependencies.

- [Design and current behavior comparison](design.md)
- [Migration and acceptance plan](implementation-plan.md)
- [Native synthesis binding draft](../native-tts-r1/README.md)
- [Lossless audio research](../../research/radoc-lossless-audio.md)

This is a follow-on design proposal for review. The [R23 release decision](https://github.com/kellyjanderson/readaloud/issues/110#issuecomment-6674071097) places advanced timing after the current audio-only release. Existing issue scope and qualification continue under their owning coordinators.
