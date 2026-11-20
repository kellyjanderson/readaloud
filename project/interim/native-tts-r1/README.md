# Native TTS bindings draft R1

Unpublished proposal, November 20, 2026 Pacific. Draft author and owner: Codex in the planning chat. Source issue: [#111 Drama 3 speech runtime](https://github.com/kellyjanderson/readaloud/issues/111), under [#110](https://github.com/kellyjanderson/readaloud/issues/110). Related ownership: [#112 model lifecycle](https://github.com/kellyjanderson/readaloud/issues/112), [#113 concurrency](https://github.com/kellyjanderson/readaloud/issues/113), and [#127 optional character analysis](https://github.com/kellyjanderson/readaloud/issues/127). Implementation baseline: `fd1df4c58c09870258a84e2975a7f6b51402d4f9` on `codex/remaining-slices-integration`.

The project uses Flutter/Dart modules to bind directly to native engines, including writing a thin binding when required. See the [repository directive](../../../AGENTS.md#flutterdart-platform-and-native-bindings). The requested deliverables are education and planning. The first proposed target is an Apple Silicon Fish Drama 3 speech route that needs no Python interpreter at runtime. Whether to remove Python from the entire product, including optional ModernBookNLP analysis, is a separate decision. This draft proposes work after scope review by the coordinator. The issue and accepted release scope continue to govern active delivery.

The user designated [all Kokoro-specific paths deprecated](../../../docs/speech-runtime-and-python.md#kokoro-deprecation). The native migration targets non-Kokoro synthesis.

- [Current runtime walkthrough](../../../docs/speech-runtime-and-python.md)
- [Native runtime research](../../research/native-tts-runtimes.md)
- [Architecture draft](design.md)
- [Implementation and qualification plan](implementation-plan.md)
- [Canonical .radoc and audio placement draft](../radoc-pipeline-r1/README.md)
